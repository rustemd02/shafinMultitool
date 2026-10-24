"""Select only completed native-data runs and preserve their exact QA/catalog.
No raw media, owner private keys, model calls or new human judgements in this kit.
Unknown clinical/product/utility claims are never turned into successful gates.
"""
from __future__ import annotations
import hashlib,io,json,os,shutil,sys,urllib.request,urllib.parse,zipfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE));sys.path.insert(0,str(HERE.parent/'cc17'))
import restore_dataset as R
import real_dataset as D
from verify_real_consumers import regressions
BASE='https://api.github.com/repos/rustemd02/shafinMultitool'
SOURCES={'illumination':(40081889341,'cc20-illumination-real'),'holoassist':(40083452215,'cc20-holoassist-all-cues'),'objectron':(40085597803,'cc20-objectron-native-oriented')}
QA_RUN=40084574392
DIAGNOSTIC_RUN=40084762448
OUT=Path('cc20-verified-real-kit')

class StripAuthRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        out=super().redirect_request(req,fp,code,msg,headers,newurl)
        if out and urllib.parse.urlparse(newurl).hostname!='api.github.com':out.remove_header('Authorization')
        return out
OPENER=urllib.request.build_opener(StripAuthRedirect())

def get(path):
    req=urllib.request.Request(BASE+path,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
    with OPENER.open(req,timeout=180) as r:return r.read()

def dump(path,obj):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(obj,ensure_ascii=False,indent=2,allow_nan=False)+'\n')

def artifact(a):
    data=get(f'/actions/artifacts/{a["id"]}/zip');expected=a.get('digest','').removeprefix('sha256:')
    if len(data)!=a['size_in_bytes'] or not expected or hashlib.sha256(data).hexdigest()!=expected:raise ValueError('Artifact metadata/hash mismatch')
    z=zipfile.ZipFile(io.BytesIO(data))
    if z.testzip() is not None:raise ValueError('Artifact CRC mismatch')
    return data,z

def source(name,rid,label):
    run=json.loads(get(f'/actions/runs/{rid}'))
    if run['conclusion']!='success':raise ValueError('Source data run not successfully completed: '+name)
    jobs=json.loads(get(f'/actions/runs/{rid}/jobs?per_page=100'))['jobs'];qa=[];indices=[]
    for job in jobs:
        if job['conclusion']!='success':continue
        text=get(f'/actions/jobs/{job["id"]}/logs').decode('utf-8-sig')
        for line in text.splitlines():
            if ' CC20_QA ' in line:qa.append(json.loads(line.split(' CC20_QA ',1)[1]))
            if ' CC17_ARTIFACT_INDEX ' in line:
                v=json.loads(line.split(' CC17_ARTIFACT_INDEX ',1)[1])
                if v['label']==label:indices.append(v)
    if len(qa)!=1 or len(indices)!=1:raise ValueError('Native source proof not unique')
    index=indices[0];release=index['release'];arts=json.loads(get(f'/actions/runs/{rid}/artifacts?per_page=100'))['artifacts'];byid={a['id']:a for a in arts}
    ix=byid[index['index_artifact_id']];data,z=artifact(ix)
    values=[json.loads(z.read(n)) for n in z.namelist() if n.endswith('.json')]
    embedded=next((v['release'] for v in values if 'release' in v and 'artifacts' in v),None)
    if embedded!=release:raise ValueError('Published index differs from executed build receipt')
    for a in index['artifacts']:
        native=byid[a['id']]
        if native['expired'] or native['size_in_bytes']!=a['size'] or native['digest'].removeprefix('sha256:')!=a['digest']:raise ValueError('Part metadata mismatch')
    if release['archive_readback_mismatches']:raise ValueError('Source plaintext archive did not verify')
    dump(OUT/f'proof/{name}_BUILD_QA.json',qa[0]);dump(OUT/f'catalog/{name}_RELEASE.json',index)
    return {'run_id':rid,'head_sha':run['head_sha'],'label':label,'qa':qa[0],'release':release,'index_artifact_id':ix['id'],'index_sha256':hashlib.sha256(data).hexdigest(),'source_artifacts':index['artifacts']}

def native_reports(rid,directory):
    run=json.loads(get(f'/actions/runs/{rid}'))
    if run['conclusion']!='success':raise ValueError('Proof run failed')
    arts=json.loads(get(f'/actions/runs/{rid}/artifacts?per_page=100'))['artifacts'];values={}
    for a in arts:
        data,z=artifact(a)
        for n in z.namelist():
            if not n.endswith('.json'):continue
            rel=R.safe_relative(n);v=json.loads(z.read(n));dest=OUT/'proof'/directory/rel;dump(dest,v);values[rel.name]=v
    return values

