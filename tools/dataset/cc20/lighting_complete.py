"""Finish the author-listed OpenIllumination subset without relabeling prior shards.
Missing combined pedestal masks are optional diagnostics, NOT subject targets.
Subject masks, calibration and all selected native photographs remain required.
"""
from __future__ import annotations
import argparse,collections,concurrent.futures,hashlib,itertools,json,math,re,shutil
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
import requests
import real_lighting as L
AUTHOR_URL='https://oppo-us-research.github.io/OpenIllumination/data.json'

def make_plan(root,part):
    old=L.plan(root)
    body=L.get(AUTHOR_URL).content
    (root/'AUTHOR_OBJECT_INVENTORY.json').write_bytes(body)
    author=sorted(x['data_name'] for x in json.loads(body)['obj_list'])
    assert len(author)==64 and len(set(author))==64
    dirs={x['path'].split('/')[-1] for x in L.tree('lighting_patterns') if x['type']=='directory'}
    assert set(author)<=dirs,{'missing_author_objects':sorted(set(author)-dirs)}
    if part=='extra':objs=sorted(set(author)-set(old['objects']))
    else:objs=[o for o in old['objects'][int(part)::4] if o in author]
    p=dict(old);p['initial_objects']=old['objects'];p['objects']=author;p['selected_objects']=objs
    p['excluded_auxiliary_directories']=sorted(set(old['objects'])-set(author))
    p['author_inventory_sha256']=hashlib.sha256(body).hexdigest();p['author_inventory_url']=AUTHOR_URL
    p['groups']=dict(old['groups']);p['group_splits']=dict(old['group_splits'])
    for obj in author:
        if obj in p['groups']:continue
        normalized=re.sub(r'^(obj_\d+)-',r'\1_',obj)
        group=L.cluster(normalized);p['groups'][obj]=group
        if group not in p['group_splits']:
            value=int(hashlib.sha256(('cc20-new-group:'+group).encode()).hexdigest(),16)%100
            p['group_splits'][group]='train' if value<70 else 'validation' if value<85 else 'test'
    assert all(p['groups'][o]==old['groups'][o] and p['group_splits'][old['groups'][o]]==old['group_splits'][old['groups'][o]] for o in old['objects'])
    p['existing_assignments_unchanged']=True
    p['selection_rule']='64 author-listed physical objects; four predeclared cameras and thirteen light conditions. Extra background/mirrorball folders are not objects.'
    L.write_json(root/'ACQUISITION_PLAN.json',p);return p

