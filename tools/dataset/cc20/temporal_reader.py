"""Strict data-only temporal loader: no Blender, torch, models, future or GT inputs."""
from __future__ import annotations
import collections,hashlib,json,random
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps

def read_jsonl(path):
    with Path(path).open() as f:
        for line in f:
            if line.strip():yield json.loads(line)
def safe(root,rel):
    p=(Path(root)/rel).resolve()
    if not p.is_relative_to(Path(root).resolve()):raise ValueError('Path escapes dataset')
    return p

def batches(root,split='train',batch_size=8):
    root=Path(root);ys={x['record_id']:x for x in read_jsonl(root/'targets.jsonl')};records=[x for x in read_jsonl(root/'inputs.jsonl') if x['split']==split]
    if split not in ['train','validation','test']:raise ValueError('Unknown split')
    for offset in range(0,len(records),batch_size):
        xs=[];taps=[];tapknown=[];goals=[];goalfields=[];candidates=[];avail=[];success=[];masks=[];decisions=[];tm=[]
        for row in records[offset:offset+batch_size]:
            o=row['observations'];y=ys[row['record_id']]
            if set(o)!={'history','subject_tap_xy','intent','equipment','candidate_actions','candidate_available','observation_cutoff_s'}:raise ValueError('Unexpected policy input')
            hist=o['history']
            if len(hist)!=3 or [h['t_s'] for h in hist]!=[-.4,-.2,0.] or o['observation_cutoff_s']!=0:raise ValueError('Noncausal input')
            frames=[]
            for h in hist:
                p=safe(root,h['path'])
                if 'prefix_' not in p.name:raise ValueError('Post-action frame forbidden')
                with Image.open(p) as im:
                    frames.append(np.asarray(ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR),dtype=np.float32).transpose(2,0,1)/255.)
            xs.append(np.stack(frames));tm.append([h['t_s'] for h in hist]);taps.append(o['subject_tap_xy'] or [0.,0.]);tapknown.append(o['subject_tap_xy'] is not None)
            g=o['intent'];keys=['min_visible','max_visible','max_center_shift','height_min','height_max']
            goals.append([float(g.get(k,0)) if g else 0. for k in keys]+[float(bool(g and g['temporal']=='all_samples'))]);goalfields.append([bool(g and k in g) for k in keys]+[g is not None])
            order=list(range(len(o['candidate_actions'])));random.Random(int(hashlib.sha256(row['record_id'].encode()).hexdigest()[:16],16)).shuffle(order)
            candidates.append([[o['candidate_actions'][j][k] for k in ['dx_m','yaw_deg','focal_factor','cost']] for j in order]);avail.append([o['candidate_available'][j] for j in order]);success.append([y['action_success'][j] for j in order]);masks.append([y['loss_masks']['action_success'][j] for j in order]);decisions.append(['keep','recommend','ask','abstain'].index(y['decision']))
            if y['human_utility'] is not None or y['loss_masks']['human_utility']:raise ValueError('Unsupported human utility label')
        X={'rgb_history':np.stack(xs),'times_s':np.asarray(tm,np.float32),'subject_tap':np.asarray(taps,np.float32),'subject_known':np.asarray(tapknown,bool),'goal':np.asarray(goals,np.float32),'goal_mask':np.asarray(goalfields,bool),'candidate_params':np.asarray(candidates,np.float32),'candidate_available':np.asarray(avail,bool)}
        Y={'action_success':np.asarray(success,np.float32),'decision':np.asarray(decisions,np.int64)};M={'action_success':np.asarray(masks,bool),'decision':np.ones(len(xs),bool),'human_utility':np.zeros(len(xs),bool)}
        for values in [X,Y,M]:
            for key,array in values.items():
                if not np.isfinite(array).all():raise ValueError('Nonfinite '+key)
        assert X['rgb_history'].shape[1:]==(3,3,224,224) and Y['action_success'].shape==M['action_success'].shape
        yield X,Y,M

def audit(root):
    root=Path(root);rows=list(read_jsonl(root/'inputs.jsonl'));targets=list(read_jsonl(root/'targets.jsonl'));ids=[x['record_id'] for x in rows]
    if len(set(ids))!=len(ids) or ids!=[x['record_id'] for x in targets]:raise ValueError('Record identity mismatch')
    paths={h['path']:h['sha256'] for r in rows for h in r['observations']['history']};groups=collections.defaultdict(set);hashsplits=collections.defaultdict(set)
    for path,h in paths.items():
        if hashlib.sha256(safe(root,path).read_bytes()).hexdigest()!=h:raise ValueError('Corrupt source image')
    for row in rows:
        groups[row['split']].add(row['origin_group']);hashsplits[row['observations']['history'][-1]['sha256']].add(row['split'])
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')]);assert not any(len(v)>1 for v in hashsplits.values())
    checks={};total_batches=0
    for split in ['train','validation','test']:
        h=hashlib.sha256();n=0;bn=0
        for X,Y,M in batches(root,split):
            bn+=1;n+=len(X['rgb_history'])
            for ds in [X,Y,M]:
                for k,v in sorted(ds.items()):h.update(k.encode());h.update(str(v.dtype).encode());h.update(str(v.shape).encode());h.update(v.tobytes())
        checks[split]={'records':n,'batches':bn,'tensor_sha256':h.hexdigest()};total_batches+=bn
    unique_mid_occlusion=[];outcomes=0
    for r in read_jsonl(root/'outcomes.jsonl'):
        outcomes+=1
        for si in [0,1]:
            v=[state[si]['visible_surface_fraction'] for state in r['measurements']]
            if all(x is not None for x in v) and v[-1]>=.9 and min(v[1:-1])<.5:unique_mid_occlusion.append({'scene_id':r['scene_id'],'subject_index':si,'action_id':r['action']['id']})
    (root/'TEMPORAL_HARD_NEGATIVES.json').write_text(json.dumps(unique_mid_occlusion,indent=2))
    return {'rows_checked':len(rows),'prefix_files_sha_verified':len(paths),'split_checks':checks,'actual_numpy_batches':total_batches,'outcome_sequences':outcomes,'unique_subject_action_mid_occlusion_cases':len(unique_mid_occlusion),'origin_overlap':0,'exact_current_image_cross_split_overlap':0,'future_input_frames':0,'model_calls':0}
