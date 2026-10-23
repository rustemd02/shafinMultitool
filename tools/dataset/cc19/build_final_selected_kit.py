"""Package verified data-only results; never decrypt media in this builder.
The actual pixel replay/restore evidence must come from a completed prior run.
"""
from __future__ import annotations
import argparse,hashlib,io,json,os,shutil,sys,urllib.request,urllib.parse,zipfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE));sys.path.insert(0,str(HERE.parent/'cc17'))
import build_delivery_handoff as B
SELECTED_RUN=39960859612
INDEX=12506805778
PROOF=12506740899
BASE_EVAL_INDEX=12438533006
SHOT_INDEX=12465381558
SWIFT=12493309039

def unpack_jsons(aid,out):
    meta,data,z=B.artifact(aid);out.mkdir(parents=True,exist_ok=True)
    values={}
    for name in z.namelist():
        if name.endswith('.json'):
            if '/' in name or '\\' in name:raise ValueError('Unexpected proof subdirectory')
            value=json.loads(z.read(name));values[name]=value;(out/name).write_bytes(z.read(name))
    return meta,values

def release_index(aid):
    meta,data,z=B.artifact(aid)
    values=[json.loads(z.read(n)) for n in z.namelist() if n.endswith('.json')]
    envelope=next((x for x in values if 'release' in x and 'artifacts' in x),None)
    release=envelope['release'] if envelope else next(x for x in values if 'parts' in x and 'label' in x)
    return {'release':release,'source_index_artifact_id':aid,'source_index_sha256':hashlib.sha256(data).hexdigest(),'source_run':meta['workflow_run']['id'],'source_artifacts':envelope.get('artifacts',[]) if envelope else []}