def acquire(root,obj,p):
    prefix='lighting_patterns/'+obj;receipts=[];missing=[];frames={};sets={}
    for split in ['train','test','val']:
        entry=L.native(root,prefix+'/output/transforms_'+split+'.json');receipts.append(entry)
        data=json.loads((root/entry['path']).read_text());sets[split]=set(data['frames'])
        for camera,ann in data['frames'].items():
            if camera in frames:assert frames[camera]==ann
            frames[camera]=ann
    assert set(L.CAMERAS)<=set(frames)
    paths=[]
    for cam in L.CAMERAS:
        paths.append(prefix+'/output/obj_masks/'+cam+'.png')
        paths.extend(prefix+f'/Lights/{light:03d}/raw_undistorted/{cam}.JPG' for light in L.LIGHTS)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:receipts.extend(pool.map(lambda s:L.native(root,s),paths))
    bypath={x['source_path']:x for x in receipts}
    for cam in L.CAMERAS:
        path=prefix+'/output/com_masks/'+cam+'.png'
        try:
            entry=L.native(root,path);receipts.append(entry);bypath[path]=entry
        except requests.HTTPError as e:
            if e.response is None or e.response.status_code!=404:raise
            missing.append({'source_path':path,'status':404,'role':'optional_combined_object_and_support_mask','replacement':None})
    photos=[];critique=[];pairs=[];metrics_rows=[];calib=[]
    for cam in L.CAMERAS:
        annotation=frames[cam];T=np.asarray(annotation['transform_matrix'],float)
        assert T.shape==(4,4) and np.isfinite(T).all() and np.allclose(T[3],[0,0,0,1],atol=1e-7)
        R=T[:3,:3];err=float(np.max(np.abs(R.T@R-np.eye(3))));det=float(np.linalg.det(R))
        assert err<1e-3 and abs(det-1)<1e-3 and 0<float(annotation['camera_angle_x'])<math.pi
        me=bypath[prefix+'/output/obj_masks/'+cam+'.png'];ce=bypath.get(prefix+'/output/com_masks/'+cam+'.png')
        with Image.open(root/me['path']) as im:
            mm=np.asarray(im);mask_size=im.size;mm=np.any(mm>0,axis=-1) if mm.ndim==3 else mm>0
        assert mm.any() and not mm.all()
        violation=None
        if ce is not None:
            with Image.open(root/ce['path']) as im:
                cc=np.asarray(im);cc=np.any(cc>0,axis=-1) if cc.ndim==3 else cc>0
            assert cc.shape==mm.shape;violation=float(np.logical_and(mm,~cc).sum()/mm.sum())
        mask=Image.fromarray(mm.astype(np.uint8)*255).resize((224,224),Image.Resampling.NEAREST);m=np.asarray(mask)>0
        yy,xx=np.where(m);k=np.argmin((xx-np.mean(xx))**2+(yy-np.mean(yy))**2)
        tap=[(float(xx[k])+.5)/224,(float(yy[k])+.5)/224]
        dest=root/'derived'/obj/cam;dest.mkdir(parents=True,exist_ok=True);mp=dest/'object_mask.png';mask.save(mp)
        states=[]
        for light in L.LIGHTS:
            source=bypath[prefix+f'/Lights/{light:03d}/raw_undistorted/{cam}.JPG']
            with Image.open(root/source['path']) as image:
                image.load();assert int(image.getexif().get(274,1))==1 and image.size==mask_size
                rgb=ImageOps.exif_transpose(image).convert('RGB').resize((224,224),Image.Resampling.BILINEAR)
            rp=dest/f'light_{light:03d}.png';rgb.save(rp,compress_level=6);metrics=L.tone(np.asarray(rgb),m)
            rid=f'oi-lp:{obj}:{cam}:{light:03d}';group=p['groups'][obj]
            prov={'source':L.REPO,'revision':L.REV,'native_rgb':source['path'],'native_rgb_sha256':source['sha256'],
                'native_mask':me['path'],'mask_label_origin':'source SAM/matting-derived masks','camera_id':cam,'lighting_pattern_id':light,
                'capture_time_intent':None,'native_light_idx_field':annotation.get('light_idx'),'light_id_authority':'source directory, not placeholder camera field',
                'subject_initialization':'benchmark tap derived from source mask, not an actual user tap','license':'CC-BY-4.0 source declaration'}
            row={'record_id':rid,'task_type':'subject_perception','origin_group':group,'object_id':obj,'split':p['group_splits'][group],
                'observations':{'rgb':str(rp.relative_to(root)),'selected_tap':tap},'targets':{'object_mask':str(mp.relative_to(root))},'provenance':prov}
            photos.append(row);states.append((row,metrics));metrics_rows.append({'record_id':rid,**metrics})
            for g in L.GOALS:
                critique.append({'record_id':rid+':'+g['id'],'task_type':'numeric_goal_critique','origin_group':group,'split':row['split'],
                    'observations':{**row['observations'],'goal':g},'targets':L.goal_values(metrics,g),
                    'provenance':{'real_image_id':rid,'intent_origin':'new_numeric_benchmark_specification_not_capture_time','label_authority':'measured_display_RGB_with_source_mask'},
                    'unknown_targets':{'human_preference':None,'human_utility':None,'recommended_physical_action':None}})
        for (a,am),(b,bm) in itertools.combinations(states,2):
            for g in L.GOALS:
                av,bv=L.goal_values(am,g),L.goal_values(bm,g);diff=av['distance_to_interval']-bv['distance_to_interval']
                order=2 if abs(diff)<=L.TOLERANCE else 0 if diff<0 else 1
                pairs.append({'record_id':a['record_id']+'|'+b['record_id']+':'+g['id'],'task_type':'observed_lighting_outcome_comparison',
                    'origin_group':a['origin_group'],'split':a['split'],'observations':{'rgb_a':a['observations']['rgb'],'rgb_b':b['observations']['rgb'],'selected_tap':tap,'goal':g},
                    'targets':{'a':av,'b':bv,'closer_to_specified_interval':order},
                    'provenance':{'image_ids':[a['record_id'],b['record_id']],'same_camera':cam,'same_object':obj,
                        'condition_change':'two captured source lighting patterns; not a continuous operator intervention',
                        'intent_origin':'new_numeric_benchmark_specification_not_capture_time','label_authority':'measured_display_RGB_with_source_mask',
                        'confounders':['Source camera settings and ambient stability not independently audited','Masks are approximate source annotations','Light patterns may change multiple emitters']},
                    'unknown_targets':{'action_performed':None,'physical_feasibility':None,'human_preference':None,'human_utility':None},'online_policy_eligible':False})
        calib.append({'object':obj,'camera':cam,'native_annotation':annotation,'rotation_orthogonality_error':err,'rotation_determinant':det,
            'translation_units':'source units; metric scale not verified','raw_rgb_and_mask_size':list(mask_size),'object_outside_combined_fraction':violation,
            'combined_mask_available':ce is not None,'source_val_equals_test':sets['val']==sets['test'],
            'calibration_width_matches_stored_width':int(annotation['calib_imgw'])==mask_size[0]})
    return receipts,photos,critique,pairs,metrics_rows,calib,missing

