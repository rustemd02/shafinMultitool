"""Data-only real handheld corpus. No model execution or subjective proxy gold.
Annotation frame_id is joined to decoded video ordinal; timestamps come from PTS,
never from Objectron's frequently unset annotation timestamp/visibility fields.
"""
from __future__ import annotations
import argparse,base64,collections,functools,hashlib,itertools,json,math,shutil,subprocess,sys,time
from pathlib import Path
import numpy as np
from PIL import Image
import requests
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'cc17'))
from acquire import write_json,digest
from release_pack import package
REV='46daaa0aca5b2e704bbc8deb99b0863bc9bf19a7'
BASE='https://storage.googleapis.com/objectron/'
CLASSES=['book','bottle','camera','cereal_box','cup','laptop','chair','bike','shoe']
CLASS_SPLIT={c:('train' if i<6 else 'validation' if i==6 else 'test') for i,c in enumerate(CLASSES)}
GOALS=[{'id':'specified_detail','height_min':.42,'height_max':.85},{'id':'specified_context','height_min':.10,'height_max':.23}]


def get(url,head=False):
    for attempt in range(4):
        r=(requests.head if head else requests.get)(url,timeout=(20,120),headers={'User-Agent':'CameraCoach-native-data/20'})
        if r.status_code==429:time.sleep(min(120,max(10,int(r.headers.get('Retry-After','30')))));continue
        if r.status_code>=500 and attempt<3:time.sleep(2**attempt);continue
        r.raise_for_status();return r
    raise RuntimeError('Source temporarily unavailable; no bypass attempted')

def save_native(root,path):
    r=get(BASE+path);data=r.content;expected=None
    for item in r.headers.get('x-goog-hash','').split(','):
        item=item.strip()
        if item.startswith('md5='):expected=item[4:]
    if expected:assert base64.b64encode(hashlib.md5(data).digest()).decode()==expected,'Provider checksum mismatch'
    dest=root/'native'/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
    return {'path':str(dest.relative_to(root)),'source_url':BASE+path,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
      'provider_md5':expected,'provider_generation':r.headers.get('x-goog-generation'),'provider_md5_verified':expected is not None}

def lines(path,rows):
    with path.open('w') as f:
        for r in rows:f.write(json.dumps(r,ensure_ascii=False,allow_nan=False)+'\n')

def choose(official,categories,count):
    selected=[];trials=[]
    for category in categories:
        candidates=(official/'index'/f'{category}_annotations_train').read_text().splitlines()
        candidates=sorted(set(s.strip() for s in candidates if s.strip()),key=lambda s:hashlib.sha256(('cc20:'+s).encode()).hexdigest())
        batches=set();found=[]
        for seq in candidates[:240]:
            batch='/'.join(seq.split('/')[:2])
            if batch in batches:continue
            try:
                r=get(BASE+'videos/'+seq+'/video.MOV',head=True);n=int(r.headers.get('content-length','0'))
            except requests.HTTPError as e:
                if e.response is not None and e.response.status_code in [403,404]:trials.append({'sequence':seq,'status':e.response.status_code});continue
                raise
            trials.append({'sequence':seq,'bytes':n,'criterion':'0 < bytes <= 32 MiB; distinct source batch; hashed order'})
            if not 0<n<=32*1024*1024:continue
            batches.add(batch);found.append({'sequence':seq,'category':category,'origin_group':'objectron:'+batch,'split':CLASS_SPLIT[category],'advertised_video_bytes':n})
            if len(found)==count:break
        assert len(found)==count,{'category':category,'obtained':len(found),'required':count}
        selected.extend(found)
    return selected,trials

def matrix(values):
    if len(values)!=16:return None
    a=np.asarray(values,float).reshape(4,4)
    if not np.isfinite(a).all() or not np.allclose(a[3],[0,0,0,1],atol=1e-4):return None
    if np.max(np.abs(a[:3,:3].T@a[:3,:3]-np.eye(3)))>.003 or abs(np.linalg.det(a[:3,:3])-1)>.003:return None
    return a

