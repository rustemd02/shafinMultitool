"""Real photographic supervision for subject perception, numeric-goal critique
and observed outcome comparison. NOT online action-ranking or human utility.
No model imports or inference. Source images and annotations remain unmodified.
"""
from __future__ import annotations
import argparse,collections,concurrent.futures,functools,hashlib,itertools,json,math,re,shutil,sys,time,urllib.parse
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
import requests
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'cc17'))
from release_pack import package
from acquire import digest,write_json
REPO='OpenIllumination/OpenIllumination'
REV='006beced878d3fb7187ded8e20ee63d9c5020fcb'
BASE=f'https://huggingface.co/datasets/{REPO}/resolve/{REV}/'
API=f'https://huggingface.co/api/datasets/{REPO}/tree/{REV}/'
CAMERAS=['CA4','CB5','CE3','CF3']
LIGHTS=list(range(1,14))
GOALS=[{'id':'specified_dark_tone','median_min':.02,'median_max':.15},
       {'id':'specified_midtone','median_min':.30,'median_max':.65}]
TOLERANCE=.015

def get(url):
    for attempt in range(5):
        r=requests.get(url,timeout=(20,100),headers={'User-Agent':'CameraCoach-CC20-data-acquisition/1'})
        if r.status_code==429:
            try:delay=min(180,max(10,int(r.headers.get('Retry-After','30'))))
            except ValueError:delay=30
            time.sleep(delay);continue
        if r.status_code>=500 and attempt<4:time.sleep(2**attempt);continue
        r.raise_for_status();return r
    raise RuntimeError('Source rate limit remained active; no bypass attempted')

def tree(path):
    url=API+urllib.parse.quote(path,safe='/')+'?limit=1000';out=[]
    while url:
        r=get(url);out.extend(r.json());url=r.links.get('next',{}).get('url')
    return out

def native(root,path):
    dest=root/'native'/path;dest.parent.mkdir(parents=True,exist_ok=True)
    r=get(BASE+urllib.parse.quote(path,safe='/'));data=r.content
    expected=None
    for x in [*r.history,r]:
        h=x.headers.get('X-Linked-Etag')
        if h and re.fullmatch('[0-9a-f]{64}',h.strip('"')):expected=h.strip('"');break
    sha=hashlib.sha256(data).hexdigest()
    if expected is not None and sha!=expected:raise ValueError('Source LFS checksum mismatch: '+path)
    if data.startswith(b'version https://git-lfs.github.com/'):raise ValueError('Received LFS pointer, not file')
    dest.write_bytes(data)
    return {'path':str(dest.relative_to(root)),'source_path':path,'source_revision':REV,'source_url':BASE+urllib.parse.quote(path,safe='/'),
            'bytes':len(data),'sha256':sha,'upstream_lfs_sha256':expected,'upstream_hash_verified':expected is not None}

def cluster(obj):
    name=re.sub(r'^obj_\d+_','',obj)
    for key in ['pumpkin','cup','bucket','sculpture','toy','pine','ball']:
        if key in name:return 'oi-object-family:'+key
    return 'oi-object-family:'+re.sub(r'\d+$','',name)

def plan(root):
    listing=tree('lighting_patterns')
    objs=sorted(x['path'].split('/')[-1] for x in listing if x['type']=='directory' and re.match(r'obj_\d+_',x['path'].split('/')[-1]))
    assert len(objs)>=30,{'unexpected_object_count':len(objs)}
    groups=sorted({cluster(o) for o in objs},key=lambda s:hashlib.sha256(('cc20-frozen-split:'+s).encode()).hexdigest())
    a=int(len(groups)*.70);b=int(len(groups)*.85)
    assignment={g:('train' if i<a else 'validation' if i<b else 'test') for i,g in enumerate(groups)}
    p={'source':REPO,'revision':REV,'objects':objs,'cameras':CAMERAS,'lights':LIGHTS,'goals':GOALS,'numeric_tolerance':TOLERANCE,
       'groups':{o:cluster(o) for o in objs},'group_splits':assignment,'split_unit':'name-family of physical objects, not views or light states',
       'not_claimed':'Unknown semantic asset relationships beyond source names; not an external blinded product test',
       'selection_rule':'Every numbered object in the lighting_patterns branch; fixed four camera IDs; all thirteen light patterns; no selection by image quality or target outcomes'}
    write_json(root/'ACQUISITION_PLAN.json',p);return p

def dump_lines(path,rows):
    with path.open('w') as f:
        for row in rows:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')

