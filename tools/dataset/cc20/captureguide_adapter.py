"""CaptureGuide photographer-side adapter, evaluation/research only.
No synthetic human labels, no training split, no model inference.
Preserves original literal annotations; compares against the pinned author parser.
"""
from __future__ import annotations
import ast,collections,concurrent.futures,hashlib,io,json,os,shutil,sys
from pathlib import Path
import numpy as np
import requests
from PIL import Image,ImageOps
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'cc17'))
from acquire import write_json,digest
from release_pack import package
REPO='ShutterMuse/CaptureGuide-Bench';REV='bd7d513ce8be56796395dd51b8fef17f58ff192e';GITREV='18b62fa2f7885f71b7acb72885686ccb027ab355'

def get(url):
    r=requests.get(url,timeout=(20,180),headers={'User-Agent':'CameraCoach research dataset/20'});r.raise_for_status();return r

def jsonl(path,items):
    with path.open('w') as f:
        for row in items:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')

def author_functions(text,names,env):
    tree=ast.parse(text);nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names]
    if {n.name for n in nodes}!=set(names):raise ValueError('Pinned author function missing')
    exec(compile(ast.Module(body=nodes,type_ignores=[]),'pinned_author_data_functions','exec'),env)
    return env

def decision(obj):
    # Same documented rules as official load_annotation_data, not score thresholds.
    boxes=[[max(0.,min(1.,float(v))) for v in b['rect']] for b in sorted(obj.get('composition_boxes',[]),key=lambda b:int(b['id']))]
    origin=obj.get('origin',{});good=origin.get('好的原因','');bad=origin.get('差的原因','');kind=origin.get('返回原图类型','') or origin.get('返回构图类型','');secondary=origin.get('二次构图类型','')
    addfull='原图构图一般' in kind or '原图构图好' in kind or '原图构图好' in secondary or '原图构图好' in good
    if addfull:boxes.append([0.,0.,1.,1.])
    if not boxes and not ('原图特别差' in bad or kind=='原图构图差'):return None,boxes
    if not boxes:return 'reject',boxes
    if all(np.allclose(b,[0,0,1,1],atol=1e-9,rtol=0) for b in boxes):return 'keep',boxes
    return 'crop',boxes

def batches(root,batch_size=8,split='evaluation'):
    if split!='evaluation':raise ValueError('CaptureGuide benchmark is excluded from all training splits')
    root=Path(root);rows=[json.loads(l) for l in (root/'records.jsonl').read_text().splitlines()];maxb=max([len(r['targets']['acceptable_crops_xyxy']) for r in rows]+[1])
    for offset in range(0,len(rows),batch_size):
        block=rows[offset:offset+batch_size];images=[];dec=[];boxes=np.zeros((len(block),maxb,4),np.float32);mask=np.zeros((len(block),maxb),bool)
        for i,r in enumerate(block):
            obs=r['observations'];assert set(obs)=={'image','selected_subject','capture_time_intent','protected_style','constraints'}
            assert all(obs[k] is None for k in ['selected_subject','capture_time_intent','protected_style','constraints'])
            with Image.open(root/obs['image']) as im:
                im=im.convert('RGB');im=ImageOps.pad(im,(224,224),method=Image.Resampling.BILINEAR,color=(0,0,0));images.append(np.asarray(im,np.float32).transpose(2,0,1)/255.)
            target=r['targets'];dec.append(['keep','crop','reject'].index(target['native_decision']));n=len(target['acceptable_crops_xyxy']);boxes[i,:n]=np.asarray(target['acceptable_crops_xyxy'],np.float32).reshape(-1,4);mask[i,:n]=True
        X={'rgb_letterboxed':np.stack(images)};Y={'native_decision':np.asarray(dec,np.int64),'crops_normalized_to_original_display_image':boxes};M={'decision':np.ones(len(block),bool),'crops':mask,'physical_action':np.zeros(len(block),bool),'human_operator_utility':np.zeros(len(block),bool)}
        yield X,Y,M

