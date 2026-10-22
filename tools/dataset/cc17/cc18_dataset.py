"""CameraCoach CC18 data-only consumer. Requires NumPy and Pillow, NOT Blender.
The default input uses the selected tap only, never the oracle bounding box.
The redundant wait_1s control is omitted from training candidates, leaving 31.
No models, weight downloads, losses, optimizers or training are executed.
"""
from __future__ import annotations
import argparse,collections,hashlib,json,random
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
DECISIONS=['keep','recommend','ask','abstain']
GOAL_KEYS=['height_min','height_max','visible_min','visible_max','luminance_min','luminance_max']

def lines(path):
    with Path(path).open() as f:
        for line in f:
            if line.strip():yield json.loads(line)

def allowed_path(root,name):
    p=(root/name).resolve()
    if not p.is_relative_to(root.resolve()):raise ValueError('Path escapes component root')
    return p

def candidate_indices(actions):
    keep=next(a for a in actions if a['id']=='keep');out=[]
    physical=['translation','pan_deg','tilt_deg','focal_factor','exposure_ev','fill_watts','key_shift_m','duration_s']
    for j,a in enumerate(actions):
        if a['id']=='wait_1s':
            if any(a[k]!=keep[k] for k in physical):raise ValueError('wait is not an equivalent control')
            continue
        out.append(j)
    return out

def load_batch(root,rows,target_map):
    """X/Y/M are separate arrays. Candidate order changes with row ID, never labels."""
    x=collections.defaultdict(list);y=collections.defaultdict(list);m=collections.defaultdict(list)
    for row in rows:
        o=row['observations'];t=target_map[row['record_id']];frames=[]
        assert len(o['history'])==3 and [h['t_seconds'] for h in o['history']]==[-.4,-.2,0.]
        assert o['observation_cutoff_s']==0. and o['rgb']==o['history'][-1]['rgb']
        for h in o['history']:
            with Image.open(allowed_path(root,h['rgb'])) as im:
                im=ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR)
                frames.append(np.asarray(im,dtype=np.float32).transpose(2,0,1)/255.)
        x['rgb_history'].append(np.stack(frames));x['history_time_s'].append([-.4,-.2,0.])
        tap=o['selected_subject']['tap_xy'];x['selected_tap_xy'].append(tap or [0.,0.]);x['selected_tap_available'].append(tap is not None)
        g=o['intent'];x['goal_bounds'].append([float(g.get(k,0)) if g else 0. for k in GOAL_KEYS]);x['goal_field_mask'].append([bool(g and k in g) for k in GOAL_KEYS]+[g is not None])
        x['preserve_dark_tone'].append(o['protected_style']=='dark_subject_tone')
        c=o['constraints'];x['equipment_constraints'].append([bool(c[k]) for k in ['allow_translation','allow_optical_zoom','allow_exposure','fill_light_available','movable_key_light']])
        x['focal_over_sensor_width'].append([o['current_focal_mm']/36.,c['focal_bounds_mm'][0]/36.,c['focal_bounds_mm'][1]/36.])
        x['source_image_aspect_ratio'].append(256./192.)
        actions=o['action_candidates'];indices=candidate_indices(actions)
        rng=random.Random(int(hashlib.sha256(row['record_id'].encode()).hexdigest()[:16],16));rng.shuffle(indices)
        features=[]
        for j in indices:
            a=actions[j];features.append(a['translation']+[a['pan_deg'],a['tilt_deg'],a['focal_factor'],a['exposure_ev'],a['fill_watts']]+a['key_shift_m']+[a['duration_s'],a['cost']])
        x['candidate_params'].append(features);x['candidate_available'].append([o['candidate_available'][j] for j in indices])
        y['action_success'].append([t['action_success'][j] for j in indices]);m['action_success'].append([t['loss_masks']['action_success'][j] for j in indices])
        y['decision'].append(DECISIONS.index(t['decision']));m['decision'].append(t['loss_masks']['decision']);m['human_utility'].append(False)
        assert t['human_utility'] is None and t['action_performed'] is None and not t['loss_masks']['human_utility']
        selected=t['target_action_index'];y['action_index'].append(indices.index(selected) if selected is not None else -1);m['action_index'].append(selected is not None)
    bool_keys={'selected_tap_available','goal_field_mask','candidate_available','equipment_constraints','preserve_dark_tone'}
    X={k:np.asarray(v,dtype=bool if k in bool_keys else np.float32) for k,v in x.items()}
    Y={k:np.asarray(v,dtype=np.int64 if k in ('decision','action_index') else np.float32) for k,v in y.items()}
    M={k:np.asarray(v,dtype=bool) for k,v in m.items()}
    assert X['rgb_history'].shape[1:]==(3,3,224,224) and X['candidate_params'].shape[1:]==(31,13)
    assert Y['action_success'].shape==M['action_success'].shape
    for a in list(X.values())+list(Y.values()):assert np.isfinite(a).all()
    assert not M['human_utility'].any()
    return X,Y,M