def tone(rgb,mask):
    selected=rgb[mask].astype(np.float32)/255.
    if selected.shape[0]<8:raise ValueError('Too few selected pixels at training resolution')
    y=selected@np.asarray([.2126,.7152,.0722],np.float32)
    return {'median':float(np.median(y)),'p10':float(np.quantile(y,.1)),'p90':float(np.quantile(y,.9)),
            'clip_fraction':float(np.mean(np.max(selected,axis=1)>=254/255)),
            'selected_pixels':int(mask.sum()),'mask_area_fraction':float(mask.mean())}

def goal_values(metrics,g):
    v=metrics['median'];lo=g['median_min'];hi=g['median_max']
    state=0 if v<lo else 2 if v>hi else 1
    return {'tone_class':state,'goal_satisfied':lo<=v<=hi,'distance_to_interval':max(lo-v,0.,v-hi),
            'label_reliable':min(abs(v-lo),abs(v-hi))>TOLERANCE}

@functools.lru_cache(maxsize=64)
def rgb_tensor(path):
    with Image.open(path) as im:
        if im.mode!='RGB' or im.size!=(224,224):raise ValueError('Unexpected prepared image format')
        return np.asarray(im,np.float32).transpose(2,0,1)/255.

@functools.lru_cache(maxsize=32)
def mask_tensor(path):
    with Image.open(path) as im:
        a=np.asarray(im)
        if a.shape!=(224,224):raise ValueError('Unexpected mask shape')
        return a>0

def records(root,task,split=None):
    names={'perception':'perception.jsonl','critique':'critique.jsonl','outcome':'outcome_pairs.jsonl'}
    if task not in names:raise ValueError('Unknown task')
    for line in (Path(root)/names[task]).open():
        r=json.loads(line)
        if split is None or r['split']==split:yield r

def batches(root,task,split=None,batch_size=16):
    root=Path(root)
    if batch_size<1:raise ValueError('batch_size must be positive')
    stream=iter(records(root,task,split))
    while rows:=list(itertools.islice(stream,batch_size)):
        obs=[r['observations'] for r in rows];X={};Y={};M={}
        if task=='outcome':
            X['rgb_pair']=np.stack([np.stack([rgb_tensor(str(root/o[k])) for k in ['rgb_a','rgb_b']]) for o in obs])
            X['subject_tap']=np.asarray([o['selected_tap'] for o in obs],np.float32)
            X['goal_bounds']=np.asarray([[o['goal']['median_min'],o['goal']['median_max']] for o in obs],np.float32)
            Y['goal_satisfied']=np.asarray([[r['targets']['a']['goal_satisfied'],r['targets']['b']['goal_satisfied']] for r in rows],bool)
            Y['closer_to_specified_interval']=np.asarray([r['targets']['closer_to_specified_interval'] for r in rows],np.int64)
            M['goal_satisfied']=np.asarray([[r['targets']['a']['label_reliable'],r['targets']['b']['label_reliable']] for r in rows],bool)
            M['closer_to_specified_interval']=np.ones(len(rows),bool)
        else:
            X['rgb']=np.stack([rgb_tensor(str(root/o['rgb'])) for o in obs]);X['subject_tap']=np.asarray([o['selected_tap'] for o in obs],np.float32)
            if task=='perception':
                Y['subject_mask']=np.stack([mask_tensor(str(root/r['targets']['object_mask'])) for r in rows]);M['subject_mask']=np.ones(len(rows),bool)
            else:
                X['goal_bounds']=np.asarray([[o['goal']['median_min'],o['goal']['median_max']] for o in obs],np.float32)
                Y['tone_class']=np.asarray([r['targets']['tone_class'] for r in rows],np.int64);M['tone_class']=np.asarray([r['targets']['label_reliable'] for r in rows],bool)
        M['human_utility']=np.zeros(len(rows),bool);M['operator_action']=np.zeros(len(rows),bool)
        for value in list(X.values())+list(Y.values()):
            if not np.isfinite(value).all():raise ValueError('Non-finite tensors')
        assert not any(k in X for k in ['mask','subject_mask','object_mask','after_metrics','camera_pose','light_id','object_id','split'])
        yield X,Y,M

