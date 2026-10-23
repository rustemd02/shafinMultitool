"""Build a code/manifest/proof-only handoff; no plaintext media or private keys.
The resulting catalog names immutable ciphertext artifacts. Delivery and Drive
readback are explicitly separate from these source-build and replay receipts.
"""
from __future__ import annotations
import hashlib,io,json,os,shutil,subprocess,sys,tarfile,tempfile,urllib.request,urllib.parse,zipfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'cc17'))
import restore_dataset as R
API='https://api.github.com/repos/rustemd02/shafinMultitool'
INDEXES=[(f'cc18-final-{i:02d}',aid) for i,aid in enumerate([12440418880,12440468812,12442007649,12440789282,12441006488,12442025700,12442175706,12441096895])]+[
 ('cc19-policy-core-joint-verified',12466361889),('acam-available-test-v18',12438533006),('cc19-acam-shotbench-native-supplement',12465381558)]
PROOF=12466900902
SWIFT=12493309039
class Redirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        r=super().redirect_request(req,fp,code,msg,headers,newurl)
        if r and urllib.parse.urlparse(newurl).hostname!='api.github.com':r.remove_header('Authorization')
        return r
OPENER=urllib.request.build_opener(Redirect())
def get(path):
    req=urllib.request.Request(API+path,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
    with OPENER.open(req,timeout=90) as r:return r.read()
def dump(p,obj):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
def artifact(aid):
    meta=json.loads(get(f'/actions/artifacts/{aid}'));data=get(f'/actions/artifacts/{aid}/zip')
    assert len(data)==meta['size_in_bytes']
    h=hashlib.sha256(data).hexdigest()
    assert meta['digest']=='sha256:'+h
    z=zipfile.ZipFile(io.BytesIO(data));assert z.testzip() is None
    return meta,data,z

def fixture_test():
    checks=[]
    with tempfile.TemporaryDirectory() as td:
        p=Path(td);payload=p/'payload';payload.mkdir();content=b'CODE TEST FIXTURE ONLY. NOT A DATASET EXAMPLE.\n';(payload/'fixture.txt').write_bytes(content)
        entry={'path':'fixture.txt','size':len(content),'sha256':hashlib.sha256(content).hexdigest()}
        dump(payload/'PAYLOAD_MANIFEST.json',{'label':'transport-fixture','files':[entry]})
        plain=p/'fixture.tar.gz'
        with tarfile.open(plain,'w:gz') as t:
            for f in sorted(payload.iterdir()):t.add(f,arcname=f.name,recursive=False)
        key=p/'ephemeral.pem';cert=p/'ephemeral.crt';cipher=p/'fixture.cms'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=CameraCoach-Transport-Fixture'],check=True,capture_output=True)
        subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',str(plain),'-out',str(cipher),'-outform','DER',str(cert)],check=True,capture_output=True)
        chunks=[cipher.read_bytes()[i:i+256] for i in range(0,cipher.stat().st_size,256)]
        release={'label':'transport-fixture','plaintext_name':plain.name,'plaintext_bytes':plain.stat().st_size,'plaintext_sha256':R.sha(plain),'encrypted_bytes':cipher.stat().st_size,'encrypted_sha256':R.sha(cipher),
                 'parts':[{'name':f'transport-fixture.p{i:03d}','bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()} for i,b in enumerate(chunks)],'payload_files_verified':1,'payload_bytes':len(content),'archive_readback_mismatches':[]}
        folder=p/'parts';folder.mkdir()
        for i,b in enumerate(chunks):
            with zipfile.ZipFile(folder/f'part{i}.zip','w') as z:z.writestr('RELEASE.json',json.dumps(release));z.writestr(release['parts'][i]['name'],b)
        item=R.discover(folder)['transport-fixture'];receipt=R.restore_one(item,key,p/'out');assert receipt['verified_files']==1;checks.append('complete_CMS_and_payload_restore')
        try:R.restore_one(item,key,p/'out');raise AssertionError('Overwrite accepted')
        except FileExistsError:checks.append('overwrite_rejected')
        incomplete={'release':release,'parts':dict(item['parts'])};incomplete['parts'].pop(release['parts'][0]['name'])
        try:R.restore_one(incomplete,key,p/'missing');raise AssertionError('Missing part accepted')
        except ValueError:checks.append('missing_part_rejected')
        with zipfile.ZipFile(folder/'part0.zip','w') as z:
            z.writestr('RELEASE.json',json.dumps(release));changed=bytearray(chunks[0]);changed[8]^=1;z.writestr(release['parts'][0]['name'],changed)
        try:R.restore_one(R.discover(folder)['transport-fixture'],key,p/'tampered');raise AssertionError('Tampered part accepted')
        except ValueError:checks.append('tampered_part_rejected')
        for path in ['../outside','/absolute','x/../../outside','C:\\outside']:
            try:R.safe_relative(path);raise AssertionError('Unsafe path accepted')
            except ValueError:pass
        checks.append('unsafe_archive_paths_rejected')
    sys.path.insert(0,str(HERE));import prepare_cc19 as P
    assert P.selected_labels('policy')==[P.CORE] and P.CORE not in P.selected_labels('synthetic-full')
    checks.append('core_and_full_policy_not_double_counted')
    return {'fixture_only':True,'checks_passed':checks,'dataset_examples_created':0,'owner_key_used':False,'actual_Drive_payload_restore':False}

def notebook():
    cells=[]
    def md(t):cells.append({'cell_type':'markdown','metadata':{},'source':t.splitlines(True)})
    def code(t):cells.append({'cell_type':'code','metadata':{},'execution_count':None,'outputs':[],'source':t.splitlines(True)})
    md('# CameraCoach v19: восстановление выбранного компонента\n\nПриватный Colab. Не публикуйте ключ, notebook outputs или исходные медиа. По умолчанию загружается только компактный policy-корпус; полный корпус содержит те же policy-ID и не должен смешиваться с ним. Модель и обучение не запускаются.\n')
    code("%pip -q install 'numpy==1.26.4' 'Pillow==11.3.0'\nfrom google.colab import drive\ndrive.mount('/content/drive')\n")
    code("from pathlib import Path\nimport zipfile, subprocess, sys\nbase=Path('/content/drive/MyDrive')\nv19=list(base.rglob('CameraCoach_v19_DATASET_DELIVERY_20261023'))\nv17=list(base.rglob('CameraCoach_v17_DATA_ACQUISITION_20261022'))\nassert len(v19)==1 and len(v17)==1, 'Укажите точные папки вручную; неоднозначное совпадение запрещено.'\nPARTS=v19[0]; LEGACY=v17[0]\nKEY=PARTS/'PRIVATE_transport_key_DO_NOT_PUBLISH.pem'\nif not KEY.is_file(): KEY=LEGACY/'PRIVATE_transport_key_DO_NOT_PUBLISH.pem'\nassert KEY.is_file(), 'Нет приватного ключа этой поставки'\nTOOLS=Path('/content/cc19_tools');TOOLS.mkdir(exist_ok=True)\nwith zipfile.ZipFile(PARTS/'CC19_TRAINING_HANDOFF.zip') as z:\n    for name in ['restore_dataset.py','cc18_dataset.py','prepare_cc19.py','DATASET_CATALOG.json']:\n        (TOOLS/name).write_bytes(z.read(name))\nOUT=Path('/content/cc19_restored')\n")
    code("cmd=[sys.executable,str(TOOLS/'prepare_cc19.py'),'--parts-dir',str(PARTS),'--parts-dir',str(LEGACY),'--component','policy','--catalog',str(TOOLS/'DATASET_CATALOG.json')]\nsubprocess.run(cmd+['--list'],check=True)\n")
    code("subprocess.run(cmd+['--key',str(KEY),'--out',str(OUT)],check=True)\nprint('Созданы фактические квитанции восстановления и чтения данных. Модель не запускалась.')\n")
    md('## Другие компоненты\n\nДля dense geometry и всех послекадров замените `--component policy` на `--component synthetic-full`. Для ACaM выберите `acam-evaluation`: подготовится отдельный evaluation index с сохранением native answers и исходной карантинной истории. Ни один ACaM record не входит в обучение. Не запускайте старый consumer рекурсивно по папке с обеими policy-репрезентациями.\n\nЭтот notebook не имеет сохранённых результатов запуска. До фактического выполнения он не является доказательством readback из Drive. Общая CameraCoach policy требует независимых реальных оценок, проверки переноса и отдельного разрешения model smoke.\n')
    return {'cells':cells,'metadata':{'kernelspec':{'display_name':'Python 3','name':'python3','language':'python'}},'nbformat':4,'nbformat_minor':5}

def main():
    out=Path('cc19_handoff');out.mkdir(exist_ok=True);components=[];index_dir=out/'source_indexes';index_dir.mkdir(exist_ok=True)
    for label,aid in INDEXES:
        meta,data,z=artifact(aid);release=json.loads(z.read('RELEASE.json'));assert release['label']==label
        (index_dir/(label+'.zip')).write_bytes(data)
        components.append({'release':release,'source_index_artifact_id':aid,'source_index_zip_sha256':hashlib.sha256(data).hexdigest(),
             'role':'physical_action_policy_core' if label== 'cc19-policy-core-joint-verified' else 'synthetic_full_counterfactuals' if label.startswith('cc18-final') else 'evaluation_only_noncommercial',
             'Drive_upload_or_readback_checked_by_this_builder':False})
    proof_meta,proof_bytes,z=artifact(PROOF);proof=json.loads(z.read('JOINT_AUDIT.json'));dump(out/'proof/JOINT_AUDIT.json',proof)
    assert proof['all_eight_replays_restored'] is True and proof['original_drive_bytes_restored'] is False
    assert proof['scene_configurations']==511 and proof['joint_consumer']['counts']['policy_rows']==3577
    assert proof['joint_consumer']==proof['core_consumer']
    _,_,z=artifact(SWIFT);swift=json.loads(z.read('CONTRACT_QA.json'));dump(out/'proof/SWIFT_CONTRACT_QA.json',swift)
    assert swift['valid_fixture_cases']==14 and swift['invalid_cases_rejected']==11
    for name in ['CameraActionInputsV1.swift','check_swift_contract.py']:(out/name).write_bytes(z.read(name))
    dump(out/'DATASET_CATALOG.json',{'schema':'cc19.selected_release_catalog.v1','components':components,
         'model_execution_authorized':False,'full_cameracoach_training_ready':False,
         'selection_rule':'compact policy core OR eight full shards; do not duplicate their policy examples',
         'inheritance':'ET, Rapidata, earlier real-source corpora and original 266 DoD remain in their versioned private checkpoints; not relabeled as real operator utility'})
    for name in ['restore_dataset.py','cc18_dataset.py']:shutil.copyfile(HERE.parent/'cc17'/name,out/name)
    shutil.copyfile(HERE/'prepare_cc19.py',out/'prepare_cc19.py')
    dump(out/'CC19_RESTORE_SELECTED.ipynb',notebook());fixture=fixture_test();dump(out/'proof/HANDOFF_SELFTEST.json',fixture)
    joint=proof['joint_consumer'];near=joint.get('dhash_review_candidates',[])
    gates={'schema':'cc19.gate_overlay.v1','does_not_replace_original_266_DoD':True,
      'complete_original_DoD':'BLOCKED','data_component':'synthetic measurable-action experiment, not complete CameraCoach policy',
      'actual_full_replay_and_batches':'PASS','numeric_Swift_Python_contract':'PASS',
      'original_Drive_plaintext_restore':'NOT_EXECUTED','model_smoke':'NOT_AUTHORIZED_NOT_EXECUTED',
      'human_operator_utility':'NO_NEW_RESPONSES','real_world_transfer':'NOT_MEASURED',
      'current_app_image_preprocessing_parity':'NOT_MEASURED','synthetic_heldout_secrecy':'DEVELOPMENT_EXPOSED_NUMERICAL_FAILURES',
      'near_duplicate_screening_candidates':len(near),'near_duplicate_semantic_adjudication':'NOT_COMPLETED' if near else 'NO_CANDIDATES_AT_FIXED_SCREENING_THRESHOLD',
      'commercial_rights':'own procedural core only; third-party datasets retain their per-source restrictions',
      'TRAINING_READY':False}
    dump(out/'GATE_STATUS.json',gates)
    (out/'START_HERE_RU.md').write_text('''# CameraCoach v19 — собранные данные и запуск загрузчика

## Что использовать

Для первого ограниченного эксперимента выбора физических действий берите `CC19_POLICY_CORE_000.zip`, `CC19_POLICY_CORE_001.zip`, соответствующий index и приватный ключ этой поставки. Это полный компактный corpus: 511 принятых конфигураций, 3577 заданий, 31 различимый кандидат действия, три предшествующих кадра. Из одной сцены происходят несколько целей и послекадров; это не независимые съёмки.

Все 8 полных партий `CC18_SYN_00_000.zip` ... `CC18_SYN_07_004.zip` нужны для послекадров, dense geometry и отдельной проверки результата. Они содержат те же policy-ID, что компактный core. Нельзя объединять обе репрезентации в обучение как новые примеры.

ET и Rapidata остаются отдельными вспомогательными задачами с прежними ограничениями. ACaM и дополнение ShotBench — evaluation-only. Публичные test answers никогда не превращаются в training data.

## Команды в приватном облаке

Python 3.10+, OpenSSL, NumPy 1.26.4, Pillow 11.3.0. Blender для загрузки не нужен. Распакуйте только этот handoff ZIP в отдельную папку. Внешние data ZIP оставьте целыми.

```sh
python prepare_cc19.py --parts-dir /private/v19 --parts-dir /private/v17 --component policy --list
python prepare_cc19.py --parts-dir /private/v19 --parts-dir /private/v17 --component policy --key /private/v17/PRIVATE_transport_key_DO_NOT_PUBLISH.pem --out /private/restored
```

`DATASET_CATALOG.json` должен лежать рядом со скриптом; каталог фиксирует доверенные release manifests. Для полного исходного synthetic corpus используйте `--component synthetic-full`. Для отдельного объединённого ACaM index — `--component acam-evaluation`.

Восстановитель проверяет SHA каждой части, всего CMS, расшифрованного tar и каждого payload-файла. Ошибочные, неполные или подменённые части отвергаются. При повторном запуске уже восстановленные файлы проверяются заново, не перезаписываются молча. Consumer обрабатывает только выбранную policy-репрезентацию и создаёт реальные X/Y/masks.

## Подтверждено исполнением

`proof/JOINT_AUDIT.json`: все 8 партий заново воспроизведены фиксированным генератором, восстановлены в приватном cloud job и совместно прочитаны. Это реальное исполнение, но НЕ восстановление первоначальных байтов Google Drive. Компактный corpus дал тот же результат consumer.

`proof/SWIFT_CONTRACT_QA.json`: настоящий Swift-код скомпилирован на облачном macOS; 14 корректных numeric fixtures совпали с действующим Python consumer, 11 некорректных inputs отвергнуты. Проверена независимость X от targets. Это не image/Metal parity и не запуск iPhone-приложения.

`proof/HANDOFF_SELFTEST.json`: реально выполнены защитные тесты восстановления на явно искусственном транспортном fixture. Они не засчитываются как новые примеры датасета или полный Drive readback.

## Какое обучение эти записи поддерживают

Ограниченная задача: текущие/прошлые RGB, выбранная точка, числовая цель, ограничения оборудования и параметризованные кандидаты → ранжирование/keep/ask/abstain. Правильность относится к размеру проекции, видимости, геометрическому столкновению и измеренной яркости пикселей. Это не художественный вкус, читаемость лица/текста или человеческая полезность.

Только split `train` участвует в оптимизации. Validation и test отделены по topology groups. Публичные/ранее просмотренные тесты не следует называть неизвестными модели или исследователю. Перечень dHash-screening кандидатов оставлен в аудите; без их независимого разрешения полная независимость не заявляется.

Ни model smoke, ни forward/backward, ни обучение здесь не запускались. Разрешение на модельный эксперимент — отдельное действие владельца, не автоматический эффект наличия архива.

## Стык с приложением

`CameraActionInputsV1.swift` реализует числовую часть отдельного ranker-контракта. Девять признаков SETCompositionNet v2 описывают художественный стиль; они не заменяют цель detail/context/expose/conceal. Не записывать вместо неизвестной цели придуманную метку. Pixel input pipeline, EXIF/orientation, зеркальность и Core ML parity ещё требуют реального подтверждения.

## Что не закрыто

Общий `TRAINING_READY=false`: нет независимых ответов о полезности CameraCoach, доказанного переноса на реальные iPhone/novice сцены, runtime-сравнения с актуальным MVP и разрешённого model smoke. Чистое восстановление исходных Drive bytes в текущем приватном runtime не выполнено. Данные с неподтверждёнными коммерческими правами не входят в коммерческий policy train pool. Полные первоначальные DoD не переопределяются этим документом; GATE_STATUS.json — только наложение статуса новой поставки.

Это завершённый материальный компонент для ограниченного экспериментального обучения после разрешения, но не утверждение, что весь перечень возможностей CameraCoach уже обеспечен.
''',encoding='utf-8')
    files=[{'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':R.sha(p)} for p in sorted(out.rglob('*')) if p.is_file()]
    dump(out/'HANDOFF_MANIFEST.json',{'schema':'cc19.handoff_manifest.v1','files':files,'contains_private_key':False,'contains_plaintext_dataset_media':False})
    print('CC19_HANDOFF_SUMMARY '+json.dumps({'catalog_components':len(components),'original_full_shards':8,'core_rows':3577,
          'joint_counts':joint['counts'],'joint_batches':joint['actual_batches'],'conservative_groups':joint['conservative_groups_by_split'],
          'near_duplicate_candidates':near,'full_replay_restored':True,'original_Drive_bytes_restored':False,
          'swift_valid_cases':14,'swift_invalid_cases':11,'transport_fixture_checks':fixture['checks_passed'],'model_calls':0,'TRAINING_READY':False}),flush=True)
if __name__=='__main__':main()