def annotation_objects(a):
    out={}
    for obj in a.annotations:
        keypoints=np.asarray([[k.point_2d.x,k.point_2d.y] for k in obj.keypoints],float)
        if keypoints.shape!=(9,2) or not np.isfinite(keypoints).all():continue
        minimum=keypoints[1:].min(axis=0);maximum=keypoints[1:].max(axis=0)
        box=np.r_[minimum,maximum];clipped=np.clip(box,0.,1.)
        extent=clipped[2:]-clipped[:2]
        if np.any(extent<=0):continue
        present={f.name for f,v in obj.ListFields()}
        out[int(obj.object_id)]={'keypoints':keypoints.tolist(),'projected_cuboid_bbox':box.tolist(),'clipped_bbox':clipped.tolist(),
          'height_fraction':float(extent[1]),'all_projected_corners_inside':bool(((keypoints[1:]>=0)&(keypoints[1:]<=1)).all()),
          'projected_center_hint':keypoints[0].tolist(),'center_hint_inside':bool(((keypoints[0]>=0)&(keypoints[0]<=1)).all()),
          'source_visibility':float(obj.visibility) if 'visibility' in present else None,
          'visibility_is_mask_or_visible_surface_fraction':False}
    return out

def target_goal(value,g):
    h=value['height_fraction'];lo,hi=g['height_min'],g['height_max']
    return {'height_class':0 if h<lo else 2 if h>hi else 1,'goal_achieved':bool(lo<=h<=hi and value['all_projected_corners_inside']),
      'projected_cuboid_inside':value['all_projected_corners_inside'],'height_fraction':h,'reliable':min(abs(h-lo),abs(h-hi))>.01}

@functools.lru_cache(maxsize=64)
def image(path):
    with Image.open(path) as im:
        assert im.size==(224,224) and im.mode=='RGB'
        return np.asarray(im,np.float32).transpose(2,0,1)/255.

def records(root,task,split=None):
    names={'perception':'temporal_perception.jsonl','critique':'framing_critique.jsonl','outcome':'framing_outcomes.jsonl'}
    for line in (Path(root)/names[task]).open():
        r=json.loads(line)
        if split is None or r['split']==split:yield r

def batches(root,task,split=None,batch_size=8):
    root=Path(root);iterator=iter(records(root,task,split))
    while rows:=list(itertools.islice(iterator,batch_size)):
        X={};Y={};M={};obs=[r['observations'] for r in rows]
        if task=='outcome':
            X['rgb_pair']=np.stack([np.stack([image(str(root/o[k])) for k in ['rgb_before','rgb_after']]) for o in obs])
            X['subject_center_hint']=np.asarray([o['selected_center_hint'] for o in obs],np.float32)
            X['elapsed_seconds']=np.asarray([o['elapsed_seconds'] for o in obs],np.float32)
            X['goal_bounds']=np.asarray([[o['goal']['height_min'],o['goal']['height_max']] for o in obs],np.float32)
            Y['goal_achieved']=np.asarray([r['targets']['after']['goal_achieved'] for r in rows],bool)
            Y['height_delta']=np.asarray([r['targets']['height_delta'] for r in rows],np.float32)
            M['goal_achieved']=np.asarray([r['targets']['after']['reliable'] for r in rows],bool);M['height_delta']=np.ones(len(rows),bool)
        else:
            assert all(len(o['history'])==3 and all(h['relative_time_s']<=0 for h in o['history']) and o['history'][-1]['relative_time_s']==0 for o in obs)
            X['rgb_history']=np.stack([np.stack([image(str(root/h['rgb'])) for h in o['history']]) for o in obs])
            X['history_time_s']=np.asarray([[h['relative_time_s'] for h in o['history']] for o in obs],np.float32)
            X['subject_center_hint']=np.asarray([o['selected_center_hint'] for o in obs],np.float32)
            if task=='perception':
                Y['projected_cuboid_bbox']=np.asarray([r['targets']['current_subject']['clipped_bbox'] for r in rows],np.float32)
                Y['projected_keypoints']=np.asarray([r['targets']['current_subject']['keypoints'] for r in rows],np.float32)
                Y['observed_camera_translation']=np.asarray([r['targets']['observed_camera_translation'] or [0.,0.,0.] for r in rows],np.float32)
                M['observed_camera_translation']=np.asarray([r['targets']['observed_camera_translation'] is not None for r in rows],bool)
                M['projected_cuboid_bbox']=np.ones(len(rows),bool);M['projected_keypoints']=np.isfinite(Y['projected_keypoints']).all(axis=-1)
            else:
                X['goal_bounds']=np.asarray([[o['goal']['height_min'],o['goal']['height_max']] for o in obs],np.float32)
                Y['height_class']=np.asarray([r['targets']['height_class'] for r in rows],np.int64);M['height_class']=np.asarray([r['targets']['reliable'] for r in rows],bool)
        M['human_utility']=np.zeros(len(rows),bool);M['recommended_action']=np.zeros(len(rows),bool)
        assert not any(k in X for k in ['bbox','depth','pose','camera_transform','sequence_id','category','object_id','after_metrics'])
        for array in list(X.values())+list(Y.values()):assert np.isfinite(array).all()
        yield X,Y,M