def run(camera_run):
    run=json.loads(B.get(f'/actions/runs/{SELECTED_RUN}'));assert run['conclusion']=='success'
    out=Path('final_selected_handoff');out.mkdir(exist_ok=False)
    _,proof=unpack_jsons(PROOF,out/'proof/selected')
    q=proof['SELECTED_TENSOR_QA.json'];restore=proof['SELECTED_ARCHIVE_RESTORE_QA.json'];status=proof['FINAL_COMPONENT_STATUS.json']
    assert q['selected_records']==3353 and q['scene_configurations']==479 and q['origin_groups']==60
    assert restore['all_actual_tensor_streams_identical'] is True
    assert status['component_data_ready'] is True and status['fresh_archive_restore'] is True
    assert status['actual_Drive_restore'] is False and status['full_cameracoach_training_ready'] is False
    selected=release_index(INDEX);assert selected['release']['label']=='cc19-policy-selected-verified'
    assert len(selected['release']['parts'])==2
    evaluation=[release_index(BASE_EVAL_INDEX),release_index(SHOT_INDEX)]
    camera_summary=None
    if camera_run:
        r=json.loads(B.get(f'/actions/runs/{camera_run}'));assert r['conclusion']=='success'
        arts=json.loads(B.get(f'/actions/runs/{camera_run}/artifacts?per_page=100'))['artifacts']
        ix=next(x for x in arts if x['name']=='cc17-release-index-cc19-acam-camerabench-native-supplement')
        evaluation.append(release_index(ix['id']))
        jobs=json.loads(B.get(f'/actions/runs/{camera_run}/jobs?per_page=100'))['jobs']
        for job in jobs:
            if job['conclusion']!='success':continue
            log=B.get(f'/actions/jobs/{job["id"]}/logs').decode('utf-8-sig')
            for line in log.splitlines():
                if ' CC19_CAMERABENCH_SUMMARY ' in line:camera_summary=json.loads(line.split(' CC19_CAMERABENCH_SUMMARY ',1)[1])
        assert camera_summary and camera_summary['resolved_rows']>0
        B.dump(out/'proof/CAMERABENCH_NATIVE_QA.json',camera_summary)
    # Copy the exact reader used by the actual pixel/restore proof, not a mutable alias.
    frozen=Path('frozen/tools/dataset/cc17')
    for name in ['restore_dataset.py','cc18_dataset.py']:shutil.copyfile(frozen/name,out/name)
    for name in ['selected_reader.py','restore_selected_release.py']:shutil.copyfile(HERE/name,out/name)
    expected={split:{'records':v['records'],'tensor_stream_sha256':v['tensor_stream_sha256']} for split,v in q['split_checks'].items()}
    catalog={'schema':'cc19.final_selected_release_catalog.v1','selected_policy':selected,'expected_tensor_streams':expected,
      'evaluation_only_components':evaluation,'model_execution_authorized':False,'full_cameracoach_training_ready':False,
      'do_not_mix_representations':['selected 3353 corpus','old unfiltered 3577 compact core','full eight synthetic shards'],
      'inherited_external_corpora':'ET, Rapidata, earlier GAIC and critique corpora retain their original task/rights restrictions and are not policy-gold'}
    B.dump(out/'FINAL_RELEASE_CATALOG.json',catalog)
    B.dump(out/'ACTUAL_INPUT_TARGET_SCHEMA.json',proof['SELECTED_ACTUAL_QA.json']['actual_tensor_schema'])
    _,swift=unpack_jsons(SWIFT,out/'proof/swift')
    assert swift['CONTRACT_QA.json']['valid_fixture_cases']==14
    _,_,sz=B.artifact(SWIFT)
    for name in ['CameraActionInputsV1.swift','check_swift_contract.py']:
        (out/name).write_bytes(sz.read(name))
    fixture=B.fixture_test();B.dump(out/'proof/RESTORER_SELFTEST.json',fixture)
    for p in out.glob('*.py'):compile(p.read_text(),str(p),'exec')
    joined=3620+(camera_summary['resolved_rows'] if camera_summary else 0)
    gates={'schema':'cc19.final_scope_status.v1','selected_component_data_ready':True,
       'selected_records':3353,'selected_configuration_count':479,'conservative_origin_groups':60,
       'splits':{'train':2184,'validation':392,'test':777},'distinct_action_candidates':31,'past_rgb_files':1437,
       'actual_pixel_batches_checked':True,'fresh_local_final_archive_restore':True,'all_numeric_tensor_streams_reproduced':True,
       'owner_key_used_by_cloud_job':False,'models_executed':0,'new_human_responses':0,
       'actual_Google_Drive_plaintext_restore':False,'full_CameraCoach_original_DoD':'BLOCKED',
       'original_266_DoD_redefined':False,'original_266_DoD_archive':'ORIGINAL_v16_AUDIT_AND_266_DoD_UNCHANGED.zip',
       'current_image_Metal_CoreML_iPhone_parity':'NOT_MEASURED','numeric_Swift_contract_only':'14 valid fixtures and 11 invalid-input rejections; not app integration',
       'synthetic_scope':'geometric framing, visibility, collision and display pixel tone in procedural proxy scenes; not face/expression/text readability or artistic intent',
       'real_transfer':'NOT_MEASURED','independent_operator_utility':'NOT_COLLECTED','statistical_sufficiency_for_product':'NOT_ESTABLISHED',
       'ACaM_annotation_rows':4153,'ACaM_video_backed_rows':joined,'ACaM_missing_original_rows':4153-joined,
       'commercial_training_real_media':'NOT_CLEARED_BY_THIS_DELIVERY','model_smoke':'NOT_EXECUTED',
       'Drive_upload_verification':'separate connector receipts; no fresh Drive plaintext restore implied'}
    B.dump(out/'FINAL_SCOPE_STATUS.json',gates)
    (out/'requirements.txt').write_text('numpy==1.26.4\nPillow==11.3.0\n')
    text=f'''# CameraCoach v19 — проверенный выбранный набор данных

## Готовый результат

Физически отобранный корпус `cc19-policy-selected-verified`: **3353 задания, 479 конфигураций, 60 консервативных групп**. Train 2184, validation 392, test 777. 1437 реально отрендеренных прошлых RGB; 31 различимый параметризованный кандидат действия. Все пиксели и batches прочитаны. Итоговый зашифрованный архив распакован в чистую облачную папку: полный состав и хеши файлов, затем все потоки числовых X/Y/masks совпали.

Проверенный запуск: https://github.com/rustemd02/shafinMultitool/actions/runs/{SELECTED_RUN}

**Это готовый к загрузке датасет ограниченной задачи физических действий. Не готовность полной CameraCoach policy, не результат обучения и не доказанная человеческая полезность.**

## Какие файлы брать

`CC19_SELECTED_POLICY_000.zip`, `CC19_SELECTED_POLICY_001.zip`, `CC19_SELECTED_POLICY_INDEX.zip` и этот комплект. Приватный ключ уже лежит в той же приватной поставке под именем `PRIVATE_transport_key_DO_NOT_PUBLISH.pem`. Ключ нельзя публиковать или отправлять в issue/log.

Старые `CC19_POLICY_CORE_*` содержат 3577 исходных строк. Полные `CC18_SYN_*` содержат те же сцены и дополнительные послекадры/геометрию. Не складывайте эти три представления как независимые обучающие примеры. Четыре подозрительные origin groups исключены из выбранного корпуса целиком; это защита от утечки, не доказательство фотореализма или переноса.

## Восстановление и чтение в приватном облаке

Требуются Python 3.10+, OpenSSL и зависимости из requirements.txt. Blender, GPU, API и модель для чтения не нужны. Распакуйте этот небольшой handoff ZIP; архивы с частями данных оставьте целыми.

```sh
python -m pip install -r requirements.txt
python restore_selected_release.py --parts-dir /private/v19 --list
python restore_selected_release.py --parts-dir /private/v19 --key /private/v19/PRIVATE_transport_key_DO_NOT_PUBLISH.pem --out /private/restored
```

Восстановитель сверяет части и payload с отдельным зафиксированным каталогом, а затем сравнивает фактические tensor hashes каждой выборки с приложенными результатами выполненного запуска. При уже существующей папке все файлы проверяются заново; молчаливой перезаписи нет.

```python
from pathlib import Path
from selected_reader import batches
root = Path('/private/restored/cc19-policy-selected-verified')
for X, Y, loss_masks in batches(root, split='train', batch_size=8):
    # Здесь реальные NumPy-массивы. Модель подключается отдельно.
    assert X['rgb_history'].shape[1:] == (3, 3, 224, 224)
```

## Смысл разметки

Вход: три прошлых кадра, tap выбранного субъекта, числовая цель, ограничения оборудования и перемешанные кандидаты. Выходы и маски хранятся отдельно. Вход не содержит послекадров, истинной геометрии, oracle-bbox или известного симулятору результата столкновения. Цели задавались до оценки: размер/контекст, видимость/скрытие, диапазон яркости выбранной области. `keep`, `ask`, `abstain` входят в разметку. Неизвестная человеческая оценка не превращена в отрицательную.

Субъекты — геометрические прокси. Термины «portrait», «dialogue», «hand/tool» не доказывают распознавание лиц, эмоций, реальных рук или читаемость текста. Яркость пикселей не является меткой операторского вкуса. Независимость групп относится к данным шаблонам, а не к реальным съёмкам.

## Внешние данные

ET и Rapidata остаются отдельными вспомогательными задачами. ACaM с дополнениями — только оценочный/reference корпус; {joined} из 4153 заданий имеют полученные видео. Исходные test answers не включаются в обучение. Права на реальные фильмы не очищены фактом получения файла. В новых дополнениях оригинальные MP4 и компактные копии различаются явно; компактная оценка не объявляется официальным full-video score.

## Что не закрыто

Исходные 266 требований сохранены отдельно без переименования. Полный DoD не пройден: нет новых независимых человеческих оценок CameraCoach, измеренного переноса на реальные iPhone-сцены, полноценного current-device image preprocessing/runtime сравнения и model smoke. Достаточность объёма для всего продукта не установлена. Реальные capture-time намерения и польза советов не выдуманы.

Чистое восстановление выполнено **из итогового облачного архива**, не повторным скачиванием всей поставки из Google Drive. Приватное runtime в текущем чате возвращало ClientError; отсутствующий Drive plaintext readback не засчитан как PASS. Файлы на Drive проверяются отдельно коннектором по факту загрузки/метаданным.

## Что смотреть в доказательствах

`proof/selected/SELECTED_TENSOR_QA.json` — все реально прочитанные batches и их hashes. `SELECTED_ARCHIVE_RESTORE_QA.json` — чистое восстановление и равенство потоков. `FINAL_SCOPE_STATUS.json` — границы допуска. `proof/swift/` — выполненная проверка числового контракта, не интеграция iPhone.
'''
    (out/'START_HERE_RU.md').write_text(text)
    manifest=[{'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file()]
    B.dump(out/'HANDOFF_MANIFEST.json',{'files':manifest,'contains_private_key':False,'contains_plaintext_media':False})
    print('CC19_FINAL_KIT '+json.dumps(gates),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--camerabench-run',type=int);a=p.parse_args();run(a.camerabench_run)
