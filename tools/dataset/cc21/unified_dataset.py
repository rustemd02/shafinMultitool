"""CameraCoach unified data-only reader. NumPy/Pillow; no model code.
Native v19/v20 targets remain separate from causal inputs. Variable action sets
are padded and masked, never expanded with fabricated negative outcomes.
"""
from __future__ import annotations
import collections,copy,hashlib,json,math,random
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
SCHEMA='cameracoach.unified-actions.v21.1'
DECISIONS=['keep','recommend','ask','abstain']
METRICS=['amodal_raster_height_fraction','amodal_mesh_height_fraction','visible_pixel_fraction','visible_surface_sample_fraction','median_display_luminance','center_shift_l2','projected_frame_margin','front_depth_m','amodal_pixel_count']
PARAMS=['translation_right_m','translation_forward_m','translation_up_m','rotation_right_rad','rotation_forward_rad','rotation_up_rad','focal_ratio','exposure_ev','fill_watts','light_translation_right_m','light_translation_forward_m','light_translation_up_m','duration_s','effort_cost','motion_profile']
MAX_ACTIONS=31

def lines(p):
    with Path(p).open() as f:
        for text in f:
            if text.strip():yield json.loads(text)
def write_lines(p,rows):
    with Path(p).open('w') as f:
        for row in rows:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')
def safe(root,name):
    root=Path(root).resolve();p=(root/name).resolve()
    if not p.is_relative_to(root):raise ValueError('Path escapes dataset')
    return p

def axis_rotation(axis,angle):
    axis=np.asarray(axis,float);axis/=np.linalg.norm(axis);x,y,z=axis;c=math.cos(angle);s=math.sin(angle);C=1-c
    return np.array([[c+x*x*C,x*y*C-z*s,x*z*C+y*s],[y*x*C+z*s,c+y*y*C,y*z*C-x*s],[z*x*C-y*s,z*y*C+x*s,c+z*z*C]])
def rotation_vector(R):
    angle=math.acos(float(np.clip((np.trace(R)-1)/2,-1,1)))
    if angle<1e-10:return np.zeros(3)
    if abs(math.sin(angle))<1e-7:raise ValueError('Unsupported near-pi action')
    return angle/(2*math.sin(angle))*np.array([R[2,1]-R[1,2],R[0,2]-R[2,0],R[1,0]-R[0,1]])

def canonical_action_v19(a,camera):
    B=np.stack([camera[k] for k in ['right','forward','up']],axis=1)
    if not np.allclose(B.T@B,np.eye(3),atol=1e-6) or np.linalg.det(B)<.999:raise ValueError('Invalid camera basis')
    Rz=axis_rotation([0,0,1],math.radians(a['pan_deg']))
    R=axis_rotation(Rz@B[:,0],math.radians(a['tilt_deg']))@Rz
    rotation=(B.T@rotation_vector(R)).tolist();light=(B.T@np.asarray(a['key_shift_m'])).tolist()
    return [*a['translation'],*rotation,a['focal_factor'],a['exposure_ev'],a['fill_watts'],*light,a['duration_s'],a['cost'],0.]
def canonical_action_v20(a):
    return [a['dx_m'],0.,0.,0.,0.,math.radians(a['yaw_deg']),a['focal_factor'],0.,0.,0.,0.,0.,1.,a['cost'],1.]

def goal_constraints(g,source):
    if g is None:return []
    out=[];scope='all_five_samples' if source=='v20' and g['temporal']=='all_samples' else 'endpoint'
    def add(metric,lo=None,hi=None):
        if lo is not None or hi is not None:out.append({'metric':metric,'minimum':lo,'maximum':hi,'scope':scope})
    if source=='v19':
        add(METRICS[0],g.get('height_min'),g.get('height_max'));add(METRICS[2],g.get('visible_min',0.),g.get('visible_max',1.));add(METRICS[4],g.get('luminance_min'),g.get('luminance_max'));add(METRICS[6],.01);add(METRICS[7],.05);add(METRICS[8],20.)
    elif source=='v20':
        add(METRICS[1],g['height_min'],g['height_max']);add(METRICS[3],g.get('min_visible'),g.get('max_visible'));add(METRICS[5],None,g['max_center_shift']);add(METRICS[6],0.);add(METRICS[7],.05)
    else:raise ValueError('Unknown goal source')
    return out

def convert_v19(row,target,camera,media_prefix):
    o=row['observations'];indices=[j for j,a in enumerate(o['action_candidates']) if a['id']!='wait_1s'];assert len(indices)==31
    hist=[{'path':media_prefix+'/'+h['rgb'],'time_s':h['t_seconds'],'sha256':h['sha256']} for h in o['history']]
    c=o['constraints'];tap=o['selected_subject']['tap_xy']
    obs={'history':hist,'tap_xy':tap,'goal':goal_constraints(o['intent'],'v19'),'goal_known':o['intent'] is not None,'preserve_dark_tone':o['protected_style']=='dark_subject_tone',
      'optics':[o['current_focal_mm']/36.,c['focal_bounds_mm'][0]/36.,c['focal_bounds_mm'][1]/36.], 'optics_known':[True,True,True],
      'actions':[{'parameters':canonical_action_v19(o['action_candidates'][j],camera),'available':o['candidate_available'][j],'native_index':j} for j in indices], 'observation_cutoff_s':0.}
    selected=target['target_action_index'];y={'decision':target['decision'],'chosen_index':indices.index(selected) if selected is not None else None,'success':[target['action_success'][j] for j in indices],'success_known':[target['loss_masks']['action_success'][j] for j in indices],'decision_known':target['loss_masks']['decision'],'human_utility':None}
    return pack(row,obs,y,'v19')