def check(root):
    result={}
    for task in ['perception','critique','outcome']:
        n=0;nb=0;sha=hashlib.sha256()
        for X,Y,M in batches(root,task):
            n+=len(next(iter(X.values())));nb+=1
            for tag,d in [('X',X),('Y',Y),('M',M)]:
                for k,v in sorted(d.items()):sha.update((tag+k+str(v.dtype)+str(v.shape)).encode());sha.update(v.tobytes())
        result[task]={'rows':n,'batches':nb,'sha256':sha.hexdigest()}
    return result

def acquire(root,item,P):
    sid=item['sequence'];video=save_native(root,'videos/'+sid+'/video.MOV');annfile=save_native(root,'annotations/'+sid+'.pbdata')
    assert video['bytes']==item['advertised_video_bytes']
    seq=P.Sequence();seq.ParseFromString((root/annfile['path']).read_bytes());anns=list(seq.frame_annotations)
    vp=root/video['path'];probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(vp)]))
    stream=next(v for v in probe['streams'] if v['codec_type']=='video')
    decoded=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time,width,height','-of','json',str(vp)]))['frames']
    assert len(anns)==len(decoded) and len(anns)>=13,{'sequence':sid,'annotation_frames':len(anns),'video_frames':len(decoded)}
    assert [a.frame_id for a in anns]==list(range(len(anns)))
    pts=np.asarray([float(f['best_effort_timestamp_time']) for f in decoded]);assert np.isfinite(pts).all() and np.all(np.diff(pts)>0)
    rotation=next((float(d['rotation']) for d in stream.get('side_data_list',[]) if 'rotation' in d),0.)
    # Source annotation convention/tutorial uses display-oriented portrait images.
    # Do not silently accept another orientation without its own transform audit.
    assert abs(rotation+90.)<.001,{'sequence':sid,'unvalidated_display_rotation':rotation}
    sample_ids=np.unique(np.rint(np.linspace(0,len(anns)-1,13)).astype(int));assert len(sample_ids)==13
    dest=root/'derived'/sid;dest.mkdir(parents=True,exist_ok=True)
    selection='+'.join(f'eq(n\\,{i})' for i in sample_ids)
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-i',str(vp),'-vf',f'select={selection},scale=224:224:flags=bilinear','-fps_mode','vfr','-pix_fmt','rgb24',str(dest/'%03d.png')],check=True,timeout=180)
    files=sorted(dest.glob('*.png'));assert len(files)==13
    states=[];camera_audit=[]
    for index,path in zip(sample_ids,files):
        a=anns[int(index)];objects=annotation_objects(a);T=matrix(a.camera.transform)
        assert int(a.camera.image_resolution_width)==stream['width'] and int(a.camera.image_resolution_height)==stream['height']
        states.append({'frame_id':int(index),'time_s':float(pts[index]),'rgb':str(path.relative_to(root)),'rgb_sha256':digest(path),'objects':objects,'camera_transform':T.tolist() if T is not None else None})
        with Image.open(path) as im:im.load();assert im.mode=='RGB' and im.size==(224,224)
        camera_audit.append({'frame_id':int(index),'camera_transform':list(a.camera.transform),'view_matrix':list(a.camera.view_matrix),
            'projection_matrix':list(a.camera.projection_matrix),'intrinsics':list(a.camera.intrinsics),'tracking_state':int(a.camera.tracking_state),
            'raw_annotation_timestamp':float(a.timestamp),'timestamp_field_present':any(f.name=='timestamp' for f,v in a.ListFields())})
    rows=[];cr=[];pairs=[]
    for k in range(2,len(states)):
        s=states[k];previous=states[k-1];history=[{key:st[key] for key in ['rgb','frame_id','rgb_sha256']}|{'relative_time_s':st['time_s']-s['time_s']} for st in states[k-2:k+1]]
        common=set(s['objects'])&set(states[k-2]['objects'])&set(previous['objects'])
        for oid in sorted(common):
            subject=s['objects'][oid]
            if not subject['center_hint_inside']:continue
            delta=None
            if s['camera_transform'] is not None and previous['camera_transform'] is not None:
                T0=np.asarray(previous['camera_transform']);T1=np.asarray(s['camera_transform']);delta=(T0[:3,:3].T@(T1[:3,3]-T0[:3,3])).tolist()
            rid=f'objectron:{sid}:{s["frame_id"]}:{oid}'
            obs={'history':history,'selected_center_hint':subject['projected_center_hint'],'cutoff_time_s':s['time_s']}
            prov={'source':'Objectron','source_code_revision':REV,'sequence':sid,'source_split':'train','native_video_sha256':video['sha256'],'annotation_sha256':annfile['sha256'],
                'alignment':'exact native frame_id to decoded ordinal; video PTS authoritative','display_orientation':'source normalized 2D coordinates; ffmpeg autorotate -90 display matrix to portrait',
                'subject_hint_origin':'projected 3D cuboid center, not a human tap or guaranteed visible surface','label_authority':'source 3D annotation and AR camera estimates',
                'capture_time_intent':None,'human_utility':None,'license':'C-UDA-1.0'}
            rows.append({'record_id':rid,'task_type':'temporal_subject_perception','origin_group':item['origin_group'],'split':item['split'],'observations':obs,
                'targets':{'current_subject':subject,'observed_camera_translation':delta,'translation_frame':'previous AR camera-local coordinates, source units'},'provenance':prov})
            for goal in GOALS:
                cr.append({'record_id':rid+':'+goal['id'],'task_type':'numeric_framing_critique','origin_group':item['origin_group'],'split':item['split'],
                    'observations':{**obs,'goal':goal},'targets':target_goal(subject,goal),'provenance':{'source_record':rid,'intent_origin':'new numeric task, not historical photographer intention'}})
    for first,second in zip(states[:-1],states[1:]):
        for oid in sorted(set(first['objects'])&set(second['objects'])):
            a,b=first['objects'][oid],second['objects'][oid]
            if not a['center_hint_inside']:continue
            for goal in GOALS:
                pairs.append({'record_id':f'{sid}:{first["frame_id"]}:{second["frame_id"]}:{oid}:{goal["id"]}','task_type':'observed_framing_outcome',
                    'origin_group':item['origin_group'],'split':item['split'],'observations':{'rgb_before':first['rgb'],'rgb_after':second['rgb'],
                        'selected_center_hint':a['projected_center_hint'],'elapsed_seconds':second['time_s']-first['time_s'],'goal':goal},
                    'targets':{'before':target_goal(a,goal),'after':target_goal(b,goal),'height_delta':b['height_fraction']-a['height_fraction']},
                    'provenance':{'native_video_sha256':video['sha256'],'label_authority':'native projected cuboid','intent_origin':'new numeric task',
                        'comparison_validity':'observed temporal sequence; lighting/object motion not independently controlled','causal_effect_of_camera_action':None},
                    'unknown_targets':{'action_recommended':None,'physical_path_feasible':None,'human_utility':None},'online_action_ranking':False})
    audit={**item,'native_video':video,'native_annotations':annfile,'video_frame_count':len(decoded),'annotation_frame_count':len(anns),
        'frame_ids_exactly_joined':True,'video_pts_seconds':pts.tolist(),'source_annotation_timestamps_all_zero':all(a.timestamp==0 for a in anns),
        'native_duration_seconds':float(stream.get('duration',pts[-1]-pts[0])),'display_rotation':rotation,'stored_resolution':[stream['width'],stream['height']],
        'derivative_resolution':[224,224],'sampled_frames':states,'sampled_camera_metadata':camera_audit,
        'source_mask_or_surface_visibility_inferred':False,'coordinate_visual_review_by_human':False}
    assert rows and cr and pairs,{'sequence':sid,'no_valid_tasks':True}
    return [video,annfile],rows,cr,pairs,audit

