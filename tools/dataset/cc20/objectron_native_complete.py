"""Objectron native 36-video component with every frame and verified AR clocks.
Source annotation timestamps are absent; NEVER treat their protobuf default zero
as an observation. Native geometry clocks are accepted only with frame-count and
camera-transform equality. Published video playback PTS are kept separately.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,json,math,struct,subprocess,sys
from pathlib import Path
import av,numpy as np
from PIL import Image
from real_common import fetch,repository_files,jsonl,write_json,digest,image_tensor,finish
ROOT=Path('cc20-objectron-native-aligned');ROOT.mkdir(exist_ok=True)
REV='46daaa0aca5b2e704bbc8deb99b0863bc9bf19a7'
CATS=['bike','book','bottle','camera','cereal_box','chair','cup','laptop','shoe']
BASE='https://storage.googleapis.com/objectron/'
PROJECTION_TOLERANCE=0.005

def geometry(path,G):
    values=[]
    with path.open('rb') as f:
        while True:
            b=f.read(4)
            if not b:break
            if len(b)!=4:raise ValueError('Incomplete native protobuf prefix')
            n=struct.unpack('<I',b)[0]
            if n>50_000_000:raise ValueError('Invalid native message length')
            raw=f.read(n)
            if len(raw)!=n:raise ValueError('Truncated native protobuf')
            g=G.ARFrame();g.ParseFromString(raw);values.append(g)
    return values

def tensors(root,record,task='perception'):
    """Streaming data-only reader; all objects per frame avoid ambiguous targets.
    Object IDs, future outcomes and AR poses never enter perception X.
    Motion verifier legitimately sees a before/after pair and capture dt.
    """
    path=Path(root)/record['video'];labels=Path(root)/record['labels']
    if digest(path)!=record['video_sha256'] or digest(labels)!=record['labels_sha256']:raise ValueError('Native component hash mismatch')
    with np.load(labels,allow_pickle=False) as z:
        arrays={k:z[k] for k in z.files}
    prev=None;count=0
    with av.open(str(path)) as v:
        for i,frame in enumerate(v.decode(video=0)):
            if i>=len(arrays['capture_time_s']):raise ValueError('Extra decoded frame')
            with frame.to_image() as im:Xrgb=image_tensor(im)[None]
            if task=='perception':
                X={'rgb':Xrgb}
                Y={'xy_normalized':arrays['xy'][i:i+1],'xyz_camera_m':arrays['xyz'][i:i+1]}
                M={'xy_normalized':arrays['keypoint_mask'][i:i+1],'xyz_camera_m':arrays['keypoint_mask'][i:i+1],'human_utility':np.zeros(1,bool)}
            elif task=='motion':
                if prev is None:prev=Xrgb;continue
                dt=float(arrays['capture_time_s'][i]-arrays['capture_time_s'][i-1]);T=np.linalg.inv(arrays['camera_to_world'][i-1])@arrays['camera_to_world'][i]
                X={'before_rgb':prev,'after_rgb':Xrgb,'capture_dt_s':np.array([dt],np.float32)}
                Y={'transform_b_in_a':T[None].astype(np.float32),'translation_m':T[None,:3,3].astype(np.float32)}
                valid=bool(arrays['tracking_normal'][i-1] and arrays['tracking_normal'][i] and dt>0)
                M={'transform_b_in_a':np.array([valid]),'translation_m':np.array([valid]),'action_performed':np.zeros(1,bool),'human_utility':np.zeros(1,bool)}
            else:raise ValueError('Unknown component task')
            prev=Xrgb
            for group in [X,Y,M]:
                for a in group.values():
                    if not np.isfinite(a).all():raise ValueError('Non-finite tensor')
            count+=1;yield X,Y,M
    if i+1!=len(arrays['capture_time_s']):raise ValueError('Missing decoded frames')

def acquire(item,A,G):
    vid=item['video_id'];out={**item,'status':'failed'};folder=ROOT/'native'/vid;receipts=[]
    try:
        for name,url in [('annotation.pbdata',BASE+'annotations/'+vid+'.pbdata'),('geometry.pbdata',BASE+'videos/'+vid+'/geometry.pbdata'),('video.MOV',BASE+'videos/'+vid+'/video.MOV')]:
            r=fetch(url,folder/name,300_000_000);r['path']=str((folder/name).relative_to(ROOT));receipts.append(r)
        seq=A.Sequence();seq.ParseFromString((folder/'annotation.pbdata').read_bytes());fs=list(seq.frame_annotations);gs=geometry(folder/'geometry.pbdata',G)
        if len(gs)!=len(fs) or [f.frame_id for f in fs]!=list(range(len(fs))):raise ValueError('Native frame-index join mismatch')
        n=len(fs);oids=sorted({obj.object_id for f in fs for obj in f.annotations});oi={v:i for i,v in enumerate(oids)}
        xy=np.zeros((n,len(oids),9,2),np.float32);xyz=np.zeros((n,len(oids),9,3),np.float32);mask=np.zeros((n,len(oids),9),bool)
        poses=[];times=[];normal=[];max_projection=0.;clock_missing=0;max_pose_diff=0.;projection_rejected=0
        for i,(fa,geo) in enumerate(zip(fs,gs)):
            if not geo.HasField('timestamp'):raise ValueError('Missing native geometry clock')
            times.append(geo.timestamp)
            T=np.asarray(fa.camera.transform).reshape(4,4);Tg=np.asarray(geo.camera.transform).reshape(4,4)
            err=float(np.max(np.abs(T-Tg)));max_pose_diff=max(max_pose_diff,err)
            if err>1e-5:raise ValueError('Annotation and geometry cameras differ')
            if not np.allclose(T[3],[0,0,0,1],atol=1e-5) or abs(np.linalg.det(T[:3,:3])-1)>.02:raise ValueError('Invalid camera rigid transform')
            poses.append(T);normal.append(fa.camera.tracking_state==3)
            clock_missing+=not any(d.name=='timestamp' for d,v in fa.ListFields())
            P=np.asarray(fa.camera.projection_matrix).reshape(4,4)
            for obj in fa.annotations:
                j=oi[obj.object_id]
                for kp in obj.keypoints:
                    if not 0<=kp.id<9:raise ValueError('Unexpected source keypoint ID')
                    k=kp.id;xy[i,j,k]=[kp.point_2d.x,kp.point_2d.y];xyz[i,j,k]=[kp.point_3d.x,kp.point_3d.y,kp.point_3d.z]
                    q=P@np.r_[xyz[i,j,k],1.]
                    if abs(q[3])<1e-8:projection_rejected+=1;continue
                    # Exact axis convention in the pinned author geometry tutorial.
                    projected=(q[:2][::-1]/q[3]+1.)*.5;error=float(np.max(np.abs(projected-xy[i,j,k])))
                    max_projection=max(max_projection,error);mask[i,j,k]=error<=PROJECTION_TOLERANCE
                    projection_rejected+=error>PROJECTION_TOLERANCE
        times=np.asarray(times,np.float64)
        if not np.isfinite(times).all() or not np.all(np.diff(times)>0):raise ValueError('Nonmonotonic native capture clock')
        if not mask.any():raise ValueError('No projection-consistent native keypoints')
        arrays={'xy':xy,'xyz':xyz,'keypoint_mask':mask,'camera_to_world':np.asarray(poses,np.float64),'capture_time_s':times,'tracking_normal':np.asarray(normal,bool),'native_object_ids':np.asarray(oids,np.int32)}
        lp=folder/'aligned_labels.npz';np.savez_compressed(lp,**arrays)
        out.update(video=str((folder/'video.MOV').relative_to(ROOT)),labels=str(lp.relative_to(ROOT)),video_sha256=digest(folder/'video.MOV'),labels_sha256=digest(lp))
        stats={};schemas={}
        for task in ['perception','motion']:
            h=hashlib.sha256();count=0;supervised=0
            for X,Y,M in tensors(ROOT,out,task):
                for tag,d in [('X',X),('Y',Y),('M',M)]:
                    for key,v in sorted(d.items()):h.update((tag+key).encode());h.update(str(v.shape).encode());h.update(str(v.dtype).encode());h.update(v.tobytes())
                if count==0:schemas[task]={tag:{k:{'shape':list(v.shape),'dtype':str(v.dtype)} for k,v in d.items()} for tag,d in [('X',X),('Y',Y),('M',M)]}
                count+=1;supervised+=int(any(v.any() for k,v in M.items() if k not in ['human_utility','action_performed']))
            stats[task]={'actual_batches':count,'batches_with_supervision':supervised,'tensor_stream_sha256':h.hexdigest()}
        # Compare source playback timing to capture timing but never replace either.
        playback=[];preview_indices={0,n//2,n-1};shapes=set();pixhash=[]
        with av.open(str(folder/'video.MOV')) as v:
            for index,f in enumerate(v.decode(video=0)):
                if f.pts is None:raise ValueError('Missing video presentation time')
                playback.append(float(f.pts*f.time_base));shapes.add((f.width,f.height))
                if index in preview_indices:
                    im=f.to_image();im.thumbnail((512,512));p=ROOT/'previews'/vid/f'{index:06d}.png';p.parent.mkdir(parents=True,exist_ok=True);im.save(p)
                    pixhash.append({'frame_id':index,'path':str(p.relative_to(ROOT)),'sha256':digest(p),'representation':'aspect-preserving downsampled preview, native MOV retained'})
        assert len(playback)==n
        jsonl(folder/'frame_clocks.jsonl',[{'frame_id':i,'video_pts_s':playback[i],'native_capture_time_s':float(times[i]),'annotation_timestamp':None if not any(d.name=='timestamp' for d,v in fs[i].ListFields()) else fs[i].timestamp} for i in range(n)])
        out.update(status='accepted',receipts=receipts,native_frame_count=n,native_object_tracks=len(oids),native_keypoint_targets=int(mask.sum()),projection_rejected_keypoints=int(projection_rejected),max_native_projection_error=max_projection,
          source_annotation_timestamps_absent=clock_missing,native_geometry_clock_join_verified=True,pose_pair_max_difference=max_pose_diff,
          capture_duration_s=float(times[-1]-times[0]),video_playback_duration_s=playback[-1]-playback[0],video_dimensions=sorted(map(list,shapes)),
          native_calibration_dimensions=[fs[0].camera.image_resolution_width,fs[0].camera.image_resolution_height],previews=pixhash,consumer=stats,first_tensor_schema=schemas)
    except Exception as e:out['error']=type(e).__name__+': '+str(e)[:300];out['receipts']=receipts
    return out

def main():
    paths=['LICENSE','README.md','objectron/schema/annotation_data.proto','objectron/schema/object.proto','objectron/schema/a_r_capture_metadata.proto','notebooks/Parse Annotations.ipynb','notebooks/objectron-geometry-tutorial.ipynb']+[f'index/{c}_annotations_{s}' for c in CATS for s in ['train','test']]
    repository_files(ROOT,'google-research-datasets/Objectron',REV,paths)
    # Do not retain notebook embedded pictures/code outputs in addition to source files.
    schema=ROOT/'source_repository/objectron/schema'
    subprocess.run([sys.executable,'-m','grpc_tools.protoc','-I'+str(schema),'--python_out='+str(schema),*map(str,schema.glob('*.proto'))],check=True)
    sys.path.insert(0,str(schema));import annotation_data_pb2 as A;import a_r_capture_metadata_pb2 as G
    chosen=[]
    for cat in CATS:
        groups=set();a=[]
        for vid in sorted(set((ROOT/f'source_repository/index/{cat}_annotations_train').read_text().splitlines()),key=lambda x:hashlib.sha256(x.encode()).hexdigest()):
            g='/'.join(vid.split('/')[:-1])
            if not vid.strip() or g in groups:continue
            a.append(vid);groups.add(g)
            if len(a)==3:break
        for j,vid in enumerate(a):chosen.append({'video_id':vid,'category':cat,'split':'validation' if j==2 else 'train','source_official_split':'train','origin_group':'objectron:'+'/'.join(vid.split('/')[:-1])})
        for vid in sorted(set((ROOT/f'source_repository/index/{cat}_annotations_test').read_text().splitlines()),key=lambda x:hashlib.sha256(x.encode()).hexdigest()):
            g='/'.join(vid.split('/')[:-1])
            if vid.strip() and g not in groups:
                chosen.append({'video_id':vid,'category':cat,'split':'test','source_official_split':'test','origin_group':'objectron:'+g});break
    write_json(ROOT/'PREDECLARED_SELECTION.json',{'source_revision':REV,'videos':chosen,'projection_tolerance_normalized':PROJECTION_TOLERANCE,'geometry_pose_match_tolerance':1e-5,'source_clock':'ARFrame.timestamp, not unset FrameAnnotation.timestamp','first_failed_clock_attempt_preserved_in_run':40082284156})
    first=acquire(chosen[0],A,G);assert first['status']=='accepted',first;results=[first]
    print('CC20_ALIGNED_PREFLIGHT '+json.dumps({k:first[k] for k in ['native_frame_count','source_annotation_timestamps_absent','native_geometry_clock_join_verified','max_native_projection_error','consumer']}),flush=True)
    with cf.ThreadPoolExecutor(max_workers=3) as pool:
        for r in pool.map(lambda x:acquire(x,A,G),chosen[1:]):results.append(r)
    jsonl(ROOT/'SOURCE_TRIALS.jsonl',results);good=[r for r in results if r['status']=='accepted'];jsonl(ROOT/'video_records.jsonl',good)
    gs=collections.defaultdict(set)
    for r in good:gs[r['split']].add(r['origin_group'])
    assert all(not gs[a]&gs[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    q={'task':'native_all_object_perception_and_observed_camera_motion','selected_videos':len(chosen),'accepted_videos':len(good),'failed_videos':len(results)-len(good),
       'native_frames':sum(r['native_frame_count'] for r in good),'native_object_tracks':sum(r['native_object_tracks'] for r in good),'native_keypoint_targets':sum(r['native_keypoint_targets'] for r in good),
       'projection_rejected_keypoints':sum(r['projection_rejected_keypoints'] for r in good),'source_annotation_timestamps_absent':sum(r['source_annotation_timestamps_absent'] for r in good),
       'native_clock_camera_join_verified_videos':sum(r['native_geometry_clock_join_verified'] for r in good),'video_splits':dict(collections.Counter(r['split'] for r in good)),
       'perception_actual_batches':sum(r['consumer']['perception']['actual_batches'] for r in good),'motion_actual_batches':sum(r['consumer']['motion']['actual_batches'] for r in good),
       'motion_batches_with_supervision':sum(r['consumer']['motion']['batches_with_supervision'] for r in good),'cross_split_capture_batch_overlap':0,
       'native_MOVs_retained':True,'timestamp_default_zero_never_used':True,'all_objects_per_frame_no_ambiguous_single_object_target':True,
       'projection_convention':'author P @ camera XYZ; normalized NDC y,x swap with no flips','participant_and_physical_object_independence':'not proven',
       'native_pose_authority':'AR estimate, not independent physical measurement','human_utility_labels':0,'historical_intent_labels':0,'model_calls':0,'rights':'C-UDA-1.0','full_cameracoach_training_ready':False}
    (ROOT/'DATASET_CARD_RU.md').write_text('# Objectron: native-видео с проверенными кадрами и часами\n\nСохранены все 36 выбранных MOV, protobuf labels, AR geometry и all-frame числовые targets. Это ограниченный nine-category набор, не весь Objectron.\n\nFrameAnnotation.timestamp в первоисточнике отсутствует и не интерпретируется как ноль. Для каждой записи используем ARFrame.timestamp из geometry, только после проверки равного числа кадров, непрерывных frame_id и совпадения всех camera transforms. Playback time MOV и физическое время съёмки сохранены отдельно: они могут идти с разной скоростью.\n\nПерцептивная задача предсказывает ВСЕ native-объекты кадра, поэтому нет разных неизвестно выбранных целей при одинаковом RGB. Вход — только изображение. Keypoints3D/2D и camera pose не попадают во вход. Motion verifier получает before/after и native capture_dt. Его after-frame запрещено подавать online policy.\n\nПроекции проверены по конвенции авторского tutorial: P@XYZ, NDC y/x swapped. Ключевые точки с ошибкой больше 0.005 normalized не участвуют в loss. Visibility не обучается: default protobuf scalar не выдаётся за известный отрицательный target.\n\nПотоковый tensors() в reproduction_cc20/objectron_native_complete.py использует только PyAV/NumPy/Pillow; запуск модели не требуется. Записи video_records.jsonl имеют пути, SHA и реальные tensor hashes. Данные C-UDA-1.0, source LICENSE/README сохранены. CameraCoach utility, intent и iPhone parity не размечены/не доказаны.\n')
    finish(ROOT,'cc20-objectron-native-aligned',q)
if __name__=='__main__':main()
