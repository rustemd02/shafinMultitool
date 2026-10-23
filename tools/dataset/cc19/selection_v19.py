"""Conservative, label-independent policy eligibility for the frozen CC19 corpus.
Raw files stay immutable. Four whole topology groups are excluded, rather than
calling suspicious pairs 'independent' without visual adjudication.
"""
from __future__ import annotations
import collections,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'cc17'))
import cc18_dataset as D
BASE_AUDIT=D.audit
EXCLUDED_GROUPS=frozenset({'cc18-topology-0-1','cc18-topology-0-6','cc18-topology-2-5','cc18-topology-6-6'})
SOURCE_PAIRS=[{'a':'cc18-000136','b':'cc18-000176','distance':3},{'a':'cc18-000426','b':'cc18-000246','distance':4}]
EXPECTED_COUNTS={'policy_rows':3353,'split:train':2184,'split:validation':392,'split:test':777}

def eligible(row):return row['origin_group'] not in EXCLUDED_GROUPS

def batches(root:Path,split:str='train',batch_size:int=8):
    """Actual X/Y/loss-mask batches; no excluded group enters any selected split."""
    if split not in {'train','validation','test'} or batch_size<1:raise ValueError('Invalid split/batch size')
    for file in sorted(Path(root).rglob('inputs.jsonl')):
        component=file.parent;targets={t['record_id']:t for t in D.lines(component/'targets.jsonl')}
        rows=[r for r in D.lines(file) if eligible(r) and r['split']==split]
        for i in range(0,len(rows),batch_size):yield D.load_batch(component,rows[i:i+batch_size],targets)

def audit_selection(root:Path,batch_size:int=8):
    root=Path(root);source=BASE_AUDIT(root,batch_size)
    if source['counts']['policy_rows']!=3577:raise ValueError('Unexpected corpus; do not silently reuse the frozen exclusion policy')
    counts=collections.Counter();excluded=collections.Counter();groups=collections.defaultdict(set);scene_groups={};actual_batches=0;seen=set()
    for file in sorted(root.rglob('inputs.jsonl')):
        component=file.parent;targets={t['record_id']:t for t in D.lines(component/'targets.jsonl')};rows=[]
        for row in D.lines(file):
            scene=row['provenance']['scene_id'];group=row['origin_group']
            if scene in scene_groups and scene_groups[scene]!=group:raise ValueError('Scene origin inconsistency')
            scene_groups[scene]=group
            if not eligible(row):excluded[group]+=1;continue
            rid=row['record_id']
            if rid in seen:raise ValueError('Duplicate selected record ID')
            seen.add(rid);rows.append(row);counts['policy_rows']+=1;counts['split:'+row['split']]+=1;counts['decision:'+targets[rid]['decision']]+=1;groups[row['split']].add(group)
        for i in range(0,len(rows),batch_size):D.load_batch(component,rows[i:i+batch_size],targets);actual_batches+=1
    assert set(excluded)==EXCLUDED_GROUPS and sum(excluded.values())==224
    assert all(counts[k]==v for k,v in EXPECTED_COUNTS.items()),dict(counts)
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    source_pairs=source['dhash_review_candidates']
    expected={(p['a'],p['b'],p['distance']) for p in SOURCE_PAIRS}
    assert {(p['a'],p['b'],p['distance']) for p in source_pairs}==expected,'The underlying screen changed; review before admitting data'
    remaining=[p for p in source_pairs if scene_groups[p['a']] not in EXCLUDED_GROUPS and scene_groups[p['b']] not in EXCLUDED_GROUPS]
    assert not remaining
    return {'schema':'cc19.filtered_policy_consumer.v1','counts':dict(counts),'actual_batches':actual_batches,'batch_size':batch_size,
       'source_rows':3577,'excluded_rows':sum(excluded.values()),'excluded_groups':sorted(EXCLUDED_GROUPS),
       'selected_scene_configurations':sum(g not in EXCLUDED_GROUPS for g in scene_groups.values()),
       'conservative_groups_by_split':{k:len(v) for k,v in groups.items()},'source_dhash_candidates':source_pairs,
       'remaining_cross_split_screening_candidates':remaining,'resolution':'whole-origin-group quarantine without claiming visual adjudication',
       'source_full_consumer_receipt':source,'model_calls':0,'human_utility_gate':'BLOCKED','full_cameracoach_training_ready':False}

def selection_metadata_test():
    """Check the frozen generator's documented ID/group formula, not fake media."""
    counts=collections.Counter();excluded=[];allowed=[]
    for index in range(512):
        if index==114:continue  # Previously quarantined ray-depth failure.
        family=index%8;topology=(index//8)%8;group=f'cc18-topology-{family}-{topology}'
        split='train' if topology<5 else 'validation' if topology==5 else 'test'
        row={'origin_group':group};scene=f'cc18-{index:06d}'
        if eligible(row):allowed.append(scene);counts['split:'+split]+=7
        else:excluded.append(scene)
    assert len(allowed)==479 and len(excluded)==32
    assert {k:counts[k] for k in ['split:train','split:validation','split:test']}=={k:EXPECTED_COUNTS[k] for k in ['split:train','split:validation','split:test']}
    for pair in SOURCE_PAIRS:assert pair['a'] in excluded and pair['b'] in excluded
    return {'schema':'cc19.selection_metadata_check.v1','method':'frozen deterministic ID/topology mapping plus actual joint screening pairs',
      'allowed_scene_configurations':len(allowed),'excluded_scene_configurations':len(excluded),
      'allowed_policy_rows':sum(counts.values()),'expected_split_rows':dict(counts),
      'excluded_groups':sorted(EXCLUDED_GROUPS),'excluded_scene_ids':excluded,
      'source_pairs':SOURCE_PAIRS,'model_calls':0,'new_dataset_records_created':0,
      'full_selected_pixel_batch_execution_in_this_metadata_test':False}

if __name__=='__main__':print(json.dumps(selection_metadata_test(),indent=2))