def main():
    OUT.mkdir(exist_ok=False)
    sources={name:source(name,*spec) for name,spec in SOURCES.items()}
    reader=native_reports(QA_RUN,'portable_readers');diagnostics=native_reports(DIAGNOSTIC_RUN,'source_diagnostics')
    r=reader['REAL_CONSUMER_QA.json']
    assert r['native_illumination']['native_scenes_replayed']==1015
    assert r['native_illumination']['real_image_batches_compared']==25375 and r['native_illumination']['all_inputs_and_targets_array_equal']
    assert all(r['regressions']['checks'].values())
    light=sources['illumination']['qa'];holo=sources['holoassist']['qa'];obj=sources['objectron']['qa']
    assert light['accepted_scene_configurations']==1015 and light['failed_scenes']==0 and light['cross_split_exact_pixel_hashes']==0
    assert holo['native_quality_cues']==338 and holo['video_backed_records']+holo['rejected_events']==338 and holo['exact_frame_and_packet_checks']
    assert obj['accepted_videos']==36 and obj['failed_videos']==0 and obj['display_orientation_verified_videos']==36 and obj['independent_exact_pixel_checks']==108
    # Source archive preserves all X/Y proof hashes. Latest reader must match
    # the SHA used by the oriented source run, not an unchecked mutable alias.
    native=HERE/'native_reader.py';assert hashlib.sha256(native.read_bytes()).hexdigest()==obj['portable_reader_sha256']
    for p in [HERE/'real_dataset.py',native,HERE.parent/'cc17/restore_dataset.py',HERE/'restore_real_components.py']:
        shutil.copyfile(p,OUT/p.name);compile(p.read_text(),str(p),'exec')
    assert hashlib.sha256((HERE/'real_dataset.py').read_bytes()).hexdigest()==r['native_illumination']['reader_sha256']
    import tempfile
    with tempfile.TemporaryDirectory() as d:fixture=regressions(Path(d))
    dump(OUT/'proof/PACKAGED_READER_SELFTEST.json',fixture)
    catalog={'schema':'cc20.real_supervision_catalog.v1','components':sources,'model_execution_authorized':False,'full_cameracoach_training_ready':False,
      'superseded_not_for_training':['cc20-objectron-real','cc20-objectron-native-aligned','cc20-holoassist-capture-cues'],
      'preflight_not_an_independent_dataset':'cc20-source-preflight',
      'inherited_policy':'v19 selected3353 remains unchanged; new auxiliary rows are NOT added to policy-gold count'}
    dump(OUT/'REAL_COMPONENT_CATALOG.json',catalog)
    status={'schema':'cc20.actual_scope.v1','native_component_data_loading_ready':{'real_light_response':True,'human_command_imitation':True,'all_object_keypoints':True,'observed_camera_motion':True},
      'selected_components_complete_and_source_archive_verified':True,'native_sources_with_explicit_rights_text':3,'human_commands_are_new_camera_coach_evaluations':False,
      'all_original_266_DoD_complete':False,'model_calls':0,'new_independent_human_responses':0,'full_camera_coach_policy_training_ready':False,
      'unresolved_original_requirements':['native capture-time artistic goals paired with performed physical actions and independent outcomes','independent human utility assessment for CameraCoach','semantic synthetic diversity and real-world transfer evidence','current iPhone preprocessing/integration parity','complete fresh Google Drive plaintext restoration','full original per-row DoD re-audit'],
      'source_scope':{'illumination':'all 1015 scenes from pinned author manifest,25conditions each','holoassist':'all338 native quality-cue annotations accounted; only available valid episodes admitted','objectron':'bounded36-video nine-category component, not all Objectron'},
      'known_limits':['controlled light IDs are source-rig categories, not universal coordinates','HoloAssist head-mounted interaction is not a phone camera field study','source commands do not establish execution, success or usefulness','Objectron AR poses are estimates, not measured physical truth','frames from one source video or room are not independent scenes','participant/physical-object independence not established for real videos'],
      'delivery_verification':'Drive upload receipts are separate; no whole-Drive plaintext readback is claimed by this kit'}
    dump(OUT/'SCOPE_STATUS.json',status)
    (OUT/'requirements.txt').write_text('numpy==1.26.4\nPillow==11.3.0\nav==18.1.0\n')
    (OUT/'START_HERE_RU.md').write_text(f'''# CameraCoach v20 — реальные данные, а не новая версия синтетических сцен

## Что завершено в этой поставке

Три фактически полученных источника с исходными аннотациями, медиа, раздельными задачами и выполненными проверками:

- **MIT Multi-Illumination:** {light['native_jpgs']} native JPG, {light['native_material_maps']} карт материалов, {light['accepted_scene_configurations']} сцен, {light['buildings']} зданий и {light['rooms']} помещений. Полный manifest-срез mip4,375×250. Train/validation/test разделены по зданиям. Все реальные изображения повторно прочитаны переносимым загрузчиком; X/Y массивы совпали с исходным consumer. Данные CC BY 4.0, авторская атрибуция и текст условий сохранены.
- **HoloAssist:** {holo['video_backed_records']} реальных video-backed команд из {holo['native_quality_cues']} native-событий качества видео. {holo['known_text_target_records']} записей имеют текстовую цель с включённой маской; остальные не превращены в выдуманный текст. Сохранены оригинальные кодированные видеопакеты нужных эпизодов, а не перекодированная имитация; совпадение пакетов и наблюдаемых кадров проверено. {holo['rejected_events']} событий не допущены, причины сохранены в SOURCE_TRIALS. Данные CDLA-Permissive-2.0.
- **Objectron:** {obj['accepted_videos']} исходных MOV, {obj['native_frames']} кадров, {obj['native_keypoint_targets']} допустимых native keypoint targets; {obj['motion_batches_with_supervision']} пар с допустимой AR-разметкой движения. Все source clocks, соответствие поз, проекции и реальный поток массивов проверены. Для всех36 видео первый, средний и последний кадр после применения display matrix точно совпали с авторской конвенцией FFmpeg. Данные C-UDA-1.0.

Данные не объединяются в одну плоскую таблицу «правильных операторских решений». Световая реакция, имитация человеческой команды, геометрическое восприятие и проверка наблюдаемого движения имеют разные входы, targets и маски. Выбранная policy v19 (3353 записи) остаётся отдельной.

## Какие файлы использовать

`CC20_ILLUMINATION_000.zip`…`006.zip` и INDEX; `CC20_HOLOASSIST_000.zip`…`010.zip` и INDEX; все части `CC20_OBJECTRON_ORIENTED_*.zip` и INDEX. Их точный список, размер и SHA зафиксированы в REAL_COMPONENT_CATALOG.json. Файлы SUPERSEDED_NOT_FOR_TRAINING не использовать: это сохранённый след исправления ориентации, не дополнительные примеры.

## Восстановление без модели

Распакуйте этот комплект в приватной папке. ZIP-части данных оставьте целыми. Приватный ключ пользователя уже сохранён в v19 под именем PRIVATE_transport_key_DO_NOT_PUBLISH.pem. Не публиковать ключ, не вставлять его в GitHub или логи. В этом комплекте и публичных артефактах приватного ключа нет.

```sh
python -m pip install -r requirements.txt
python restore_real_components.py --parts-dir /private/v20 --list
python restore_real_components.py --parts-dir /private/v20 --key /private/PRIVATE_transport_key_DO_NOT_PUBLISH.pem --out /private/restored
```

При проверке сверяются не только имена: ожидаемый каталог, каждый chunk, ciphertext, plaintext SHA и полный payload manifest. Скрипт не запускает модель и не выполняет обучение. Реальное восстановление из Drive в текущей сессии НЕ засчитано: приватное runtime недоступно. При сборке источников полные tar-архивы прочитаны и проверены.

```python
from pathlib import Path
import real_dataset as real
import native_reader as native
light=Path('/private/restored/cc20-illumination-real')
holo=Path('/private/restored/cc20-holoassist-all-cues')
objects=Path('/private/restored/cc20-objectron-native-oriented')
X,Y,masks,metadata=next(real.illumination(light,split='train'))
X,Y,masks,metadata=next(real.holoassist(holo))
X,Y,masks=next(native.batches(objects,task='perception',split='train'))
X,Y,masks=next(native.batches(objects,task='motion',split='train'))
```

Для HoloAssist официальный split хранится в metadata: не смешивать validation с train. Послекадры хранятся отдельно и не входят в online observation. Native instruction — target, не input. Неизвестные execution/goal/human utility остаются null с выключенным loss. Для Objectron loader требует подтверждённую display-ориентацию и откажется читать старую неверную версию. Для illumination light IDs специфичны исходной установке; они не являются метрами смещения света.

## Что исправлено, а не замолчано

В Objectron обнаружены отсутствующие timestamp в FrameAnnotation: значение protobuf по умолчанию0 не было признано временем съёмки. Использован native ARFrame.timestamp после проверки frame ID, числа кадров и camera matrices. Затем обнаружен display rotation MOV; исправление прошло108 независимых пиксельных проверок. Невалидные проекции masked, а не объявлены человеческим ground truth. В HoloAssist не подставлялись похожие названия других участников/сессий вместо отсутствующих оригиналов.

## Граница готовности

Компоненты готовы для их объявленных задач чтения/подготовки обучения. Это НЕ выполнение всех исходных266 DoD и НЕ доказательство, что готовая CameraCoach даёт полезные советы. Новых независимых оценок CameraCoach нет, execution/outcome человеческих команд не выдуманы, модель и iPhone-runtime не запускались. Исходные требования не переименованы и не снижены; SCOPE_STATUS.json сохраняет непокрытые предикаты.
''')
    manifest=[{'path':str(p.relative_to(OUT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUT.rglob('*')) if p.is_file()]
    dump(OUT/'MANIFEST.json',{'files':manifest,'contains_media':False,'contains_private_key':False,'models_executed':0})
    print('CC20_VERIFIED_REAL_KIT '+json.dumps({'components':{k:v['qa'] for k,v in sources.items()},'files':len(manifest),'portable_reader_checks':r,'full_original_DoD_complete':False},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
