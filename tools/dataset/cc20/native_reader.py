"""Portable native Objectron consumer: no requests, protobuf, models or renderer.
Install NumPy, Pillow, PyAV. Functions do not write files or access the network.
"""
from __future__ import annotations
import hashlib,json
from pathlib import Path
import av,numpy as np
from PIL import Image,ImageOps

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

def safe(root,path):
    root=Path(root).resolve();p=(root/path).resolve()
    if root not in p.parents or not p.is_file():raise ValueError('Invalid component media path')
    return p

def image_tensor(im):return np.asarray(ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.

def records(root,split=None):
    with safe(root,'video_records.jsonl').open() as f:
        for line in f:
            if not line.strip():continue
            r=json.loads(line)
            if split is None or split==r['split']:yield r

def video_batches(root,record,task='perception'):
    path=safe(root,record['video']);labels=safe(root,record['labels'])
    if digest(path)!=record['video_sha256'] or digest(labels)!=record['labels_sha256']:raise ValueError('Native component hash mismatch')
    with np.load(labels,allow_pickle=False) as z:arrays={k:z[k] for k in z.files}
    n=len(arrays['capture_time_s'])
    if n<1 or not np.all(np.diff(arrays['capture_time_s'])>0):raise ValueError('Invalid source clock')
    previous=None;decoded=0
    with av.open(str(path)) as v:
        for i,frame in enumerate(v.decode(video=0)):
            if i>=n:raise ValueError('Extra native video frame')
            with frame.to_image() as im:rgb=image_tensor(im)[None]
            if task=='perception':
                X={'rgb':rgb};Y={'xy_normalized':arrays['xy'][i:i+1],'xyz_camera_m':arrays['xyz'][i:i+1]}
                M={'xy_normalized':arrays['keypoint_mask'][i:i+1],'xyz_camera_m':arrays['keypoint_mask'][i:i+1],'human_utility':np.zeros(1,bool)}
            elif task=='motion':
                decoded+=1
                if previous is None:previous=rgb;continue
                dt=float(arrays['capture_time_s'][i]-arrays['capture_time_s'][i-1]);T=np.linalg.inv(arrays['camera_to_world'][i-1])@arrays['camera_to_world'][i]
                X={'before_rgb':previous,'after_rgb':rgb,'capture_dt_s':np.array([dt],np.float32)}
                Y={'transform_b_in_a':T[None].astype(np.float32),'translation_m':T[None,:3,3].astype(np.float32)}
                valid=bool(arrays['tracking_normal'][i-1] and arrays['tracking_normal'][i] and dt>0)
                M={'transform_b_in_a':np.array([valid]),'translation_m':np.array([valid]),'action_performed':np.zeros(1,bool),'human_utility':np.zeros(1,bool)}
            else:raise ValueError('Unknown task')
            previous=rgb
            for g in [X,Y,M]:
                for a in g.values():
                    if not np.isfinite(a).all():raise ValueError('Non-finite array')
            if task=='perception':decoded+=1
            yield X,Y,M
    if decoded!=n:raise ValueError('Missing native video frames')

def batches(root,task='perception',split='train'):
    for record in records(root,split):yield from video_batches(root,record,task)