def audit(data_root:Path,batch_size:int=8)->dict:
    paths=sorted(data_root.rglob('inputs.jsonl'));assert paths,'No CC18 inputs.jsonl found'
    origins=collections.defaultdict(set);all_ids=set();pixels=collections.defaultdict(set);signatures=[];counts=collections.Counter();batches=0;file_checks=0
    for path in paths:
        root=path.parent;rows=list(lines(path));targets={r['record_id']:r for r in lines(root/'targets.jsonl')}
        assert len(targets)==len(rows)
        cached={}
        for row in rows:
            assert row['schema']=='cameracoach.component.v18.2'
            rid=row['record_id'];assert rid not in all_ids;all_ids.add(rid)
            origins[row['split']].add(row['origin_group']);counts['split:'+row['split']]+=1;counts['decision:'+targets[rid]['decision']]+=1
            for h in row['observations']['history']:
                p=allowed_path(root,h['rgb'])
                if p not in cached:
                    cached[p]=hashlib.sha256(p.read_bytes()).hexdigest();file_checks+=1
                assert cached[p]==h['sha256']
            assert row['provenance']['label_authority']=='synthetic_task_oracle'
            assert len(row['observations']['candidate_available'])==32
        for start in range(0,len(rows),batch_size):
            X,Y,M=load_batch(root,rows[start:start+batch_size],targets);batches+=1
        for r in lines(root/'image_signatures.jsonl'):
            pixels[r['pixel_sha256']].add(r['split']);signatures.append(r)
        counts['policy_rows']+=len(rows);counts['components']+=1
    assert all(not origins[a]&origins[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    cross_exact=sum(len(s)>1 for s in pixels.values());assert cross_exact==0
    near=[]
    for i,a in enumerate(signatures):
        for b in signatures[i+1:]:
            if a['split']==b['split']:continue
            distance=(int(a['dhash_hex'],16)^int(b['dhash_hex'],16)).bit_count()
            if distance<=4:near.append({'a':a['origin_id'],'b':b['origin_id'],'distance':distance})
    return {'schema':'cc18.renderer_free_consumer_audit.v1','counts':dict(counts),'actual_batches':batches,'batch_size':batch_size,
      'prefix_files_sha_verified':file_checks,'conservative_groups_by_split':{k:len(v) for k,v in origins.items()},
      'cross_split_origin_overlap':0,'cross_split_exact_pixels':cross_exact,'dhash_review_candidates':near,
      'dhash_policy':'distance<=4 is a screening heuristic, not proof of duplicate identity; review remains required',
      'input_subject_mode':'tap_only; no oracle box, depth, pose, after-image or path-feasibility tensors',
      'training_candidates':31,'omitted_redundant_control':'wait_1s equals keep at the matched horizon',
      'model_calls':0,'human_utility_gate':'BLOCKED','full_cameracoach_training_ready':False}

def main():
    p=argparse.ArgumentParser();p.add_argument('--data-root',type=Path,required=True);p.add_argument('--batch-size',type=int,default=8);p.add_argument('--receipt',type=Path);a=p.parse_args()
    result=audit(a.data_root,a.batch_size);text=json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    if a.receipt:a.receipt.write_text(text)
    print(text)
if __name__=='__main__':main()
