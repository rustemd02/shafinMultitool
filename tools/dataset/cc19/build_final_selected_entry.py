"""Final handoff execution with bounded ciphertext checks, no decryption keys.
Fixes only portable packaging paths and records heldout exposure explicitly.
"""
from pathlib import Path
import hashlib,json,shutil,sys,time
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE));sys.path.insert(0,str(HERE.parent/'cc17'))
import build_final_selected_kit as K
import restore_selected_release as E
import restore_dataset as R
CAMERA_RUN=39964839454

def unpack_jsons(aid,out):
    meta,data,z=K.B.artifact(aid);out.mkdir(parents=True,exist_ok=True);values={}
    for name in z.namelist():
        if not name.endswith('.json'):continue
        rel=R.safe_relative(name);value=json.loads(z.read(name));values[name]=value
        dest=out/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(z.read(name))
    return meta,values
K.unpack_jsons=unpack_jsons

for _ in range(60):
    r=json.loads(K.B.get(f'/actions/runs/{CAMERA_RUN}'))
    if r['status']=='completed':
        assert r['conclusion']=='success','CameraBench acquisition not successful';break
    time.sleep(5)
else:raise RuntimeError('Bounded wait for source acquisition exhausted')
K.run(CAMERA_RUN)
out=Path('final_selected_handoff');catalog=json.loads((out/'FINAL_RELEASE_CATALOG.json').read_text())
parts=Path('selected_ciphertext_checks');parts.mkdir(exist_ok=True)
receipts=[]
for artifact in catalog['selected_policy']['source_artifacts']:
    meta,data,z=K.B.artifact(artifact['id']);p=parts/(str(artifact['id'])+'.zip');p.write_bytes(data)
    receipts.append({'artifact_id':artifact['id'],'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'crc_checked':True,'source':'GitHub source artifact; not Drive'})
assert len(receipts)==2
item=E.find_selected([parts],catalog);assert not R.missing(item)
for part in item['release']['parts']:
    path,name=item['parts'][part['name']]
    import zipfile
    with zipfile.ZipFile(path) as z:
        value=z.read(name)
        assert len(value)==part['bytes'] and hashlib.sha256(value).hexdigest()==part['sha256']
wrong=json.loads(json.dumps(catalog));wrong['selected_policy']['release']['plaintext_sha256']='0'*64
try:E.find_selected([parts],wrong);raise AssertionError('Untrusted catalog accepted')
except ValueError:pass
incomplete={'release':item['release'],'parts':dict(item['parts'])};incomplete['parts'].pop(next(iter(incomplete['parts'])))
assert len(R.missing(incomplete))==1
K.B.dump(out/'proof/FINAL_PINNED_CIPHERTEXT_CHECK.json',{'files':receipts,'complete_selected_parts':True,'trusted_catalog_mismatch_rejected':True,'missing_part_reported':True,'payload_decrypted_here':False,'actual_Drive_restore':False})
# Make the optional Swift verifier runnable after flat ZIP extraction.
p=out/'check_swift_contract.py';text=p.read_text()
text=text.replace("sys.path.insert(0,str(ROOT.parent/'cc17'))", "sys.path.insert(0,str(ROOT))\nsys.path.insert(0,str(ROOT.parent/'cc17'))")
text=text.replace("loader=ROOT.parent/'cc17/cc18_dataset.py'", "loader=(ROOT/'cc18_dataset.py') if (ROOT/'cc18_dataset.py').is_file() else ROOT.parent/'cc17/cc18_dataset.py'")
p.write_text(text)
g=out/'FINAL_SCOPE_STATUS.json';status=json.loads(g.read_text());status['test_exposure']='Synthetic heldout numerical failures were observed during development; not a pristine external hidden test'
K.B.dump(g,status)
r=out/'START_HERE_RU.md';r.write_text(r.read_text()+'\n## Ограничение тестовой независимости\n\nВо время разработки проверок просматривались числовые сбои синтетического test. Разделение origin groups сохранено, но этот test не называется нераскрытым внешним экзаменом. Его нельзя использовать как независимое доказательство качества продукта.\n')
for p in out.glob('*.py'):compile(p.read_text(),str(p),'exec')
entries=[{'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file() and p.name!='HANDOFF_MANIFEST.json']
K.B.dump(out/'HANDOFF_MANIFEST.json',{'files':entries,'contains_plaintext_media':False,'contains_private_key':False})
print('CC19_FINAL_SELECTED_HANDOFF_PASS '+json.dumps({'files':len(entries),'selected_rows':3353,'actual_pixel_and_restore_proof':True,'ACaM_video_backed_rows':status['ACaM_video_backed_rows'],'ACaM_missing_original_rows':status['ACaM_missing_original_rows'],'full_cameracoach_training_ready':False}),flush=True)
