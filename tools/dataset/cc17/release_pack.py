"""Private task-dataset release, compressed before CMS encryption.
Chunks respect the smallest connected transport limit. No model code is used.
"""
from __future__ import annotations
import hashlib,json,subprocess,tarfile,shutil
from pathlib import Path
from acquire import digest,write_json
LIMIT=90*1024*1024

def package(root:Path,label:str)->dict:
 root=Path(root); delivery=Path('delivery');delivery.mkdir(exist_ok=True)
 code=root/'reproduction';code.mkdir(exist_ok=True)
 for p in Path('tools/dataset/cc17').glob('*.py'):
  if p.name!='datadop.py':shutil.copyfile(p,code/p.name)
 entries=[{'path':str(p.relative_to(root)),'size':p.stat().st_size,'sha256':digest(p)} for p in sorted(root.rglob('*')) if p.is_file() and p.name!='PAYLOAD_MANIFEST.json']
 write_json(root/'PAYLOAD_MANIFEST.json',{'schema':'cc17.payload.v1','label':label,'files':entries,'model_execution':False})
 plain=Path(label+'.tar.gz')
 with tarfile.open(plain,'w:gz',compresslevel=6) as t:
  for p in sorted(root.rglob('*')):
   if p.is_file():t.add(p,arcname=str(p.relative_to(root)),recursive=False)
 # Read all archived bytes and compare the manifest before calling a release complete.
 checks={e['path']:e for e in entries};bad=[]
 with tarfile.open(plain,'r:gz') as t:
  for m in t:
   if not m.isfile() or m.name=='PAYLOAD_MANIFEST.json':continue
   b=t.extractfile(m).read();e=checks.get(m.name)
   if e is None or len(b)!=e['size'] or hashlib.sha256(b).hexdigest()!=e['sha256']:bad.append(m.name)
 assert not bad,bad
 encrypted=Path(label+'.tar.gz.cms')
 subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',str(plain),'-out',str(encrypted),'-outform','DER','tools/dataset/cc17/transport_public.pem'],check=True)
 parts=[]
 with encrypted.open('rb') as f:
  for i in range(1000):
   b=f.read(LIMIT)
   if not b:break
   p=delivery/(label+'.p'+str(i).zfill(3));p.write_bytes(b)
   parts.append({'name':p.name,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
 info={'label':label,'plaintext_name':plain.name,'plaintext_bytes':plain.stat().st_size,'plaintext_sha256':digest(plain),'encrypted_bytes':encrypted.stat().st_size,'encrypted_sha256':digest(encrypted),'parts':parts,'payload_files_verified':len(entries),'payload_bytes':sum(e['size'] for e in entries),'archive_readback_mismatches':bad}
 write_json(delivery/'RELEASE.json',info)
 print('CC17_RELEASE '+json.dumps(info),flush=True)
 return info