def run():
    root=Path('cc20-captureguide-evaluation');root.mkdir();native=root/'native';native.mkdir();tmp=Path('source_originals');tmp.mkdir();tree=[];url=f'https://huggingface.co/api/datasets/{REPO}/tree/{REV}?recursive=true&limit=1000';base=f'https://huggingface.co/datasets/{REPO}/resolve/{REV}/'
    while url:
        r=get(url);tree.extend(r.json());url=r.links.get('next',{}).get('url')
    pmeta='photographer-side/composition_benchmark/meta_new.json';meta_bytes=get(base+pmeta).content;(native/'meta_new.json').write_bytes(meta_bytes);meta=json.loads(meta_bytes)
    (native/'README_SOURCE.md').write_bytes(get(base+'README.md').content)
    files=[x for x in tree if x['type']=='file' and x['path'].startswith('photographer-side/') and Path(x['path']).suffix.lower() in ['.jpg','.png','.jpeg','.webp']]
    receipts={}
    def load(v):
        b=get(base+requests.utils.quote(v['path'],safe='/')).content;assert len(b)==v['size'];sha=hashlib.sha256(b).hexdigest()
        if v.get('lfs',{}).get('oid'):assert sha==v['lfs']['oid']
        source=tmp/Path(v['path']).name;source.write_bytes(b)
        with Image.open(io.BytesIO(b)) as im:
            orientation=im.getexif().get(274,1);original_size=im.size;display=ImageOps.exif_transpose(im).convert('RGB');display_size=display.size
            display.thumbnail((768,768),Image.Resampling.LANCZOS);out=root/'media'/(sha+'.jpg');out.parent.mkdir(exist_ok=True);display.save(out,quality=94,subsampling=0)
        return Path(v['path']).stem,{'native_path':v['path'],'sha256':sha,'bytes':len(b),'raw_size':original_size,'display_size':display_size,'derivative_size':display.size,'exif_orientation':orientation,'derivative':str(out.relative_to(root)),'derivative_sha256':digest(out),'source_local':str(source)}
    for key,value in concurrent.futures.ThreadPoolExecutor(max_workers=6).map(load,files):
        if key in receipts:raise ValueError('Ambiguous native filename')
        receipts[key]=value
    sourceurl=f'https://raw.githubusercontent.com/lijayuTnT/ShutterMuse/{GITREV}/';utils=get(sourceurl+'evaluation/photographer-side/utils.py').text;ev=get(sourceurl+'evaluation/photographer-side/evaluate_benchmark.py').text
    (native/'author_utils.py').write_text(utils);(native/'author_evaluation.py').write_text(ev)
    env={'json':json,'ast':ast,'os':os,'Image':Image,'ImageOps':ImageOps,'tqdm':lambda x,**kw:x};author_functions(utils,['clip_norm','load_annotation_data'],env)
    original_items=env['load_annotation_data'](str(native/'meta_new.json'),str(tmp));official={r['id']:r for r in original_items}
    author_functions(ev,['_is_full_image_bbox','_has_keep_gt','_gt_decision_type'],env)
    records=[];quarantine=[];counter=collections.Counter();bbox_count=0;clipped=0;invalid=0;author_agreement=0
    for id,raw in meta.items():
        obj=ast.literal_eval(raw);label,crops=decision(obj);receipt=receipts.get(id)
        if receipt is None or label is None:
            quarantine.append({'id':id,'reason':'missing exact media' if receipt is None else 'excluded by native author semantic rules','native':obj});continue
        if id not in official:raise AssertionError('Local parser accepts row absent from author parser')
        oi=official[id];w,h=receipt['display_size'];native_label=env['_gt_decision_type'](oi['is_reject_case'],oi['gt_bboxes'],w,h)
        assert label==native_label
        expected=np.asarray(oi['gt_bboxes'],float).reshape(-1,4)/[w,h,w,h];assert expected.shape==(len(crops),4) and np.allclose(expected,np.asarray(crops,float).reshape(-1,4),atol=1e-9,rtol=0);author_agreement+=1
        valid=[]
        for c in crops:
            if not (0<=c[0]<c[2]<=1 and 0<=c[1]<c[3]<=1):invalid+=1
            else:valid.append(c)
        if len(valid)!=len(crops):quarantine.append({'id':id,'reason':'invalid native rectangle geometry','native':obj});continue
        clipped+=sum(any(not 0<=float(v)<=1 for v in b['rect']) for b in obj.get('composition_boxes',[]));counter[label]+=1;bbox_count+=len(crops)
        records.append({'record_id':'captureguide:'+id,'origin_group':'native-image-sha256:'+receipt['sha256'],'split':'evaluation','task_type':'published_digital_framing_preference',
          'observations':{'image':receipt['derivative'],'selected_subject':None,'capture_time_intent':None,'protected_style':None,'constraints':None},
          'targets':{'native_decision':label,'acceptable_crops_xyxy':crops,'native_critique':obj.get('origin'),'native_crop_annotations':obj.get('composition_boxes'),'native_score':obj.get('score'),'physical_action':None,'action_performed':None,'human_operator_utility':None},
          'loss_masks':{'native_decision':True,'acceptable_crops':bool(crops),'physical_action':False,'action_performed':False,'human_operator_utility':False},
          'provenance':{'repo':REPO,'revision':REV,'native_image':receipt,'native_annotation_id':id,'native_annotation_sha256':hashlib.sha256(raw.encode()).hexdigest(),'annotation_authority':'published benchmark expert annotations with source-described language normalization; not new independent raters','license_scope':'research use only; training leakage excluded','commercial_training_eligible':False}})
    jsonl(root/'records.jsonl',records);jsonl(root/'quarantine.jsonl',quarantine);write_json(root/'SOURCE_RECEIPTS.json',receipts)
    h=hashlib.sha256();count=0;bn=0
    for X,Y,M in batches(root):
        bn+=1;count+=len(X['rgb_letterboxed'])
        for ds in [X,Y,M]:
            for k,a in sorted(ds.items()):assert np.isfinite(a).all();h.update(k.encode());h.update(str(a.shape).encode());h.update(a.tobytes())
    assert count==len(records) and len(records)+len(quarantine)==len(meta)
    try:next(batches(root,split='train'));raise AssertionError('Train leakage accepted')
    except ValueError:pass
    report={'records_source':len(meta),'images_downloaded_and_decoded':len(receipts),'records_ready':len(records),'quarantined_records':len(quarantine),'native_decision_counts':dict(counter),'acceptable_crop_boxes':bbox_count,'clipped_native_box_count_author_rule':clipped,'invalid_native_boxes':invalid,'author_parser_agreement_records':author_agreement,'actual_numpy_batches':bn,'actual_tensor_stream_sha256':h.hexdigest(),'train_records':0,'train_loader_rejected':True,'models_called':0,'new_human_responses':0,'physical_action_labels':0,'source_revision':REV,'full_cameracoach_training_ready':False}
    write_json(root/'QA.json',report);code=root/'reproduction';code.mkdir();shutil.copyfile(__file__,code/'captureguide_adapter.py')
    (root/'README_RU.md').write_text('# CaptureGuide: опубликованный оценочный компонент\nПолный photographer-side pinned benchmark. Исходники сохранены отдельным native-пакетом. Здесь точный join, исходные комментарии и кропы, EXIF-исправленные производные изображения и исполняемый data-only reader.\n\nЗадача: авторская оценка keep/crop/reject для цифрового кадрирования. Это НЕ физическое операторское действие, не заранее заявленный intent и не оценка полезности CameraCoach. Запрещён train split; research-only scope.\n\nОригинальные координаты относятся к EXIF-corrected display image. Изображение для batch letterboxed, поэтому координаты нельзя интерпретировать как координаты padded tensor без обратного преобразования.\n')
    print('CC20_CAPTUREGUIDE_ADAPTER_QA '+json.dumps(report),flush=True);package(root,'cc20-captureguide-evaluation')
if __name__=='__main__':run()