def check(root):
    report={};groups=collections.defaultdict(set);hashes=collections.defaultdict(set)
    for task in ['perception','critique','outcome']:
        n=0;h=hashlib.sha256();bc=0
        for X,Y,M in batches(root,task):
            n+=len(next(iter(X.values())));bc+=1
            for tag,d in [('X',X),('Y',Y),('M',M)]:
                for k,v in sorted(d.items()):h.update((tag+k+str(v.dtype)+str(v.shape)).encode());h.update(v.tobytes())
        report[task]={'records':n,'actual_batches':bc,'tensor_stream_sha256':h.hexdigest()}
    for r in records(root,'perception'):
        groups[r['split']].add(r['origin_group']);hashes[r['provenance']['native_rgb_sha256']].add(r['split'])
        with Image.open(root/r['targets']['object_mask']) as im:m=np.asarray(im)>0
        x,y=r['observations']['selected_tap'];assert m[min(223,int(y*224)),min(223,int(x*224))]
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    assert not any(len(v)>1 for v in hashes.values())
    return {'task_streams':report,'groups_by_split':{k:len(v) for k,v in groups.items()},'cross_split_group_overlap':0,
            'cross_split_native_image_hash_overlap':0,'actual_model_calls':0,'human_utility_targets':0}

def acquire_object(root,obj,p):
    prefix='lighting_patterns/'+obj;receipts=[];native_frames={};native_sets={}
    for split in ['train','test','val']:
        entry=native(root,prefix+'/output/transforms_'+split+'.json');receipts.append(entry)
        data=json.loads((root/entry['path']).read_text());native_sets[split]=set(data['frames'])
        for camera,ann in data['frames'].items():
            if camera in native_frames:assert native_frames[camera]==ann
            native_frames[camera]=ann
    assert set(CAMERAS)<=set(native_frames),{'object':obj,'missing_cameras':sorted(set(CAMERAS)-set(native_frames))}
    selected=[]
    for cam in CAMERAS:
        selected.extend(prefix+'/output/'+typ+'/'+cam+'.png' for typ in ['obj_masks','com_masks'])
        selected.extend(prefix+f'/Lights/{light:03d}/raw_undistorted/{cam}.JPG' for light in LIGHTS)
    # Limited parallelism, honor HTTP 429 Retry-After. Failed objects are not silently omitted.
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:receipts.extend(pool.map(lambda path:native(root,path),selected))
    bypath={x['source_path']:x for x in receipts};photo_rows=[];critique=[];pairs=[];all_metrics=[];calibrations=[]
    for cam in CAMERAS:
        annotation=native_frames[cam];T=np.asarray(annotation['transform_matrix'],float);R=T[:3,:3]
        assert T.shape==(4,4) and np.isfinite(T).all() and np.allclose(T[3],[0,0,0,1],atol=1e-7)
        err=float(np.max(np.abs(R.T@R-np.eye(3))));det=float(np.linalg.det(R))
        assert err<1e-3 and abs(det-1)<1e-3,(obj,cam,err,det)
        assert 0<float(annotation['camera_angle_x'])<math.pi
        me=bypath[prefix+'/output/obj_masks/'+cam+'.png'];ce=bypath[prefix+'/output/com_masks/'+cam+'.png']
        with Image.open(root/me['path']) as mi:
            mm=np.asarray(mi);mask_size=mi.size
            if mm.ndim==3:mm=np.any(mm>0,axis=-1)
            else:mm=mm>0
        assert mm.any() and not mm.all()
        with Image.open(root/ce['path']) as ci:
            cc=np.asarray(ci);cc=np.any(cc>0,axis=-1) if cc.ndim==3 else cc>0
        assert cc.shape==mm.shape
        # Keep disagreement observable: source masks are SAM/matting-derived, not independent human gold.
        subset_violation=float(np.logical_and(mm,~cc).sum()/mm.sum())
        mask=Image.fromarray(mm.astype(np.uint8)*255).resize((224,224),Image.Resampling.NEAREST);m=np.asarray(mask)>0
        yy,xx=np.where(m);center=np.asarray([np.mean(xx),np.mean(yy)]);k=np.argmin((xx-center[0])**2+(yy-center[1])**2)
        tap=[(float(xx[k])+.5)/224,(float(yy[k])+.5)/224]
        dest=root/'derived'/obj/cam;dest.mkdir(parents=True,exist_ok=True);mask_path=dest/'object_mask.png';mask.save(mask_path)
        rows=[]
        for light in LIGHTS:
            source=bypath[prefix+f'/Lights/{light:03d}/raw_undistorted/{cam}.JPG']
            with Image.open(root/source['path']) as image:
                image.load();size=image.size;orientation=int(image.getexif().get(274,1))
                # Native mask alignment is stored-pixel based; nontrivial EXIF must be explicitly handled, not ignored.
                assert orientation==1,{'object':obj,'camera':cam,'exif_orientation':orientation}
                assert size==mask_size,{'object':obj,'camera':cam,'rgb_size':size,'mask_size':mask_size}
                rgb=ImageOps.exif_transpose(image).convert('RGB').resize((224,224),Image.Resampling.BILINEAR)
            rgb_path=dest/f'light_{light:03d}.png';rgb.save(rgb_path,compress_level=6);metrics=tone(np.asarray(rgb),m)
            rid=f'oi-lp:{obj}:{cam}:{light:03d}'
            prov={'source':REPO,'revision':REV,'native_rgb':source['path'],'native_rgb_sha256':source['sha256'],
                  'native_mask':me['path'],'mask_label_origin':'source SAM/matting-derived masks','camera_id':cam,'lighting_pattern_id':light,
                  'capture_time_intent':None,'native_light_idx_field':annotation.get('light_idx'),'light_id_authority':'source directory, not placeholder camera field',
                  'subject_initialization':'benchmark tap derived from source mask, not an actual user tap','license':'CC-BY-4.0 source declaration'}
            row={'record_id':rid,'task_type':'subject_perception','origin_group':p['groups'][obj],'object_id':obj,'split':p['group_splits'][p['groups'][obj]],
                 'observations':{'rgb':str(rgb_path.relative_to(root)),'selected_tap':tap},
                 'targets':{'object_mask':str(mask_path.relative_to(root))},'provenance':prov}
            photo_rows.append(row);rows.append((row,metrics));all_metrics.append({'record_id':rid,**metrics})
            for g in GOALS:
                critique.append({'record_id':rid+':'+g['id'],'task_type':'numeric_goal_critique','origin_group':row['origin_group'],'split':row['split'],
                  'observations':{**row['observations'],'goal':g},'targets':goal_values(metrics,g),
                  'provenance':{'real_image_id':rid,'intent_origin':'new_numeric_benchmark_specification_not_capture_time','label_authority':'measured_display_RGB_with_source_mask'},
                  'unknown_targets':{'human_preference':None,'human_utility':None,'recommended_physical_action':None}})
        for (a,am),(b,bm) in itertools.combinations(rows,2):
            for g in GOALS:
                av,bv=goal_values(am,g),goal_values(bm,g);diff=av['distance_to_interval']-bv['distance_to_interval']
                order=2 if abs(diff)<=TOLERANCE else 0 if diff<0 else 1
                pairs.append({'record_id':a['record_id']+'|'+b['record_id']+':'+g['id'],'task_type':'observed_lighting_outcome_comparison',
                  'origin_group':a['origin_group'],'split':a['split'],'observations':{'rgb_a':a['observations']['rgb'],'rgb_b':b['observations']['rgb'],'selected_tap':tap,'goal':g},
                  'targets':{'a':av,'b':bv,'closer_to_specified_interval':order},
                  'provenance':{'image_ids':[a['record_id'],b['record_id']],'same_camera':cam,'same_object':obj,
                    'condition_change':'two captured source lighting patterns; not a continuous operator intervention',
                    'intent_origin':'new_numeric_benchmark_specification_not_capture_time','label_authority':'measured_display_RGB_with_source_mask',
                    'confounders':['Source camera settings and ambient stability not independently audited','Masks are approximate source annotations','Light patterns may change multiple emitters']},
                  'unknown_targets':{'action_performed':None,'physical_feasibility':None,'human_preference':None,'human_utility':None},'online_policy_eligible':False})
        calibrations.append({'object':obj,'camera':cam,'native_annotation':annotation,'rotation_orthogonality_error':err,'rotation_determinant':det,
             'translation_units':'source units; metric scale not verified','raw_rgb_and_mask_size':list(mask_size),'object_outside_combined_fraction':subset_violation,
             'source_val_equals_test':native_sets['val']==native_sets['test'],'calibration_width_matches_stored_width':int(annotation['calib_imgw'])==mask_size[0]})
    return receipts,photo_rows,critique,pairs,all_metrics,calibrations

