"""Portable CC20 data consumers: NumPy/Pillow only, no network or model imports.
Keep tasks separate. Do not concatenate their targets as CameraCoach policy gold.
"""
from __future__ import annotations
import hashlib,io,json,zipfile
from pathlib import Path,PurePosixPath
import numpy as np
from PIL import Image,ImageOps

def rows(path):
    with Path(path).open(encoding='utf-8') as f:
        for line in f:
            if line.strip():yield json.loads(line)

def inside(root,path):
    root=Path(root).resolve();p=(root/path).resolve()
    if p!=root and root not in p.parents:raise ValueError('Path escapes dataset root')
    if not p.is_file():raise FileNotFoundError(p)
    return p

def rgb(root,path,sha=None):
    p=inside(root,path);b=p.read_bytes()
    if sha and hashlib.sha256(b).hexdigest()!=sha:raise ValueError('Media checksum mismatch')
    with Image.open(io.BytesIO(b)) as im:
        return np.asarray(ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.

def holoassist(root):
    """Source-command imitation. Historical outcomes are not supervised.
    Returns (X, Y, masks, provenance). Text targets stay out of X.
    Every returned item is a batch of size 1, preserving time stamps.
    """
    for r in rows(inside(root,'records.jsonl')):
        o=r['observations'];prefix=o['rgb_history'];cut=o['cutoff_s']
        if len(prefix)!=3 or any(x['t_seconds']>=cut for x in prefix):raise ValueError('Invalid causal observation prefix')
        X={'rgb_history':np.stack([rgb(root,x['path'],x['sha256']) for x in prefix])[None],
           'relative_time_s':np.asarray([[x['t_seconds']-cut for x in prefix]],np.float32),
           'selected_subject_available':np.zeros(1,bool),'intent_available':np.zeros(1,bool)}
        Y={'instruction_text':[r['targets']['native_instruction_text']],'source_purpose':[r['targets']['native_purpose']]}
        M={'instruction_text':np.asarray([r['loss_masks']['native_instruction_text']],bool),'action_performed':np.zeros(1,bool),'goal_achieved':np.zeros(1,bool),'human_utility':np.zeros(1,bool)}
        yield X,Y,M,{'record_id':r['record_id'],'origin_group':r['origin_group'],'source_official_split':r['source_official_split'],'split':r['split'],'participant_independence_proven':False}

def objectron(root,task='perception',split=None):
    if task not in ['perception','motion']:raise ValueError('Unknown Objectron task')
    files=sorted(Path(root).glob('native/**/*_records.jsonl'))
    for p in files:
        if p.name!=('perception_records.jsonl' if task=='perception' else 'motion_records.jsonl'):continue
        for r in rows(p):
            if split and r['split']!=split:continue
            o,t,m=r['observations'],r['targets'],r['loss_masks']
            if task=='perception':
                # Native object ID is metadata, never a model input. This task
                # predicts the annotated keypoints for a single-object source.
                kp=t['native_keypoints'];xy=np.array([k['xy'] for k in kp],np.float32);xyz=np.array([k['xyz_camera_m'] for k in kp],np.float32)
                if xy.ndim!=2 or xy.shape[1]!=2:continue
                X={'rgb':rgb(root,o['rgb'],r['provenance']['rgb_sha256'])[None]}
                Y={'native_xy':xy[None],'native_xyz_camera_m':xyz[None],'native_visibility':np.asarray([t['native_visibility']],np.float32)}
                M={'native_xy':np.full((1,len(kp)),m['native_keypoints'],bool),'native_xyz_camera_m':np.full((1,len(kp)),m['native_keypoints'],bool),'native_visibility':np.asarray([m['native_visibility']],bool)}
            else:
                X={'before_rgb':rgb(root,o['before_rgb'])[None],'after_rgb':rgb(root,o['after_rgb'])[None],'dt_s':np.asarray([o['dt_s']],np.float32)}
                Y={'transform_b_in_a':np.asarray([t['transform_b_in_a']],np.float32),'translation_m':np.asarray([t['translation_m']],np.float32),'rotation_rad':np.asarray([t['rotation_rad']],np.float32)}
                M={k:np.asarray([m['relative_pose']],bool) for k in Y}
            M['human_utility']=np.zeros(1,bool)
            yield X,Y,M,{'record_id':r['record_id'],'origin_group':r['origin_group'],'split':r['split'],'authority':'native annotations and AR pose estimates; not perfect measurement'}

def illumination(root,split=None):
    for r in rows(inside(root,'scene_records.jsonl')):
        if split and r['split']!=split:continue
        with zipfile.ZipFile(inside(root,r['archive'])) as z:
            first=r['images'][0]
            def read_image(rec):
                name=PurePosixPath(rec['member'])
                if name.is_absolute() or '..' in name.parts:raise ValueError('Unsafe member')
                b=z.read(rec['member'])
                if hashlib.sha256(b).hexdigest()!=rec['native_sha256']:raise ValueError('Native JPG hash mismatch')
                with Image.open(io.BytesIO(b)) as im:
                    rgb_native=np.asarray(im.convert('RGB'));image=np.asarray(ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.
                return image,rgb_native
            before,_=read_image(first)
            for rec in r['images']:
                after,native=read_image(rec);lum=(native.astype(np.float32)/255.)@np.asarray([.2126,.7152,.0722],np.float32);h,w=lum.shape
                values=[float(lum.mean()),float(np.median(lum)),float((native.max(axis=-1)>=254).mean()),float(lum[h//4:3*h//4,w//4:3*w//4].mean())]
                X={'before_rgb':before[None],'source_light_index':np.array([0],np.int64),'target_light_index':np.array([rec['light_index']],np.int64)}
                Y={'observed_after_rgb':after[None],'display_photometry':np.asarray([values],np.float32)}
                M={'observed_after_rgb':np.ones(1,bool),'display_photometry':np.ones((1,4),bool),'human_preference':np.zeros(1,bool),'operator_utility':np.zeros(1,bool)}
                yield X,Y,M,{'record_id':r['name']+':'+str(rec['light_index']),'origin_group':r['origin_group'],'split':r['split'],'task':'real_light_response_not_preference'}

def audit(iterator):
    h=hashlib.sha256();n=0;schema=None
    for X,Y,M,meta in iterator:
        this={}
        for label,g in [('inputs',X),('targets',Y),('masks',M)]:
            this[label]={}
            for key,v in sorted(g.items()):
                if isinstance(v,np.ndarray):
                    if not np.isfinite(v).all():raise ValueError('Non-finite tensor')
                    this[label][key]={'shape':list(v.shape),'dtype':str(v.dtype)};b=v.tobytes()
                else:this[label][key]={'type':'text_target'};b=json.dumps(v,ensure_ascii=False).encode()
                h.update((label+':'+key).encode());h.update(b)
        if schema is None:schema=this
        n+=1
    return {'actual_batches':n,'tensor_and_text_stream_sha256':h.hexdigest(),'first_schema':schema,'model_calls':0}
