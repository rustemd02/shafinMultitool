"""Create code-only handoff and execute restoration/data-consumer tests.
Only code and aggregate test receipts are published as a transport artifact.
Owner data and keys are never copied into the handoff artifact.
"""
from __future__ import annotations
import hashlib,io,json,shutil,subprocess,tarfile,tempfile,zipfile
from pathlib import Path
import restore_dataset as D
from acquire import write_json,digest


def selftest():
    checks=[]
    with tempfile.TemporaryDirectory() as td:
        t=Path(td);payload=t/'fixture';payload.mkdir();(payload/'fixture.txt').write_text('TEST FIXTURE ONLY: not a dataset sample.\n')
        files=[{'path':'fixture.txt','size':(payload/'fixture.txt').stat().st_size,'sha256':digest(payload/'fixture.txt')}]
        write_json(payload/'PAYLOAD_MANIFEST.json',{'label':'selftest','files':files})
        plain=t/'fixture.tar.gz'
        with tarfile.open(plain,'w:gz') as z:
            for p in sorted(payload.iterdir()):z.add(p,arcname=p.name,recursive=False)
        key=t/'ephemeral.pem';cert=t/'ephemeral.crt'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=CameraCoach-Test-Fixture'],check=True,capture_output=True)
        encrypted=t/'fixture.cms'
        subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',str(plain),'-out',str(encrypted),'-outform','DER',str(cert)],check=True,capture_output=True)
        chunks=[encrypted.read_bytes()[i:i+256] for i in range(0,encrypted.stat().st_size,256)]
        parts=[{'name':f'selftest.p{i:03d}','bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()} for i,b in enumerate(chunks)]
        release={'label':'selftest','plaintext_name':plain.name,'plaintext_bytes':plain.stat().st_size,'plaintext_sha256':digest(plain),'encrypted_bytes':encrypted.stat().st_size,'encrypted_sha256':digest(encrypted),'parts':parts,'payload_files_verified':1,'payload_bytes':files[0]['size'],'archive_readback_mismatches':[]}
        folder=t/'parts';folder.mkdir()
        for i,(p,b) in enumerate(zip(parts,chunks)):
            with zipfile.ZipFile(folder/f'{i:03d}.zip','w') as z:z.writestr('RELEASE.json',json.dumps(release));z.writestr(p['name'],b)
        item=D.discover(folder)['selftest'];receipt=D.restore_one(item,key,t/'restored');assert receipt['cms_decrypted'] and receipt['verified_files']==1;checks.append('complete_CMS_restore_and_payload_hashes')
        try:D.restore_one(item,key,t/'restored');raise AssertionError('overwrite accepted')
        except FileExistsError:checks.append('overwrite_rejected')
        partial={'release':release,'parts':dict(item['parts'])};partial['parts'].pop(parts[0]['name'])
        try:D.restore_one(partial,key,t/'missing');raise AssertionError('missing part accepted')
        except ValueError:checks.append('missing_part_rejected')
        with zipfile.ZipFile(folder/'000.zip','w') as z:
            z.writestr('RELEASE.json',json.dumps(release));b=bytearray(chunks[0]);b[5]^=1;z.writestr(parts[0]['name'],b)
        try:D.restore_one(D.discover(folder)['selftest'],key,t/'tamper');raise AssertionError('tampered part accepted')
        except ValueError:checks.append('tampered_part_rejected')
        for name in ['../escape','/absolute','folder/../../escape','C:\\escape']:
            try:D.safe_relative(name);raise AssertionError('unsafe path accepted')
            except ValueError:pass
        checks.append('unsafe_paths_rejected')
    return {'checks_passed':checks,'test_fixture_only':True,'actual_owner_Drive_restore_executed':False,'owner_key_used':False,'dataset_samples_created':0}


def notebook():
    cells=[]
    def md(text):cells.append({'cell_type':'markdown','metadata':{},'source':text.splitlines(True)})
    def code(text):cells.append({'cell_type':'code','metadata':{},'execution_count':None,'outputs':[],'source':text.splitlines(True)})
    md('# CameraCoach: восстановление и data-only проверка\n\nРаботает в приватном Colab с вашим Drive. Не публикуйте notebook outputs или ключ. Ни модели, ни обучение не запускаются. Human utility и пригодность полной CameraCoach policy этим тестом не подтверждаются.\n')
    code("%pip -q install 'numpy==1.26.4' 'Pillow==11.3.0'\nfrom google.colab import drive\ndrive.mount('/content/drive')\n")
    code("from pathlib import Path\nimport zipfile, subprocess, sys, json\nfolders=list(Path('/content/drive/MyDrive').rglob('CameraCoach_v17_DATA_ACQUISITION_20261022'))\nassert len(folders)==1, 'Укажите PARTS вручную: должна быть ровно одна папка поставки.'\nPARTS=folders[0]\nKEY=PARTS/'PRIVATE_transport_key_DO_NOT_PUBLISH.pem'\nassert KEY.is_file(), 'Нет приватного ключа этой поставки'\nTOOLS=Path('/content/cc18_tools'); TOOLS.mkdir(exist_ok=True)\nwith zipfile.ZipFile(PARTS/'CC18_HANDOFF_TOOLS.zip') as z:\n    for name in ['restore_dataset.py','cc18_dataset.py']:\n        (TOOLS/name).write_bytes(z.read(name))\nOUT=Path('/content/cameracoach_restored')\n")
    code("subprocess.run([sys.executable,str(TOOLS/'restore_dataset.py'),'--parts-dir',str(PARTS),'--list'],check=True)\n")
    code("subprocess.run([sys.executable,str(TOOLS/'restore_dataset.py'),'--parts-dir',str(PARTS),'--key',str(KEY),'--out',str(OUT),'--all'],check=True)\n")
    code("receipt=PARTS/'CC18_RENDERER_FREE_CONSUMER_ACTUAL_READBACK.json'\nsubprocess.run([sys.executable,str(TOOLS/'cc18_dataset.py'),'--data-root',str(OUT),'--receipt',str(receipt)],check=True)\nprint('Фактическая квитанция сохранена в приватной папке. Это проверка данных, не обучение.')\n")
    md('## Интерпретация\n\nВосстановитель проверяет порядок и SHA каждой части, целый CMS, расшифрованный tar и каждый payload-файл. Consumer проверяет реальные прошлые кадры, выборки, цели и маски, собирает NumPy batches без Blender. По умолчанию используется только tap, не идеальный bounding box. Эквивалентный keep вариант wait исключён, поэтому в обучающем batch 31 кандидат.\n\nНаличие dHash-кандидатов требует просмотра: этот скрининг не означает автоматически ошибку или доказанную независимость. Отсутствие всех ошибок не превращает синтетику в человеческую оценку, не даёт прав на сторонние медиа и не подтверждает full-policy TRAINING_READY.\n')
    return {'cells':cells,'metadata':{'kernelspec':{'display_name':'Python 3','language':'python','name':'python3'}},'nbformat':4,'nbformat_minor':5}

out=Path('handoff');out.mkdir(exist_ok=True)
report={'restorer':selftest(),'model_calls':0}
# Run the renderer-free consumer on genuinely rendered, separately generated
# eight-family contract cases. This is NOT a readback of the delivered corpus.
import cc18_entry as E
E.R.package=lambda root,label:None
E.R.run(0,1,8,'cc18-consumer-contract')
from cc18_dataset import audit
report['renderer_free_consumer']=audit(Path('complete/cc18-consumer-contract-00'))
report['renderer_free_consumer_scope']='8 newly rendered contract scenes, not full delivered-corpus readback'
write_json(out/'SELFTEST.json',report)
for name in ['restore_dataset.py','cc18_dataset.py']:shutil.copyfile(Path(__file__).with_name(name),out/name)
write_json(out/'CC18_RESTORE_AND_CHECK.ipynb',notebook())
(out/'README_RU.md').write_text('''# CameraCoach — инструменты фактической поставки

Нужны Python 3.10+, OpenSSL; consumer — numpy==1.26.4 и Pillow==11.3.0. Blender для загрузки данных не нужен.

1. Откройте CC18_RESTORE_AND_CHECK.ipynb в приватном Colab и подключите собственный Drive. Архив CC18_HANDOFF_TOOLS.zip и приватный ключ должны оставаться в той же папке, что части.
2. Восстановитель сначала показывает недостающие части. При отсутствии хотя бы одной части, ошибке SHA/CRC, неверном ключе или небезопасном tar он прекращает работу, не объявляя поставку готовой.
3. После восстановления consumer читает все CC18 policy records, проверяет прошлые кадры, source-group splits, exact hashes, missingness и реальные NumPy batches. Новая квитанция создаётся только после успешного фактического запуска.

Команды вне Colab:
```
python restore_dataset.py --parts-dir /private/delivery --list
python restore_dataset.py --parts-dir /private/delivery --key /private/key.pem --out /private/restored --all
python cc18_dataset.py --data-root /private/restored --receipt /private/consumer_receipt.json
```

inputs/targets/loss masks не смешивать. Counterfactual after-images и oracle geometry допустимы только для отдельного outcome verifier, не для online policy. Родной consumer в reproduction использует точную видимую box-инициализацию; новый renderer-free consumer по умолчанию использует только tap и исключает эквивалентный wait-кандидат. Не смешивайте их результаты без указания интерфейса.

SELFTEST.json содержит реально исполненные тесты кода на искусственном транспортном fixture и 8 отдельно отрендеренных сценах. Это НЕ доказательство чистого восстановления всех owner bytes с Drive. Не переименовывайте эту квитанцию в full-dataset readback.

Полная CameraCoach policy требует независимой человеческой полезности, реального телефонного/новичкового покрытия и проверки current MVP. Они не появляются автоматически из этих архивов. Обучение, forward/backward и изменения приложения здесь не выполняются.
''')
print('CC18_HANDOFF_TESTS '+json.dumps(report),flush=True)