def run(shard,shards,pilot=False):
    label='cc20-real-lighting-pilot' if pilot else f'cc20-real-lighting-{shard:02d}'
    root=Path('cc20')/label;root.mkdir(parents=True,exist_ok=False)
    p=plan(root);objs=p['objects'][:1] if pilot else p['objects'][shard::shards]
    receipts=[native(root,'README.md'),native(root,'open_illumination.py'),native(root,'open_illumination_v2.py')]
    photos=[];critique=[];pairs=[];metrics=[];calib=[]
    for obj in objs:
        result=acquire_object(root,obj,p)
        for dest,src in zip([receipts,photos,critique,pairs,metrics,calib],result):dest.extend(src)
        print('CC20_PROGRESS '+json.dumps({'label':label,'object':obj,'native_photos':len(photos)}),flush=True)
    for name,data in [('SOURCE_RECEIPTS.jsonl',receipts),('perception.jsonl',photos),('critique.jsonl',critique),('outcome_pairs.jsonl',pairs),('MEASUREMENTS.jsonl',metrics),('CALIBRATION_AUDIT.jsonl',calib)]:dump_lines(root/name,data)
    assert len(photos)==len(objs)*len(CAMERAS)*len(LIGHTS)
    for rec in receipts:assert digest(root/rec['path'])==rec['sha256']
    first=check(root);rgb_tensor.cache_clear();mask_tensor.cache_clear();second=check(root);assert first==second
    eligibility={'source_license':'CC-BY-4.0 per pinned author dataset card','attribution_required':True,
       'perception':'source mask supervision; SAM/matting-origin, not independent manual gold',
       'critique':'specified numerical display-tone goal only; no artistic judgement',
       'outcome':'comparison of observed endpoints; both RGB images are legitimate inputs for this task',
       'online_action_ranking':False,'human_operator_utility':False,'full_cameracoach_training_ready':False}
    write_json(root/'ELIGIBILITY.json',eligibility)
    (root/'ATTRIBUTION.md').write_text('# OpenIllumination\n\nSource: https://huggingface.co/datasets/OpenIllumination/OpenIllumination/tree/'+REV+'\n\nAuthors: Isabella Liu, Linghao Chen, Ziyang Fu, Liwen Wu, Haian Jin, Zhong Li, Chin Ming Ryan Wong, Yi Xu, Ravi Ramamoorthi, Zexiang Xu and Hao Su.\nPaper: OpenIllumination: A Multi-Illumination Dataset for Inverse Rendering Evaluation on Real Objects.\nLicense declared by authors: CC BY 4.0, https://creativecommons.org/licenses/by/4.0/\n\nNative files unchanged. Changes: deterministic 224x224 RGB resize, nearest mask resize, name-family split, new numeric task definitions and computed display-tone targets. No endorsement implied.\n')
    (root/'README_RU.md').write_text('# CameraCoach v20: реальные объекты и изменение света\n\nПолностью полученная явно заданная подвыборка, не весь OpenIllumination. На каждый объект четыре фиксированные камеры и все 13 опубликованных световых схем. Native JPEG/PNG/JSON сохранены без изменений.\n\nЗадачи: выделение выбранного объекта; проверка заранее заданного числового диапазона яркости; сравнение двух наблюдаемых результатов света. Цели созданы для этого benchmark и не являются историческим intent автора.\n\nМаски созданы авторами с SAM/matting. Это source-native supervision, не независимый human gold. Точка выбора получена из маски; маска никогда не входит в X.\n\nAfter-изображения допустимы только в outcome task. Не подавать их в online policy. Не интерпретировать смену двух камер как физически проходимую траекторию. Единицы camera translation не объявлены метрами. Human preference/utility/action performed неизвестны.\n\nСчитайте независимость по объектам/группам, не по десяткам тысяч пар одних кадров. Все состояния одного объекта и похожих имён в одной выборке. Source val/test совпадают; здесь используется отдельное разбиение по объектам.\n\nДля чтения: from real_lighting import batches; batches(root, task="critique", split="train"). NumPy, Pillow, requests; нет моделей, Blender или GPU.\n')
    rep=root/'reproduction';rep.mkdir();shutil.copyfile(__file__,rep/'real_lighting.py')
    counts={'objects':len(objs),'views':len(objs)*len(CAMERAS),'native_rgb':len(photos),'native_masks':len(objs)*len(CAMERAS)*2,
      'source_receipts':len(receipts),'native_bytes':sum(x['bytes'] for x in receipts),'upstream_sha_verified_files':sum(x['upstream_hash_verified'] for x in receipts),
      'perception_records':len(photos),'critique_records':len(critique),'outcome_task_records':len(pairs),'unique_observed_light_pairs':len(pairs)//len(GOALS)}
    qa={'schema':'cc20.real_lighting_qa.v1','label':label,'revision':REV,'selection_complete':True,'objects_selected':objs,'counts':counts,'consumer':first,
        'all_native_file_hashes_rechecked':True,'second_full_tensor_pass_identical':True,'visual_human_review':False,'source_masks_independently_reannotated':False,
        'realworld_model_transfer_measured':False,'models_executed':0,'original_full_DoD':'NOT_COMPLETE','eligibility':eligibility}
    write_json(root/'QA.json',qa);print('CC20_QA '+json.dumps(qa),flush=True);package(root,label)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--shard',type=int,default=0);ap.add_argument('--shards',type=int,default=4);ap.add_argument('--pilot',action='store_true');a=ap.parse_args();run(a.shard,a.shards,a.pilot)