def convert_v20(row,target,media_prefix):
    o=row['observations'];obs={'history':[{'path':media_prefix+'/'+h['path'],'time_s':h['t_s'],'sha256':h['sha256']} for h in o['history']], 'tap_xy':o['subject_tap_xy'],
      'goal':goal_constraints(o['intent'],'v20'),'goal_known':o['intent'] is not None,'preserve_dark_tone':False,'optics':[34./36.,0.,0.],'optics_known':[True,False,False],
      'actions':[{'parameters':canonical_action_v20(a),'available':o['candidate_available'][j],'native_index':j} for j,a in enumerate(o['candidate_actions'])],'observation_cutoff_s':0.}
    y={'decision':target['decision'],'chosen_index':target['target_action_index'],'success':target['action_success'],'success_known':target['loss_masks']['action_success'],'decision_known':target['loss_masks']['decision'],'human_utility':None}
    return pack(row,obs,y,'v20')
def pack(row,o,y,source):
    assert [h['time_s'] for h in o['history']]==[-.4,-.2,0.]
    assert len(y['success'])==len(o['actions'])==len(y['success_known'])
    k=y['chosen_index']
    if k is not None:assert y['success'][k] and y['success_known'][k] and o['actions'][k]['available']
    assert y['human_utility'] is None
    rid=source+':'+row['record_id']
    return {'schema':SCHEMA,'record_id':rid,'origin_group':source+':'+row['origin_group'],'split':row['split'],'observations':o,'targets':y,
      'provenance':{'native_source':source,'native_record_id':row['record_id'],'native_provenance':row['provenance'],'label_authority':'synthetic_task_oracle','rights_scope':'own_procedural_outputs','human_evaluated':False}}

