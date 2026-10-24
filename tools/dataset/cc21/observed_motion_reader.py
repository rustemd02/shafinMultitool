"""Observable real-motion tasks from the admitted TUM RGB-D subset.
RGB-only: rotation and unit translation direction, with metric-translation loss OFF.
RGB-D: measured translation in meters additionally enabled with valid native depth.
No model execution. Native ground-truth poses never enter input tensors.
"""
from __future__ import annotations
import collections,hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image
CALIBRATION={
 'freiburg1':{'rgb':[517.3,516.5,318.6,255.3],'distortion':[.2624,-.9531,-.0054,.0026,1.1633]},
 'freiburg2':{'rgb':[520.9,521.0,325.1,249.7],'distortion':[.2312,-.7849,-.0033,-.0001,.9172]},
 'freiburg3':{'rgb':[535.4,539.2,320.1,247.6],'distortion':[0.,0.,0.,0.,0.]}}
SOURCE='https://cvg.cit.tum.de/data/datasets/rgbd-dataset/file_formats'

def lines(p):
    with Path(p).open() as f:
        for l in f:
            if l.strip():yield json.loads(l)
def path(root,rel):
    p=(Path(root)/rel).resolve()
    if not p.is_relative_to(Path(root).resolve()):raise ValueError('Unsafe path')
    return p

def load_records(root,split):
    root=Path(root)
    if split not in ['train','validation','test']:raise ValueError('Invalid split')
    rows=[r for r in lines(root/'motion_records.jsonl') if r['split']==split];frames={}
    for p in sorted(root.glob('native/*/ALIGNED_SELECTED_FRAMES.jsonl')):
        for r in lines(p):
            key=r['files']['rgb']
            if key in frames:raise ValueError('Ambiguous frame identity')
            frames[key]={'depth_path':r['files']['depth'],'rgb_time':r['rgb_timestamp'],'depth_time':r['depth_timestamp']}
    return rows,frames