def run(part):
    if part not in ['00','03','extra']:raise ValueError('Only missing shards and omitted author objects')
    label='cc20-real-lighting-finish-'+part;root=Path('cc20')/label;root.mkdir(parents=True,exist_ok=False);p=make_plan(root,part)
    objs=p['selected_objects'];assert objs
    receipts=[L.native(root,n) for n in ['README.md','open_illumination.py','open_illumination_v2.py']]
    photos=[];critique=[];pairs=[];metrics=[];calib=[];missing=[]
    for obj in objs:
        result=acquire(root,obj,p)
        for dst,src in zip([receipts,photos,critique,pairs,metrics,calib,missing],result):dst.extend(src)
        print('CC20_PROGRESS '+json.dumps({'label':label,'object':obj,'native_photos':len(photos)}),flush=True)
    for name,data in [('SOURCE_RECEIPTS.jsonl',receipts),('perception.jsonl',photos),('critique.jsonl',critique),('outcome_pairs.jsonl',pairs),('MEASUREMENTS.jsonl',metrics),('CALIBRATION_AUDIT.jsonl',calib),('OPTIONAL_SOURCE_GAPS.jsonl',missing)]:L.dump_lines(root/name,data)
    assert len(photos)==len(objs)*52 and len(critique)==len(objs)*104 and len(pairs)==len(objs)*624
    for r in receipts:assert L.digest(root/r['path'])==r['sha256']
    q=L.check(root);L.rgb_tensor.cache_clear();L.mask_tensor.cache_clear();assert q==L.check(root)
    eligibility={'source_license':'CC-BY-4.0 per pinned author card','attribution_required':True,'perception':'source SAM/matting supervision',
        'critique':'specified numerical display-tone goal','outcome':'two observed image endpoints','online_action_ranking':False,'human_operator_utility':False,'full_cameracoach_training_ready':False}
    L.write_json(root/'ELIGIBILITY.json',eligibility)
    (root/'ATTRIBUTION.md').write_text('OpenIllumination: A Multi-Illumination Dataset for Inverse Rendering Evaluation on Real Objects. Isabella Liu, Linghao Chen, Ziyang Fu, Liwen Wu, Haian Jin, Zhong Li, Chin Ming Ryan Wong, Yi Xu, Ravi Ramamoorthi, Zexiang Xu and Hao Su. Source: https://huggingface.co/datasets/OpenIllumination/OpenIllumination/tree/'+L.REV+' . Author license declaration CC BY 4.0: https://creativecommons.org/licenses/by/4.0/ . Native bytes unchanged; modifications are 224-pixel resizing, new grouped split and computed numeric task labels. No endorsement implied.\n')
    (root/'README_RU.md').write_text('# Реальные объекты: завершение OpenIllumination\n\nЭто новые native-фотографии, маски и калибровка, не синтетические изображения. Отбор — 64 объекта авторского списка, 4 камеры, 13 световых состояний. Этот архив дополняет ранее успешные части 01 и 02 без дублей и изменения их разбиения.\n\nДанные обучают выделению объекта, проверке числовой цели по яркости и сравнению двух уже снятых кадров. Не являются оценкой художественной полезности, capture-time intent или физического действия пользователя. Маски SAM/matting автора не называются независимой человеческой разметкой. Выбранная точка вычислена из маски, которая не подаётся на вход.\n\nДля greenhead отсутствующие combined-маски отражены как optional missing, без подстановок. Это маски объекта с подставкой, не необходимые object-mask targets. Source val/test повторяются; используется отдельное разбиение по объектам.\n\nreal_lighting.batches(root, task="perception"/"critique"/"outcome", split="train") возвращает реальные NumPy X,Y,M.\n')
    rep=root/'reproduction';rep.mkdir();shutil.copyfile(L.__file__,rep/'real_lighting.py');shutil.copyfile(__file__,rep/Path(__file__).name)
    counts={'objects':len(objs),'views':len(objs)*4,'native_rgb':len(photos),'native_masks':sum(x['source_path'].endswith('.png') for x in receipts),
        'source_receipts':len(receipts),'native_bytes':sum(x['bytes'] for x in receipts),'upstream_sha_verified_files':sum(x['upstream_hash_verified'] for x in receipts),
        'perception_records':len(photos),'critique_records':len(critique),'outcome_task_records':len(pairs),'unique_observed_light_pairs':len(pairs)//2}
    qa={'schema':'cc20.real_lighting_qa.v2','label':label,'revision':L.REV,'objects_selected':objs,'selection_complete':True,'counts':counts,'consumer':q,
        'optional_missing_files':missing,'required_missing_files':[],'all_native_file_hashes_rechecked':True,'second_full_tensor_pass_identical':True,
        'existing_split_assignments_unchanged':True,'models_executed':0,'visual_human_review':False,'realworld_model_transfer_measured':False,
        'original_full_DoD':'NOT_COMPLETE','eligibility':eligibility}
    L.write_json(root/'QA.json',qa)
    proof=Path('proof');proof.mkdir(exist_ok=True);L.write_json(proof/'QA.json',qa)
    L.write_json(proof/'SOURCE_HASH_AUDIT.json',{'source':L.REPO,'revision':L.REV,'rows':[{'object':r['object_id'],'group':r['origin_group'],'split':r['split'],'sha256':r['provenance']['native_rgb_sha256']} for r in photos]})
    print('CC20_QA '+json.dumps(qa),flush=True);L.package(root,label)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--part',required=True);run(p.parse_args().part)