def run(shard,per_class=8,pilot=False):
    official=Path('official_objectron').resolve();sys.path.insert(0,str(official));from objectron.schema import annotation_data_pb2 as P
    categories=['book'] if pilot else CLASSES[shard::3]
    label='cc20-objectron-pilot' if pilot else f'cc20-objectron-{shard:02d}';root=Path('cc20')/label;root.mkdir(parents=True,exist_ok=False)
    selected,trials=choose(official,categories,1 if pilot else per_class)
    write_json(root/'ACQUISITION_PLAN.json',{'code_revision':REV,'selected':selected,'selection_trials':trials,'all_class_splits':CLASS_SPLIT,
        'criteria':'eight hashed-order videos per category, distinct capture batches, raw size <=32MiB, official train index only',
        'split_limit':'category-heldout; semantic identity beyond source batches not established','numeric_goals':GOALS})
    shutil.copyfile(official/'LICENSE',root/'LICENSE_CUDA.txt')
    code=root/'source_schema';shutil.copytree(official/'objectron/schema',code)
    (root/'ATTRIBUTION.md').write_text('Objectron Dataset. Adel Ahmadyan, Liangkai Zhang, Artsiom Ablavatski, Jianing Wei and Matthias Grundmann. Source https://github.com/google-research-datasets/Objectron at '+REV+' . Data governed by the included Computational Use of Data Agreement v1.0 (C-UDA). Recipients of data must comply with that agreement; inclusion does not clear unrelated third-party rights. Native MOV and protobuf bytes unchanged; derived frames are autorotated/resized, groups and numeric task labels are new.\n')
    native=[];perception=[];critique=[];outcomes=[];audits=[]
    for item in selected:
        a,b,c,d,e=acquire(root,item,P);native.extend(a);perception.extend(b);critique.extend(c);outcomes.extend(d);audits.append(e)
        print('CC20_HANDHELD_PROGRESS '+json.dumps({'label':label,'sequence':item['sequence'],'videos_complete':len(audits)}),flush=True)
    for name,items in [('NATIVE_RECEIPTS.jsonl',native),('temporal_perception.jsonl',perception),('framing_critique.jsonl',critique),('framing_outcomes.jsonl',outcomes),('SEQUENCE_AUDIT.jsonl',audits)]:lines(root/name,items)
    for f in native:assert digest(root/f['path'])==f['sha256']
    first=check(root);image.cache_clear();assert first==check(root)
    groups=collections.defaultdict(set)
    for r in perception:groups[r['split']].add(r['origin_group'])
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    (root/'README_RU.md').write_text('# Реальные видео Objectron\n\nНативные MOV и protobuf-аннотации получены полностью для объявленной подвыборки. Кадры привязаны по frame_id к фактическому порядку декодирования; время — реальные PTS, а не нулевые timestamps аннотаций. RGB авторотирован в portrait по display matrix.\n\nЗадачи: temporal perception выбранного субъекта, числовая проверка крупности и проверка результата двух наблюдаемых кадров. Bbox — проекция 3D cuboid, не маска видимой поверхности. Visibility=0 при отсутствующем поле не считается окклюзией. Центр кубоида — benchmark hint, не пользовательский tap.\n\nНамерение задано как новая числовая задача. Нет исторического capture-time intent, causal counterfactual, полезности совета человеку или доказанной безопасности перемещения. Изменения света/объектов не исключены. Послекадр подаётся только в outcome task, не в online policy.\n\nВсе категории и capture batches разделены до оценки меток; test из двух новых категорий, поэтому не является оценкой обычного in-domain распределения. raw video не заменён компактной копией. batches(root, task="perception"/"critique"/"outcome", split="train") возвращает X,Y,loss masks.\n')
    rep=root/'reproduction';rep.mkdir();shutil.copyfile(__file__,rep/'objectron_data.py')
    qa={'schema':'cc20.objectron_qa.v1','label':label,'selected_videos_complete':len(selected)==len(audits),
        'counts':{'videos':len(audits),'categories':len(categories),'source_frames':sum(a['video_frame_count'] for a in audits),'sampled_rgb':13*len(audits),
          'duration_seconds':sum(a['native_duration_seconds'] for a in audits),'native_bytes':sum(f['bytes'] for f in native),'perception_records':len(perception),'critique_records':len(critique),'outcome_records':len(outcomes)},
        'consumer':first,'second_tensor_pass_identical':True,'all_native_file_sha_verified':True,'model_calls':0,'human_utility_labels':0,
        'source_mask_claims':0,'historical_intents_invented':0,'full_cameracoach_training_ready':False,'real_model_transfer_measured':False,
        'split_groups':{k:len(v) for k,v in groups.items()},'subject_hint':'native projected cuboid center, not guaranteed visible surface'}
    write_json(root/'QA.json',qa)
    proof=Path('proof');proof.mkdir(exist_ok=True);write_json(proof/'QA.json',qa);write_json(proof/'NATIVE_HASHES.json',native)
    print('CC20_HANDHELD_QA '+json.dumps(qa),flush=True);package(root,label)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--per-class',type=int,default=8);p.add_argument('--pilot',action='store_true');a=p.parse_args();run(a.shard,a.per_class,a.pilot)
