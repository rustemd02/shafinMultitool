"""Final handoff with an explicit source-group quarantine; raw corpora unchanged."""
from pathlib import Path
import hashlib,json,shutil
import finalize_handoff  # Executes the source-proof and protected-restore checks.
import selection_v19 as S
out=Path('cc19_handoff');here=Path(__file__).resolve().parent
shutil.copyfile(here/'selection_v19.py',out/'selection_v19.py')
p=out/'prepare_cc19.py';text=p.read_text()
assert text.count('import cc18_dataset as D')==1 and text.count('report=D.audit(selected_root)')==1
text=text.replace('import cc18_dataset as D','import cc18_dataset as D\nimport selection_v19 as S')
text=text.replace('report=D.audit(selected_root)','report=S.audit_selection(selected_root)')
text=text.replace("'resolve any near-duplicate screening candidates before heldout quality claims',",'')
p.write_text(text)
proof=S.selection_metadata_test();(out/'proof/SELECTION_METADATA_QA.json').write_text(json.dumps(proof,indent=2)+'\n')
nb_path=out/'CC19_RESTORE_SELECTED.ipynb';nb=json.loads(nb_path.read_text())
for cell in nb['cells']:
    if cell['cell_type']=='code':
        source=''.join(cell['source'])
        source=source.replace("'prepare_cc19.py','DATASET_CATALOG.json'","'prepare_cc19.py','selection_v19.py','DATASET_CATALOG.json'")
        cell['source']=source.splitlines(True)
nb['cells'].insert(1,{'cell_type':'markdown','metadata':{},'source':['В сохранённом корпусе 3577 исходных заданий. Загрузчик допускает 3353 после исключения четырёх полных origin groups: train 2184, validation 392, test 777. Сырые записи не удалены и не переименованы; это консервативная защита от двух найденных cross-split dHash-пар, а не утверждение об их визуальной идентичности.\n']})
nb_path.write_text(json.dumps(nb,ensure_ascii=False,indent=2)+'\n')
gate_path=out/'GATE_STATUS.json';g=json.loads(gate_path.read_text());g.update(
    near_duplicate_semantic_adjudication='NOT_CLAIMED',
    near_duplicate_resolution='ALL_FOUR_INVOLVED_ORIGIN_GROUPS_QUARANTINED_IN_SELECTION',
    selected_policy_rows=3353,selected_split_rows={'train':2184,'validation':392,'test':777},
    selected_topology_groups=60,
    selected_batch_check='source full corpus was consumed; filtered consumer rechecks actual rows at private restore; this metadata-only job did not decrypt owner corpus')
gate_path.write_text(json.dumps(g,ensure_ascii=False,indent=2)+'\n')
readme=out/'START_HERE_RU.md';text=readme.read_text();prefix='''## Активная выборка после защиты от утечки

В исходном corpus остаются 3577 записей; в действующем допуске — **3353**: 2184 train, 392 validation, 777 test. Это 479 конфигураций в 60 консервативных topology groups. Исключены целиком четыре группы, участвовавшие в двух подозрительных cross-split dHash-парах. Источники сохранены неизменными. Этот шаг не объявляет картинки визуально идентичными и не доказывает перенос на реальные сцены.

`selection_v19.py` содержит `batches(root, split='train', batch_size=8)`. Используйте его для экспериментального обучения, а не прямой необработанный `load_batch` по всем строкам. `prepare_cc19.py` вызывает фильтрованный consumer, который заново читает реальные записи, проверяет 3353 ID/224 исключения/состав групп и собирает отдельные X/Y/masks. В нынешнем metadata-only тесте проверена строгая схема отбора; все исходные 3577 строк ранее были реально прочитаны joint consumer. Новый полный прогон отфильтрованных пикселей здесь не выдаётся за выполненный.

'''
readme.write_text(text.replace('## Что использовать\n',prefix+'## Что использовать\n',1),encoding='utf-8')
# Keep the standalone numeric test usable from both a checkout and this flat ZIP.
p=out/'check_swift_contract.py';t=p.read_text()
t=t.replace("sys.path.insert(0,str(ROOT.parent/'cc17'))", "sys.path.insert(0,str(ROOT))\nsys.path.insert(0,str(ROOT.parent/'cc17'))")
t=t.replace("loader=ROOT.parent/'cc17/cc18_dataset.py'", "loader=(ROOT/'cc18_dataset.py') if (ROOT/'cc18_dataset.py').is_file() else ROOT.parent/'cc17/cc18_dataset.py'")
p.write_text(t)
for file in out.glob('*.py'):compile(file.read_text(),str(file),'exec')
files=[{'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file() and p.name!='HANDOFF_MANIFEST.json']
(out/'HANDOFF_MANIFEST.json').write_text(json.dumps({'schema':'cc19.handoff_manifest.v2','files':files,'contains_private_key':False,'contains_plaintext_dataset_media':False},indent=2)+'\n')
print('CC19_SELECTED_HANDOFF '+json.dumps(proof),flush=True)