def encode(root,rows,frames,mode):
    if mode not in ['rgb_direction','rgbd_metric']:raise ValueError('Unknown observation mode')
    rgb=[];depths=[];valids=[];kvals=[];dist=[];dt=[];truth=[];coverage=[]
    for r in rows:
        o=r['observations'];assert set(o)=={'before_rgb','after_rgb','delta_time_s'}
        assert o['delta_time_s']>0
        pair=[];dpair=[];vpair=[]
        for key in ['before_rgb','after_rgb']:
            rel=o[key]
            with Image.open(path(root,rel)) as im:
                assert im.size==(640,480)
                pair.append(np.asarray(im.convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.)
            native=frames[rel];assert abs(native['rgb_time']-native['depth_time'])<=.02
            if mode=='rgbd_metric':
                with Image.open(path(root,native['depth_path'])) as im:
                    assert im.size==(640,480)
                    raw=np.asarray(im.resize((224,224),Image.Resampling.NEAREST),dtype=np.float32)
                valid=raw>0;depth=raw/5000.;assert np.isfinite(depth).all()
                dpair.append(depth[None]);vpair.append(valid[None])
        rgb.append(np.stack(pair));dt.append(o['delta_time_s'])
        camera=r['sequence'].split('_')[0];c=CALIBRATION[camera]
        if mode=='rgbd_metric':
            # Source recommends ROS-default unrectified registration for the
            # already registered depth. This is an approximation, not exact K.
            fx,fy,cx,cy=525.,525.,319.5,239.5;dist.append([0.]*5)
            depths.append(np.stack(dpair));valids.append(np.stack(vpair));coverage.append(min(float(v.mean()) for v in vpair))
        else:fx,fy,cx,cy=c['rgb'];dist.append(c['distortion']);coverage.append(0.)
        sx,sy=224/640,224/480
        kvals.append([fx*sx,fy*sy,(cx+.5)*sx-.5,(cy+.5)*sy-.5])
        t=r['targets'];assert t['human_intent'] is None and t['operator_utility'] is None
        truth.append(t['measured_camera_motion'])
    native=np.asarray(truth,np.float32);length=np.linalg.norm(native[:,:3],axis=1);direction=np.zeros_like(native[:,:3]);known=length>=.01;direction[known]=native[known,:3]/length[known,None]
    X={'rgb_pair':np.stack(rgb),'delta_time_s':np.asarray(dt,np.float32),'intrinsics_224_px':np.asarray(kvals,np.float32),'distortion':np.asarray(dist,np.float32)}
    if mode=='rgbd_metric':X.update(depth_m=np.stack(depths),depth_valid=np.stack(valids),registration_intrinsics_approximate=np.ones(len(rows),bool))
    Y={'translation_direction':direction,'rotation_vector_rad':native[:,3:],'translation_m':native[:,:3]}
    metric_known=np.asarray(coverage)>=.05 if mode=='rgbd_metric' else np.zeros(len(rows),bool)
    M={'translation_direction':np.repeat(known[:,None],3,axis=1),'rotation_vector_rad':np.ones((len(rows),3),bool),'translation_m':np.repeat(metric_known[:,None],3,axis=1),'human_utility':np.zeros(len(rows),bool)}
    for d in [X,Y,M]:
        for a in d.values():assert np.isfinite(a).all()
    if mode=='rgb_direction':assert not M['translation_m'].any() and 'depth_m' not in X
    return X,Y,M

def batches(root,split='train',batch_size=16,mode='rgb_direction'):
    rows,frames=load_records(root,split)
    for i in range(0,len(rows),batch_size):yield encode(root,rows[i:i+batch_size],frames,mode)

def audit(root):
    root=Path(root);results={};actual_batches=0
    for mode in ['rgb_direction','rgbd_metric']:
        results[mode]={}
        for split in ['train','validation','test']:
            h=hashlib.sha256();n=0;nb=0;metric=0;directions=0
            for X,Y,M in batches(root,split,mode=mode):
                n+=len(X['delta_time_s']);nb+=1;metric+=int(np.any(M['translation_m'],axis=1).sum());directions+=int(np.any(M['translation_direction'],axis=1).sum())
                for tag,d in [('X',X),('Y',Y),('M',M)]:
                    for k,v in sorted(d.items()):h.update((tag+k+str(v.dtype)+str(v.shape)).encode());h.update(v.tobytes())
            results[mode][split]={'records':n,'batches':nb,'metric_translation_loss_rows':metric,'direction_loss_rows':directions,'tensor_sha256':h.hexdigest()};actual_batches+=nb
    assert all(v['metric_translation_loss_rows']==0 for v in results['rgb_direction'].values())
    rows,frames=load_records(root,'train');base=rows[:2]
    import copy
    changed=copy.deepcopy(base)
    for r in changed:r['targets']['measured_camera_motion']=[2.,3.,4.,.1,.2,.3]
    for mode in ['rgb_direction','rgbd_metric']:
        X,_,_=encode(root,base,frames,mode);X2,_,_=encode(root,changed,frames,mode);assert all(np.array_equal(X[k],X2[k]) for k in X)
    report={'modes':results,'actual_batches':actual_batches,'target_mutation_leaves_X_unchanged':True,'RGB_only_metric_translation_loss_disabled':True,'RGBD_metric_scale_from_native_depth':True,'native_depth_divisor':5000,'native_zero_depth_masked':True,
      'rgbd_intrinsics_policy':'official recommended ROS default, approximate unrectified pre-registration; not exact calibrated reconstruction','calibration_reference':SOURCE,'human_utility_losses':0,'model_calls':0,'same_native_records_in_two_views_not_additional_observations':True}
    (root/'OBSERVABILITY_QA.json').write_text(json.dumps(report,indent=2));return report

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);a=p.parse_args();print('CC21_OBSERVABILITY_QA '+json.dumps(audit(a.root)),flush=True)
