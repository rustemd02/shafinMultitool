"""Native Objectron media, keypoints and AR camera motion for component tasks.
Captures are real; AR poses are estimates, not perfect geometric ground truth.
No photographer goal, compliance or utility is imputed to an observed movement.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,json,math,subprocess,sys
from pathlib import Path
import av,numpy as np
from google.protobuf.json_format import MessageToDict
from PIL import Image
from real_common import fetch,pin,repository_files,jsonl,write_json,digest,image_tensor,finish
ROOT=Path('cc20-objectron-real');ROOT.mkdir(exist_ok=True)
CATS=['bike','book','bottle','camera','cereal_box','chair','cup','laptop','shoe']
BASE='https://storage.googleapis.com/objectron/'

def group(vid):return '/'.join(vid.split('/')[:-1])

def acquire(item,A):
    vid=item['video_id'];out={**item,'status':'failed'};folder=ROOT/'native'/vid
    try:
        receipts=[]
        for name,url in [('annotation.pbdata',BASE+'annotations/'+vid+'.pbdata'),('geometry.pbdata',BASE+'videos/'+vid+'/geometry.pbdata'),('video.MOV',BASE+'videos/'+vid+'/video.MOV')]:
            r=fetch(url,folder/name,300_000_000);r['path']=str((folder/name).relative_to(ROOT));receipts.append(r)
        seq=A.Sequence();seq.ParseFromString((folder/'annotation.pbdata').read_bytes());fas=list(seq.frame_annotations)
        assert fas and len({f.frame_id for f in fas})==len(fas)
        times=np.array([f.timestamp for f in fas]);assert np.isfinite(times).all() and np.all(np.diff(times)>=0)
        selected={fas[i].frame_id:fas[i] for i in sorted(set(np.linspace(0,len(fas)-1,min(24,len(fas)),dtype=int).tolist()))}
        samples=[];pts=[];last=-math.inf;decoded=0
        with av.open(str(folder/'video.MOV')) as v:
            stream=v.streams.video[0];rotation_metadata=stream.metadata.get('rotate');rate=float(stream.average_rate) if stream.average_rate else None
            for index,frame in enumerate(v.decode(stream)):
                assert frame.pts is not None;time=float(frame.pts*frame.time_base);assert time>=last;last=time;decoded+=1;pts.append(time)
                if index not in selected:continue
                fa=selected[index];cam=fa.camera
                if len(cam.transform)!=16 or len(cam.intrinsics)!=9:raise ValueError('Missing native camera calibration')
                T=np.asarray(cam.transform).reshape(4,4);K=np.asarray(cam.intrinsics).reshape(3,3)
                assert np.isfinite(T).all() and np.isfinite(K).all() and abs(np.linalg.det(T[:3,:3])-1)<.02
                assert np.allclose(T[3],[0,0,0,1],atol=1e-4)
                p=ROOT/'frames'/vid/f'{index:06d}.png';p.parent.mkdir(parents=True,exist_ok=True);frame.to_image().save(p)
                objects=[]
                for obj in fa.annotations:
                    keypoints=[{'id':k.id,'xy':[k.point_2d.x,k.point_2d.y],'xyz_camera_m':[k.point_3d.x,k.point_3d.y,k.point_3d.z],'depth_m':k.point_2d.depth} for k in obj.keypoints]
                    values=np.array([k['xy']+k['xyz_camera_m'] for k in keypoints]);assert np.isfinite(values).all()
                    objects.append({'object_id':obj.object_id,'visibility':obj.visibility,'keypoints':keypoints})
                samples.append({'frame_id':index,'rgb':str(p.relative_to(ROOT)),'rgb_sha256':digest(p),'video_pts_s':time,'native_timestamp':fa.timestamp,
                   'dimensions':[frame.width,frame.height],'camera_native':MessageToDict(cam,preserving_proto_field_name=True),'camera_to_world':T.tolist(),'intrinsics':K.tolist(),'objects':objects,
                   'native_resolution':[cam.image_resolution_width,cam.image_resolution_height]})
        assert len(samples)==len(selected),(vid,len(samples),len(selected),decoded)
        # Native frame_id is the primary join. Measure timestamp agreement after a
        # single source-clock offset; do not silently nearest-match unrelated frames.
        offsets=np.array([x['native_timestamp']-x['video_pts_s'] for x in samples]);residual=float(np.max(np.abs(offsets-np.median(offsets))))
        clock_ok=residual<.1
        records=[];motion=[]
        for s in samples:
            for obj in s['objects']:
                record={'record_id':'objectron:'+vid+':'+str(s['frame_id'])+':'+str(obj['object_id']),'task_type':'native_subject_keypoint_perception','origin_group':item['origin_group'],'split':item['split'],
                  'observations':{'rgb':s['rgb'],'selected_subject':{'native_object_id':obj['object_id'],'prompt_origin':'native annotation reference, not recorded user tap'},'intent':None},
                  'targets':{'native_keypoints':obj['keypoints'],'native_visibility':obj['visibility'],'historical_intent':None,'operator_utility':None},
                  'loss_masks':{'native_keypoints':clock_ok,'native_visibility':clock_ok,'historical_intent':False,'operator_utility':False},
                  'provenance':{'dataset':'Objectron','video_id':vid,'native_frame_id':s['frame_id'],'video_pts_s':s['video_pts_s'],'native_timestamp':s['native_timestamp'],'rgb_sha256':s['rgb_sha256'],
                    'native_label_authority':'manual 3D object annotation projected with estimated AR pose','coordinate_frame':'native normalized top-left XY; no auto rotation applied','clock_join_verified':clock_ok,'rights':'C-UDA-1.0'}}
                records.append(record)
        for a,b in zip(samples,samples[1:]):
            Ta=np.asarray(a['camera_to_world']);Tb=np.asarray(b['camera_to_world']);relative=np.linalg.inv(Ta)@Tb
            motion.append({'record_id':'objectron-motion:'+vid+':'+str(a['frame_id'])+':'+str(b['frame_id']),'task_type':'observed_camera_motion_verifier','origin_group':item['origin_group'],'split':item['split'],
              'observations':{'before_rgb':a['rgb'],'after_rgb':b['rgb'],'dt_s':b['video_pts_s']-a['video_pts_s']},
              'targets':{'camera_to_world_a':a['camera_to_world'],'camera_to_world_b':b['camera_to_world'],'transform_b_in_a':relative.tolist(),'translation_m':relative[:3,3].tolist(),'rotation_rad':float(np.arccos(np.clip((np.trace(relative[:3,:3])-1)/2,-1,1))),
                'action_proposed':None,'action_performed':None,'goal_achieved':None,'human_utility':None},
              'loss_masks':{'relative_pose':clock_ok,'action_performed':False,'goal_achieved':False,'human_utility':False},'label_authority':'native_ar_pose_estimate','scope':'after-image allowed for verifier only, never online policy'})
        jsonl(folder/'sampled_frames.jsonl',samples);jsonl(folder/'perception_records.jsonl',records);jsonl(folder/'motion_records.jsonl',motion)
        h=hashlib.sha256();n=0
        for s in samples:
            with Image.open(ROOT/s['rgb']) as im:X=image_tensor(im)[None]
            assert X.shape==(1,3,224,224) and np.isfinite(X).all();h.update(X.tobytes());n+=1
        out.update(status='accepted',receipts=receipts,video_frames_decoded=decoded,native_annotation_frames=len(fas),native_objects=len(seq.objects),sampled_frames=len(samples),perception_records=len(records),motion_records=len(motion),
          timestamp_residual_max_s=residual,clock_join_verified=clock_ok,native_clock_offset_s=float(np.median(offsets)),rotation_metadata=rotation_metadata,video_rate=rate,dimensions=samples[0]['dimensions'],native_resolution=samples[0]['native_resolution'],
          actual_image_batches=n,tensor_stream_sha256=h.hexdigest(),participant_identity_available=False)
    except Exception as e:out['error']=type(e).__name__+': '+str(e)[:300]
    return out

if __name__=='__main__':
    repo='google-research-datasets/Objectron';rev=pin(repo)
    paths=['LICENSE','README.md','objectron/schema/annotation_data.proto','objectron/schema/object.proto','objectron/schema/a_r_capture_metadata.proto']+[f'index/{cat}_annotations_{s}' for cat in CATS for s in ['train','test']]
    repository_files(ROOT,repo,rev,paths)
    schema=ROOT/'source_repository/objectron/schema'
    subprocess.run([sys.executable,'-m','grpc_tools.protoc','-I'+str(schema),'--python_out='+str(schema),*map(str,schema.glob('*.proto'))],check=True)
    sys.path.insert(0,str(schema));import annotation_data_pb2 as A
    selection=[]
    for cat in CATS:
        train=(ROOT/f'source_repository/index/{cat}_annotations_train').read_text().splitlines();test=(ROOT/f'source_repository/index/{cat}_annotations_test').read_text().splitlines()
        # Use different native capture batches within each category. Source test
        # never enters train; batch IDs do not establish participant independence.
        chosen=[];groups=set()
        for vid in sorted(set(train),key=lambda x:hashlib.sha256(x.encode()).hexdigest()):
            if not vid.strip() or group(vid) in groups:continue
            chosen.append(vid);groups.add(group(vid))
            if len(chosen)==3:break
        for j,vid in enumerate(chosen):selection.append({'video_id':vid,'category':cat,'split':'validation' if j==2 else 'train','source_official_split':'train','origin_group':'objectron:'+group(vid)})
        for vid in sorted(set(test),key=lambda x:hashlib.sha256(x.encode()).hexdigest()):
            if vid.strip() and group(vid) not in groups:
                selection.append({'video_id':vid,'category':cat,'split':'test','source_official_split':'test','origin_group':'objectron:'+group(vid)});break
    write_json(ROOT/'PREDECLARED_SELECTION.json',{'revision':rev,'records':selection,'selection':'hash-ranked first distinct native batches, fixed before media outcomes','population_claim':'bounded nine-category component dataset, not whole Objectron'})
    first=acquire(selection[0],A);print('CC20_OBJECTRON_PREFLIGHT '+json.dumps(first),flush=True)
    assert first['status']=='accepted',first
    results=[first]
    with cf.ThreadPoolExecutor(max_workers=3) as pool:
        for out in pool.map(lambda x:acquire(x,A),selection[1:]):results.append(out)
    jsonl(ROOT/'SOURCE_TRIALS.jsonl',results);good=[x for x in results if x['status']=='accepted']
    splitgroups=collections.defaultdict(set)
    for x in good:splitgroups[x['split']].add(x['origin_group'])
    assert all(not splitgroups[a]&splitgroups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    q={'task':'real_subject_perception_and_observed_motion','source_revision':rev,'selected_videos':len(selection),'accepted_videos':len(good),'failed_videos':len(results)-len(good),
       'categories':dict(collections.Counter(x['category'] for x in good)),'video_splits':dict(collections.Counter(x['split'] for x in good)),
       **{key:sum(x[key] for x in good) for key in ['video_frames_decoded','native_annotation_frames','native_objects','sampled_frames','perception_records','motion_records','actual_image_batches']},
       'clock_join_validated_videos':sum(x['clock_join_verified'] for x in good),'cross_split_native_batch_overlap':0,'participant_independence':'not established','rights':'C-UDA-1.0','pose_authority':'AR estimate, not external measurement',
       'historical_intent_labels':0,'human_utility_labels':0,'model_calls':0,'policy_training_eligible':False,'full_cameracoach_training_ready':False,'image_orientation_parity_with_iPhone':'not tested'}
    (ROOT/'DATASET_CARD_RU.md').write_text('# Objectron: реальные объекты и движение камеры\n\nСохранены source-native MOV, protobuf-аннотации и AR geometry. Объекты размечены в 3D, позы камеры являются AR-оценками. Взята ограниченная партия из девяти категорий с раздельными capture batches, не весь исходный корпус.\n\nДве отдельные задачи: keypoint perception и observed-motion verifier. Послекадры входят только во вторую задачу. Нет известных intent, выполненного совета, успеха или human utility.\n\nКоординаты 2D сохранены native normalized top-left; видео декодируется без неявного автоповорота. Сохранены native resolution, video shape, rotate metadata, PTS и проверка часов. При неподтверждённом join loss выключается. Выбранный object ID — ссылка на native разметку, не пользовательский tap.\n\nДанные Google Objectron под C-UDA-1.0; полный текст и attribution из README сохранены. Разделение source batches не доказывает отсутствие повторяющихся участников или одинаковых физических предметов между партиями.\n')
    finish(ROOT,'cc20-objectron-real',q)
