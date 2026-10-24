"""Strict sanitation of a native timestamp/SE3 table, retaining row-level reasons.
Only nonfinite/invalid rows and all conflicting same-time measurements are removed.
Identical timestamp+pose repeats are coalesced; unsorted rows are sorted without
changing measurements. Gaps are still rejected by the 30ms interpolation gate.
"""
from __future__ import annotations
import hashlib,json
import numpy as np

def clean_groundtruth(raw):
    data=np.asarray(raw,dtype=np.float64)
    if data.ndim!=2 or data.shape[1]!=8:raise ValueError('Expected native timestamp tx ty tz qx qy qz qw')
    decisions=[];valid=[]
    for i,row in enumerate(data):
        reason=None
        if not np.isfinite(row).all():reason='nonfinite_native_pose'
        elif np.linalg.norm(row[4:])<1e-8:reason='zero_quaternion'
        elif abs(np.linalg.norm(row[4:])-1.)>.02:reason='nonunit_quaternion_gt_over_2_percent'
        if reason:decisions.append({'native_numeric_row':i,'reason':reason})
        else:valid.append(i)
    buckets={}
    for i in valid:buckets.setdefault(float(data[i,0]),[]).append(i)
    selected=[]
    for stamp,ids in sorted(buckets.items()):
        if len(ids)==1:selected.append(ids[0]);continue
        values=data[ids,1:]
        # Byte-identical measurements only; sign-opposite quaternions are not
        # silently equated because the native observation event may differ.
        if all(np.array_equal(values[0],v) for v in values[1:]):
            selected.append(ids[0]);decisions.extend({'native_numeric_row':i,'reason':'identical_duplicate_timestamp_and_pose','retained_row':ids[0]} for i in ids[1:])
        else:decisions.extend({'native_numeric_row':i,'reason':'conflicting_poses_at_same_timestamp','timestamp':stamp} for i in ids)
    clean=data[selected]
    if len(clean)<3:raise ValueError('Too few trusted native poses')
    if not np.all(np.diff(clean[:,0])>0) or not np.isfinite(clean).all():raise ValueError('Clean trajectory failed strict validation')
    counts={}
    for d in decisions:counts[d['reason']]=counts.get(d['reason'],0)+1
    finite_times=data[np.isfinite(data[:,0]),0]
    report={'native_rows':len(data),'retained_rows':len(clean),'excluded_or_coalesced_rows':len(decisions),'native_timestamp_nonincreasing_count':int(np.sum(np.diff(finite_times)<=0)),
       'row_reordered':selected!=sorted(selected),'reasons':counts,'row_decisions':decisions,'clean_pose_array_sha256':hashlib.sha256(clean.tobytes()).hexdigest(),
       'source_bytes_modified':False,'interpolation_gap_threshold_s':.03,'quality_criteria_relaxed':False}
    return clean,report

def regression():
    good=np.array([[i*.01,0,0,0,0,0,0,1] for i in range(5)],float)
    out,q=clean_groundtruth(good[::-1]);assert np.array_equal(out,good) and q['row_reordered']
    out,q=clean_groundtruth(np.vstack([good,good[2]]));assert len(out)==5 and q['reasons']['identical_duplicate_timestamp_and_pose']==1
    conflict=good[2].copy();conflict[1]=1;out,q=clean_groundtruth(np.vstack([good,conflict]));assert len(out)==4 and q['reasons']['conflicting_poses_at_same_timestamp']==2
    invalid=good[0].copy();invalid[2]=np.nan;out,q=clean_groundtruth(np.vstack([good,invalid]));assert len(out)==5 and q['reasons']['nonfinite_native_pose']==1
    print('CC21_TRAJECTORY_SANITATION_REGRESSIONS_PASS')
if __name__=='__main__':regression()
