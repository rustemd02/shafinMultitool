"""Data-only joint audit. Owner key is never read or exported.
An ephemeral private key lives only inside the audit job. Public certificates and
encrypted artifacts can travel between jobs. No plaintext media are uploaded.
"""
from __future__ import annotations
import argparse,collections,hashlib,io,json,os,shutil,subprocess,sys,tarfile,time,urllib.request,urllib.parse,zipfile
from pathlib import Path
BASE='https://api.github.com/repos/rustemd02/shafinMultitool'
RUN=os.environ.get('GITHUB_RUN_ID','')
FROZEN='dd9cc68c3e1c12fb913a4a8590b55ff0bbdff2ed'
class Redirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):
  out=super().redirect_request(req,fp,code,msg,headers,newurl)
  if out and urllib.parse.urlparse(newurl).hostname!='api.github.com':out.remove_header('Authorization')
  return out
OPENER=urllib.request.build_opener(Redirect())
def request(path):
 return OPENER.open(urllib.request.Request(BASE+path,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'}),timeout=180)
def api(path):
 with request(path) as r:return json.load(r)
def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def dump(p,obj):Path(p).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
def download_artifact(meta,dest):
 with request(f'/actions/artifacts/{meta["id"]}/zip') as r,Path(dest).open('wb') as f:shutil.copyfileobj(r,f)
 expected=meta.get('digest','').removeprefix('sha256:')
 if expected:assert sha(dest)==expected
 assert Path(dest).stat().st_size==meta['size_in_bytes']
 with zipfile.ZipFile(dest) as z:assert z.testzip() is None

def wait_artifact(name,seconds=240):
 deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  found=[a for a in api(f'/actions/runs/{RUN}/artifacts?per_page=100')['artifacts'] if a['name']==name and not a['expired']]
  if found:return max(found,key=lambda a:a['id'])
  time.sleep(5)
 raise TimeoutError('Expected artifact not produced: '+name)

def worker(shard):
 frozen=Path('frozen/tools/dataset/cc17').resolve();sys.path.insert(0,str(frozen))
 meta=wait_artifact('cc19-audit-public-recipient');download_artifact(meta,'recipient.zip')
 with zipfile.ZipFile('recipient.zip') as z:
  names=[n for n in z.namelist() if n.endswith('audit-public.pem')];assert len(names)==1
  Path('audit-public.pem').write_bytes(z.read(names[0]))
 # Work from the frozen source checkout: reproduce the accepted generator.
 os.chdir('frozen');import cc18_entry as E
 builtin_range=range
 def audited_range(*args):
  r=builtin_range(*args)
  return [i for i in r if i!=114] if args==(shard,512,8) else r
 E.R.range=audited_range
 original_pack=E.raw_package
 def with_audit_recipient(root,label):
  if shard==2:dump(Path(root)/'EXCLUDED_SCENES.json',[{'origin_id':'cc18-000114','reason':'historical unresolved analytic/Blender depth mismatch; excluded before this replay','source_job':119934893443}])
  info=original_pack(root,label)
  out=Path('../replay');out.mkdir(exist_ok=True)
  dest=out/'payload.cms'
  subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',info['plaintext_name'],'-out',str(dest),'-outform','DER','tools/dataset/cc17/transport_public.pem','../audit-public.pem'],check=True)
  dump(out/'REPLAY.json',{'label':label,'generator_commit':FROZEN,'shard':shard,'plaintext_bytes':info['plaintext_bytes'],'plaintext_sha256':info['plaintext_sha256'],'ciphertext_bytes':dest.stat().st_size,'ciphertext_sha256':sha(dest),'original_build_comparison':'same frozen generator and accepted origin IDs; archive byte equivalence not claimed'})
  shutil.copyfile(Path(root)/'QA.json',out/'BUILD_QA.json')
  return info
 E.raw_package=with_audit_recipient
 E.R.run(shard,8,512,'cc19-replay')
 print('CC19_REPLAY_COMPLETE',shard,flush=True)

def extract_checked(archive,dest):
 dest.mkdir(parents=True,exist_ok=True)
 with tarfile.open(archive,'r:gz') as t:
  names=set()
  for m in t:
   p=(dest/m.name).resolve()
   if not p.is_relative_to(dest.resolve()) or not m.isfile() or m.name in names:raise ValueError('Unsafe or duplicate member')
   names.add(m.name);p.parent.mkdir(parents=True,exist_ok=True)
   with t.extractfile(m) as f,p.open('wb') as out:shutil.copyfileobj(f,out)
 manifest=json.loads((dest/'PAYLOAD_MANIFEST.json').read_text());entries=manifest['files']
 assert names=={e['path'] for e in entries}|{'PAYLOAD_MANIFEST.json'}
 for e in entries:
  p=dest/e['path'];assert p.stat().st_size==e['size'] and sha(p)==e['sha256'],e['path']
 return {'files_verified':len(entries),'bytes_verified':sum(e['size'] for e in entries),'manifest_sha256':sha(dest/'PAYLOAD_MANIFEST.json')}

def joint(key):
 sys.path.insert(0,str(Path('frozen/tools/dataset/cc17').resolve()));from cc18_dataset import audit,lines,load_batch
 import numpy as np
 root=Path('joint_data');root.mkdir(exist_ok=True);receipts=[];done=set();deadline=time.monotonic()+3300
 while len(done)<8 and time.monotonic()<deadline:
  artifacts=api(f'/actions/runs/{RUN}/artifacts?per_page=100')['artifacts']
  for a in artifacts:
   if not a['name'].startswith('cc19-replay-shard-'):continue
   shard=int(a['name'].rsplit('-',1)[1])
   if shard in done:continue
   download_artifact(a,'part.zip')
   with zipfile.ZipFile('part.zip') as z:
    for name in ['REPLAY.json','BUILD_QA.json','payload.cms']:
     matches=[n for n in z.namelist() if n==name or n.endswith('/'+name)];assert len(matches)==1
     with z.open(matches[0]) as src,Path(name).open('wb') as f:shutil.copyfileobj(src,f)
   info=json.loads(Path('REPLAY.json').read_text());assert info['shard']==shard and info['generator_commit']==FROZEN
   assert sha('payload.cms')==info['ciphertext_sha256']
   subprocess.run(['openssl','cms','-decrypt','-binary','-inform','DER','-in','payload.cms','-inkey',key,'-out','restored.tar.gz'],check=True,stdout=subprocess.DEVNULL)
   assert sha('restored.tar.gz')==info['plaintext_sha256'] and Path('restored.tar.gz').stat().st_size==info['plaintext_bytes']
   dest=root/f'shard_{shard:02d}';checks=extract_checked('restored.tar.gz',dest)
   receipts.append({'shard':shard,'artifact_id':a['id'],'ciphertext_sha256':info['ciphertext_sha256'],**checks})
   done.add(shard);print('CC19_PRIVATE_RESTORED',shard,checks['files_verified'],flush=True)
   for p in ['part.zip','payload.cms','restored.tar.gz']:Path(p).unlink()
  if len(done)<8:time.sleep(12)
 assert len(done)==8,{'missing_shards':sorted(set(range(8))-done)}
 result=audit(root,batch_size=8)
 # Check every origin has the same past observations across all declared goals.
 observations={};targets={};counts=collections.Counter();cf_count=0;ver_count=0
 for inputs in sorted(root.glob('*/inputs.jsonl')):
  base=inputs.parent;tm={r['record_id']:r for r in lines(base/'targets.jsonl')};rows=list(lines(inputs))
  for r in rows:
   origin=r['provenance']['scene_id'];sig=json.dumps(r['observations']['history'],sort_keys=True)
   assert observations.setdefault(origin,sig)==sig
   counts[r['split']]+=1
  # A target mutation must never change any X tensor.
  sample=rows[:3];X,_,_=load_batch(base,sample,tm);mutated={k:dict(v) for k,v in tm.items()}
  for r in sample:
   t=mutated[r['record_id']];t['decision']='ask';t['target_action_index']=None;t['action_success']=[not v for v in t['action_success']]
  X2,_,_=load_batch(base,sample,mutated)
  assert X.keys()==X2.keys() and all(np.array_equal(X[k],X2[k]) for k in X),'Target-to-input leakage'
  cf_count+=sum(1 for _ in lines(base/'counterfactuals.jsonl'));ver_count+=sum(1 for _ in lines(base/'outcome_verifier.jsonl'))
 assert len(observations)==511 and result['counts']['policy_rows']==3577 and cf_count==16352 and ver_count==98112
 # Build a compact, standalone policy-training core, not a renamed full policy.
 core=Path('policy_core');core.mkdir(exist_ok=True)
 for source in sorted(root.iterdir()):
  dest=core/source.name;dest.mkdir()
  for name in ['inputs.jsonl','targets.jsonl','counterfactuals.jsonl','scenes.jsonl','actions.json','goals.json','split_definition.json','image_signatures.jsonl','QA.json','RENDERER_FREE_CONSUMER_AUDIT.json']:
   shutil.copyfile(source/name,dest/name)
  paths={h['rgb'] for r in lines(source/'inputs.jsonl') for h in r['observations']['history']}
  for name in paths:
   p=dest/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/name,p)
 core_result=audit(core,batch_size=8);assert core_result==result
 # Reuse a frozen reader rather than requiring Blender for loading the core.
 shutil.copyfile('frozen/tools/dataset/cc17/cc18_dataset.py',core/'cc18_dataset.py')
 report={'schema':'cc19.joint_private_replay.v1','frozen_generator_commit':FROZEN,'source_builds':[39809877540,39812496682],
  'actual_replay_run':RUN,'all_eight_replays_restored':True,'original_drive_bytes_restored':False,
  'source':'fresh deterministic replay of accepted generator; not claimed to be the original Drive archive bytes',
  'transport_receipts':receipts,'joint_consumer':result,'core_consumer':core_result,'scene_configurations':len(observations),
  'counterfactual_states':cf_count,'verifier_rows_in_full_replay':ver_count,'target_mutation_input_invariance':True,
  'model_calls':0,'new_human_responses':0,'full_cameracoach_training_ready':False,
  'restrictions':['physical synthetic task component only','not proof of real-world transfer or human utility','no exact iPhone preprocessing parity','test numerical failures were development-exposed historically','near-duplicate candidates require explicit review']}
 dump(core/'JOINT_AUDIT.json',report)
 (core/'README_RU.md').write_text('# CameraCoach: законченный физический policy-компонент\n\n511 принятых конфигураций, 3577 заданий, 31 различимый кандидат. Фактически восстановлены и совместно прочитаны все 8 облачных партий. Это повторная сборка фиксированного генератора, не проверка исходных байтов Google Drive.\n\nЗагрузчик: python cc18_dataset.py --data-root . --receipt consumer.json\n\nВ core входят только прошлые RGB, цели, выбранные точки и targets; будущие RGB и dense geometry сюда не включены. counterfactuals.jsonl — доказательства/targets, не online inputs. Исходные полные партии сохранены отдельно.\n\nСинтетические объекты геометрические. Проверка полезности для реальных операторов и перенос на iPhone не выполнены. Общая готовность всей CameraCoach policy не заявляется.\n')
 # Owner-only encryption of the result. No audit private key can enter this path.
 os.chdir('frozen');from release_pack import package
 package(Path('../policy_core'),'cc19-policy-core-joint-verified')
 os.chdir('..');Path('proof').mkdir(exist_ok=True);dump('proof/JOINT_AUDIT.json',report)
 print('CC19_JOINT_SUMMARY '+json.dumps({k:v for k,v in report.items() if k not in ['joint_consumer','core_consumer','transport_receipts']}),flush=True)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['worker','joint']);p.add_argument('--shard',type=int);p.add_argument('--key');a=p.parse_args()
 if a.mode=='worker':worker(a.shard)
 else:
  try:joint(a.key)
  finally:
   if a.key:Path(a.key).unlink(missing_ok=True)
