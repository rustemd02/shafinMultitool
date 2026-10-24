"""Real controlled-light observations, not invented cinematography preferences.
Native 375x250 JPG mip4 archives and indexed material maps. All scene identities
come from the author manifest; every available observation is decoded and hashed.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,io,json,re,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
from real_common import fetch,repository_files,jsonl,safe_member,image_tensor,finish,write_json,digest
REV='a85aa9253065ff836ea97ba1a04b14259a06b3e0'
BASE='https://data.csail.mit.edu/multilum'
ROOT=Path('cc20-illumination-real');ROOT.mkdir(exist_ok=True)

def split(scene):
    return 'test' if scene['building']=='everett' else 'validation' if scene['building']=='kingston' else 'train'

def photometry(rgb):
    lum=(rgb.astype(np.float32)/255.)@np.array([.2126,.7152,.0722],np.float32)
    h,w=lum.shape;roi=lum[h//4:3*h//4,w//4:3*w//4]
    return [float(lum.mean()),float(np.median(lum)),float((rgb.max(axis=-1)>=254).mean()),float(roi.mean())]

def load_pairs(root,scene_record):
    """Separate condition input and observed-output target; no preference label.
    Categorical light IDs are valid only for the source capture rig.
    """
    with zipfile.ZipFile(root/scene_record['archive']) as z:
        with Image.open(io.BytesIO(z.read(scene_record['images'][0]['member']))) as im:before=image_tensor(im)
        for row in scene_record['images']:
            with Image.open(io.BytesIO(z.read(row['member']))) as im:
                rgb=np.asarray(im.convert('RGB'));after=image_tensor(im)
            X={'before_rgb':before[None], 'source_light_index':np.array([0],np.int64),'target_light_index':np.array([row['light_index']],np.int64)}
            Y={'observed_after_rgb':after[None],'display_photometry':np.asarray([photometry(rgb)],np.float32)}
            M={'observed_after_rgb':np.ones(1,bool),'display_photometry':np.ones((1,4),bool),'historical_intent':np.zeros(1,bool),'human_preference':np.zeros(1,bool),'operator_utility':np.zeros(1,bool)}
            yield X,Y,M

def acquire(scene):
    name=scene['name'];out={**scene,'origin_group':'multilum-building:'+scene['building'],'room_group':scene['building']+'/'+scene['room'],'split':split(scene),'status':'failed'}
    try:
        p=ROOT/'native'/f'{name}_mip4_jpg.zip';rec=fetch(f'{BASE}/{name}/{name}_mip4_jpg.zip',p,30_000_000)
        out['archive']=str(p.relative_to(ROOT));out['source_archive']=rec;images=[]
        with zipfile.ZipFile(p) as z:
            assert z.testzip() is None
            for member in z.namelist():
                safe_member(member)
                m=re.fullmatch(r'dir_(\d+)_mip4\.jpg',Path(member).name)
                if not m:continue
                b=z.read(member)
                with Image.open(io.BytesIO(b)) as im:
                    im.load();assert im.size==(375,250),(name,im.size)
                    rgb=np.asarray(im.convert('RGB'))
                images.append({'member':member,'light_index':int(m.group(1)),'bytes':len(b),'native_sha256':hashlib.sha256(b).hexdigest(),'pixel_sha256':hashlib.sha256(rgb.tobytes()).hexdigest(),'width':375,'height':250})
        images.sort(key=lambda x:x['light_index']);assert [x['light_index'] for x in images]==list(range(25))
        out['images']=images;out['status']='accepted';out['material_mask']=None
        mp=ROOT/'native'/f'{name}_materials_mip4.png'
        try:
            mr=fetch(f'{BASE}/{name}/materials_mip4.png',mp,3_000_000)
            with Image.open(mp) as im:
                im.load();assert im.mode=='P' and im.size==(375,250)
                mask=np.asarray(im);ids=np.unique(mask).tolist()
            out['material_mask']={'path':str(mp.relative_to(ROOT)),'receipt':mr,'native_index_values':ids,'semantic_use':'native material indices only; not instance or selected-subject masks'}
        except Exception as e:out['material_mask_error']=type(e).__name__+': '+str(e)[:180]
        # Execute actual image-dependent data consumer, not only path checks.
        h=hashlib.sha256();n=0
        for X,Y,M in load_pairs(ROOT,out):
            assert X['before_rgb'].shape==Y['observed_after_rgb'].shape==(1,3,224,224)
            for group in [X,Y,M]:
                for k,v in sorted(group.items()):assert np.isfinite(v).all();h.update(k.encode());h.update(str(v.shape).encode());h.update(v.tobytes())
            n+=1
        out['consumer_rows']=n;out['tensor_stream_sha256']=h.hexdigest()
    except Exception as e:out['error']=type(e).__name__+': '+str(e)[:250]
    return out

if __name__=='__main__':
    repository_files(ROOT,'lmurmann/multi_illumination',REV,['scenes.json','multilum.py','README.md','LICENSE'])
    page=ROOT/'rights/project.html';fetch('https://projects.csail.mit.edu/illumination/',page,1_000_000)
    assert 'creativecommons.org/licenses/by/4.0/' in page.read_text()
    fetch('https://creativecommons.org/licenses/by/4.0/legalcode.txt',ROOT/'rights/CC-BY-4.0.txt',300_000)
    scenes=json.loads((ROOT/'source_repository/scenes.json').read_text());assert len({x['name'] for x in scenes})==len(scenes)
    write_json(ROOT/'PREDECLARED_SELECTION.json',{'all_native_scenes':len(scenes),'native_mip':4,'test_building':'everett','validation_building':'kingston','selection_depends_on_targets':False,'historical_intent':None})
    # Semantic/file preflight before bulk. Any failed first-scene schema stops expansion.
    first=acquire(scenes[0]);assert first['status']=='accepted',first
    rows=[first]
    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        for r in pool.map(acquire,scenes[1:]):
            rows.append(r)
            if len(rows)%100==0:print('CC20_LIGHT_PROGRESS '+str(len(rows)),flush=True)
    accepted=[r for r in rows if r['status']=='accepted'];failed=[r for r in rows if r['status']!='accepted']
    jsonl(ROOT/'scene_records.jsonl',accepted);jsonl(ROOT/'source_trials.jsonl',rows)
    groups=collections.defaultdict(set);pixels=collections.defaultdict(set)
    for r in accepted:
        groups[r['split']].add(r['origin_group'])
        for im in r['images']:pixels[im['pixel_sha256']].add(r['split'])
    overlaps=sum(len(groups[a]&groups[b]) for a,b in [('train','validation'),('train','test'),('validation','test')]);assert overlaps==0
    duplicates=[h for h,v in pixels.items() if len(v)>1]
    write_json(ROOT/'EXACT_PIXEL_OVERLAPS.json',duplicates)
    q={'task':'real_controlled_lighting_response','native_manifest_scenes':len(scenes),'accepted_scene_configurations':len(accepted),'failed_scenes':len(failed),
       'native_jpgs':sum(len(r['images']) for r in accepted),'native_material_maps':sum(r['material_mask'] is not None for r in accepted),
       'real_pixel_consumer_rows':sum(r['consumer_rows'] for r in accepted),'buildings':len({r['building'] for r in accepted}),'rooms':len({r['room_group'] for r in accepted}),
       'scene_splits':dict(collections.Counter(r['split'] for r in accepted)),'building_groups':{k:sorted(v) for k,v in groups.items()},'cross_split_buildings':0,'cross_split_exact_pixel_hashes':len(duplicates),
       'all_native_scenes_acquired':not failed,'source_license':'CC-BY-4.0, data attribution preserved; SDK MIT is separate','model_calls':0,'native_capture_time_intent_records':0,'human_utility_labels':0,
       'policy_training_eligible':False,'component_use':'appearance response and material/illumination perception only','unmeasured':['perceptual near duplicates','human preference','camera/light trajectory feasibility','iPhone transfer'],
       'training_scope_clear':not duplicates,'preprocessing':'EXIF transpose, RGB independent XY resize 224 bilinear; not measured Apple parity'}
    (ROOT/'DATASET_CARD_RU.md').write_text('# Реальные световые серии MIT\n\nПолучены исходные JPG-архивы авторского mip4 (375×250), не генерированные картинки. Каждая сцена имеет 25 условий света. scene_records.jsonl описывает изображения внутри ZIP; load_pairs выполняет чтение и формирует X/Y/masks.\n\nЗадача — предсказать наблюдаемое изменение изображения при переключении категории света исходной установки. Номера света не являются универсальными физическими координатами и не означают предпочтение. Нет исторического intent, человеческой полезности или выбранного пользователем субъекта. Центральная область в photometry — фиксированная вычислительная область, не детекция объекта.\n\nTrain/val/test разделены по зданиям; все комнаты и варианты одного здания вместе. Исходный тест everett сохранён. Число кадров не равно числу независимых помещений. Данные CC BY 4.0: Lukas Murmann, Michael Gharbi, Miika Aittala, Fredo Durand, ICCV 2019, A Multi-Illumination Dataset of Indoor Object Appearance. URL и лицензия сохранены.\n')
    finish(ROOT,'cc20-illumination-real',q)