def batch(root,rows):
    n=len(rows);X={'rgb_history':np.zeros((n,3,3,224,224),np.float32),'history_time_s':np.tile(np.array([-.4,-.2,0.],np.float32),(n,1)),
      'selected_tap_xy':np.zeros((n,2),np.float32),'selected_tap_known':np.zeros(n,bool),'goal_bounds':np.zeros((n,len(METRICS),2),np.float32),'goal_bounds_known':np.zeros((n,len(METRICS),2),bool),
      'goal_scope':np.zeros((n,len(METRICS)),np.int64),'goal_known':np.zeros(n,bool),'preserve_dark_tone':np.zeros(n,bool),'optics':np.zeros((n,3),np.float32),'optics_known':np.zeros((n,3),bool),
      'candidate_params':np.zeros((n,MAX_ACTIONS,len(PARAMS)),np.float32),'candidate_present':np.zeros((n,MAX_ACTIONS),bool),'candidate_available':np.zeros((n,MAX_ACTIONS),bool)}
    Y={'decision':np.zeros(n,np.int64),'action_index':np.full(n,-1,np.int64),'action_success':np.zeros((n,MAX_ACTIONS),np.float32)}
    M={'decision':np.zeros(n,bool),'action_index':np.zeros(n,bool),'action_success':np.zeros((n,MAX_ACTIONS),bool),'human_utility':np.zeros(n,bool)}
    allowed_obs={'history','tap_xy','goal','goal_known','preserve_dark_tone','optics','optics_known','actions','observation_cutoff_s'}
    for i,r in enumerate(rows):
        if r['schema']!=SCHEMA or set(r['observations'])!=allowed_obs:raise ValueError('Unrecognized input schema')
        o=r['observations'];y=r['targets']
        if o['observation_cutoff_s']!=0 or [h['time_s'] for h in o['history']]!=[-.4,-.2,0.]:raise ValueError('Future/incorrect history')
        for j,h in enumerate(o['history']):
            with Image.open(safe(root,h['path'])) as im:X['rgb_history'][i,j]=np.asarray(ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.
        if o['tap_xy'] is not None:
            if len(o['tap_xy'])!=2 or not all(0<=v<=1 for v in o['tap_xy']):raise ValueError('Invalid tap')
            X['selected_tap_xy'][i]=o['tap_xy'];X['selected_tap_known'][i]=True
        X['goal_known'][i]=o['goal_known'];X['preserve_dark_tone'][i]=o['preserve_dark_tone'];X['optics'][i]=o['optics'];X['optics_known'][i]=o['optics_known']
        for g in o['goal']:
            mi=METRICS.index(g['metric']);X['goal_scope'][i,mi]={'endpoint':1,'all_five_samples':2}[g['scope']]
            for j,k in enumerate(['minimum','maximum']):
                if g[k] is not None:X['goal_bounds'][i,mi,j]=g[k];X['goal_bounds_known'][i,mi,j]=True
        actions=o['actions'];order=list(range(len(actions)));random.Random(int(hashlib.sha256(r['record_id'].encode()).hexdigest()[:16],16)).shuffle(order)
        if len(order)>MAX_ACTIONS:raise ValueError('Too many candidates')
        for j,k in enumerate(order):
            a=actions[k];X['candidate_params'][i,j]=a['parameters'];X['candidate_present'][i,j]=True;X['candidate_available'][i,j]=a['available'];Y['action_success'][i,j]=y['success'][k];M['action_success'][i,j]=bool(y['success_known'][k] and a['available'])
        Y['decision'][i]=DECISIONS.index(y['decision']);M['decision'][i]=y['decision_known'];chosen=y['chosen_index']
        if chosen is not None:Y['action_index'][i]=order.index(chosen);M['action_index'][i]=True
        if y['human_utility'] is not None:raise ValueError('Human utility is unsupported in these sources')
    for d in [X,Y,M]:
        for key,value in d.items():
            if not np.isfinite(value).all():raise ValueError('Nonfinite tensor '+key)
    if np.any(M['action_success'] & ~X['candidate_present']):raise ValueError('Padded target unmasked')
    return X,Y,M

def batches(root,split='train',batch_size=8):
    if split not in ['train','validation','test']:raise ValueError('Invalid split')
    rows=[r for r in lines(Path(root)/'records.jsonl') if r['split']==split]
    # Interleave sources without crossing splits. Sample order never depends on targets.
    rows.sort(key=lambda r:hashlib.sha256(r['record_id'].encode()).digest())
    for i in range(0,len(rows),batch_size):yield batch(root,rows[i:i+batch_size])

def audit(root):
    root=Path(root);rows=list(lines(root/'records.jsonl'));counts=collections.Counter();groups=collections.defaultdict(set);paths={};pixels=collections.defaultdict(set)
    assert len({r['record_id'] for r in rows})==len(rows)
    for r in rows:
        groups[r['split']].add(r['origin_group']);counts[r['split']]+=1;counts['source:'+r['provenance']['native_source']]+=1;counts['decision:'+r['targets']['decision']]+=1
        for h in r['observations']['history']:
            p=safe(root,h['path']);wanted=h['sha256']
            if p not in paths:paths[p]=hashlib.sha256(p.read_bytes()).hexdigest()
            if paths[p]!=wanted:raise ValueError('Image SHA mismatch')
        p=safe(root,r['observations']['history'][-1]['path'])
        with Image.open(p) as im:ph=hashlib.sha256(np.asarray(im.convert('RGB')).tobytes()).hexdigest()
        pixels[ph].add(r['split'])
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    assert not any(len(v)>1 for v in pixels.values())
    streams={};total=0
    for split in ['train','validation','test']:
        h=hashlib.sha256();bn=0;rn=0
        for X,Y,M in batches(root,split):
            bn+=1;rn+=len(Y['decision'])
            for tag,ds in [('X',X),('Y',Y),('M',M)]:
                for key,a in sorted(ds.items()):h.update((tag+key+str(a.dtype)+str(a.shape)).encode());h.update(a.tobytes())
        streams[split]={'rows':rn,'batches':bn,'sha256':h.hexdigest()};total+=bn
    sample=[]
    for source in ['v19','v20']:sample.extend(next(r for r in rows if r['provenance']['native_source']==source) for _ in [0])
    X,Y,M=batch(root,sample);changed=copy.deepcopy(sample)
    for row in changed:
        row['targets']['decision']='ask';row['targets']['chosen_index']=None;row['targets']['success']=[not v for v in row['targets']['success']]
    X2,_,_=batch(root,changed)
    assert all(np.array_equal(X[k],X2[k]) for k in X),'Target leakage'
    invalid=copy.deepcopy(sample);invalid[0]['observations']['history'][-1]['time_s']=.1
    try:batch(root,invalid);raise AssertionError('Future accepted')
    except ValueError:pass
    assert not M['action_success'][1,11:].any() and not X['candidate_present'][1,11:].any()
    return {'schema':SCHEMA,'rows':len(rows),'counts':dict(counts),'origin_groups':{k:len(v) for k,v in groups.items()},'actual_batches':total,'image_files_sha_verified':len(paths),'stream_hashes':streams,
      'mixed_11_and_31_candidate_batch_passed':True,'padding_losses_zero':True,'target_mutation_leaves_inputs_unchanged':True,'future_time_rejected':True,'cross_split_origin_overlap':0,'cross_split_exact_pixel_overlap':0,
      'model_calls':0,'human_utility_labels':0,'full_original_DoD_pass':False,'tensor_schema':{tag:{k:{'dtype':str(a.dtype),'shape':list(a.shape[1:])} for k,a in ds.items()} for tag,ds in [('X',X),('Y',Y),('M',M)]}}
