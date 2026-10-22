"""Data-only acquisition. Never imports a model or publishes unencrypted media."""
from __future__ import annotations
import argparse, concurrent.futures as cf, hashlib, io, json, os, re, subprocess, tarfile, time, zipfile
from pathlib import Path
from urllib.parse import quote, urlparse
import requests

SOURCES={
 'acam':('Yuwen2024/ACaM-Bench','416a728dba34db8a51079c7ee4465276f8236f21'),
 'rapidata':('Rapidata/image-to-video-camera-movement-human-feedback-benchmark','8c5379ca3f4d997092ff54f4794ccc18eb4bb9ff'),
 'et':('robin-courant/et-data','94ea08f5feb9c4375c8b0cf22f22fadb50b3931b14d'),
 'datadop':('Dubhe-zmc/DataDoP',None),
}
# Correct exact source revision from the discovery receipt.
SOURCES['et']=('robin-courant/et-data','94ea08f5feb9c4375c8b0cf22fadb50b3931b14d')
UA={'User-Agent':'CameraCoach-data-only-acquisition/17'}

def write_json(path,obj):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(json.dumps(obj,ensure_ascii=False,indent=2,allow_nan=False)+'\n')

def digest(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()

def get_json(url):
 r=requests.get(url,headers=UA,timeout=(20,90));r.raise_for_status();return r.json(),r

def source_info(key,out):
 repo,rev=SOURCES[key]
 info,_=get_json('https://huggingface.co/api/datasets/'+repo+(('/revision/'+rev) if rev else ''))
 rev=info['sha'];repo=info['id'];tree=[]
 url=f'https://huggingface.co/api/datasets/{repo}/tree/{rev}?recursive=true&limit=1000'
 while url:
  page,r=get_json(url);tree.extend(page);url=r.links.get('next',{}).get('url')
 write_json(out/'source_info.json',info);write_json(out/'source_tree.json',tree)
 return repo,rev,[v for v in tree if v['type']=='file']

def download(url,dest,size=None,expected_sha=None):
 dest=Path(dest);dest.parent.mkdir(parents=True,exist_ok=True)
 if dest.exists() and (size is None or dest.stat().st_size==size) and (expected_sha is None or digest(dest)==expected_sha):
  return {'path':str(dest),'bytes':dest.stat().st_size,'sha256':digest(dest),'url':url}
 last=None
 for attempt in range(3):
  part=dest.with_name(dest.name+'.partial')
  try:
   with requests.get(url,headers=UA,stream=True,timeout=(20,120)) as r:
    if r.status_code==429:
     time.sleep(min(120,int(r.headers.get('Retry-After','30'))));continue
    r.raise_for_status();h=hashlib.sha256();n=0
    with open(part,'wb') as f:
     for b in r.iter_content(1024*1024):
      if b:f.write(b);h.update(b);n+=len(b)
   if size is not None and n!=size:raise ValueError('size mismatch')
   if expected_sha and h.hexdigest()!=expected_sha:raise ValueError('source hash mismatch')
   part.replace(dest)
   return {'path':str(dest),'bytes':n,'sha256':h.hexdigest(),'url':url}
  except Exception as e:
   last=type(e).__name__+': '+str(e).split('?')[0];part.unlink(missing_ok=True)
   if isinstance(e,requests.HTTPError) and e.response.status_code in (401,403,404):break
   time.sleep(2**attempt)
 raise RuntimeError(last or 'download failed')

def acquire_files(key,out,predicate):
 repo,rev,files=source_info(key,out)
 selected=[v for v in files if predicate(v)]
 def work(v):
  url=f'https://huggingface.co/datasets/{repo}/resolve/{rev}/'+quote(v['path'],safe='/')
  try:
   r=download(url,out/'native'/v['path'],v.get('size'),v.get('lfs',{}).get('oid'))
   r['path']=str(Path(r['path']).relative_to(out));r['source_path']=v['path'];r['status']='downloaded';return r
  except Exception as e:return {'source_path':v['path'],'status':'failed','error':str(e)}
 with cf.ThreadPoolExecutor(max_workers=4) as pool: receipts=list(pool.map(work,selected))
 write_json(out/'downloads.json',receipts)
 print('ACQUIRED',key,len([r for r in receipts if r['status']=='downloaded']),len(selected),flush=True)
 return receipts

def inspect_metadata(root):
 import pyarrow.parquet as pq
 summary={}
 for key in SOURCES:
  out=root/key
  pred=lambda v:(v['path'].endswith(('.jsonl','.txt','.md','.csv','.sh','.json','.parquet')) and v.get('size',0)<4000000)
  acquire_files(key,out,pred)
  if key=='rapidata':
   rows=[]
   for p in sorted((out/'native/data').glob('*.parquet')):rows.extend(pq.read_table(p).to_pylist())
   with open(out/'native_rows.jsonl','w') as f:
    for row in rows:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')
   assets={};votes=0;bad=0
   for i,row in enumerate(rows):
    for col in ('reference_gif','input_image','video1','video2'):
     u=row.get(col)
     if isinstance(u,str) and u.startswith(('http://','https://')):assets.setdefault(u,{'roles':set(),'rows':[]})['roles'].add(col);assets[u]['rows'].append(i)
    try:
     d=row.get('detailed_results_movement');d=json.loads(d) if isinstance(d,str) else d
     if isinstance(d,list):votes+=len(d)
    except Exception:bad+=1
   manifest=[{'url':u,'asset_id':hashlib.sha256(u.encode()).hexdigest(),'roles':sorted(v['roles']),'row_indices':v['rows']} for u,v in sorted(assets.items())]
   write_json(out/'asset_manifest.json',manifest)
   summary[key]={'rows':len(rows),'unique_urls':len(assets),'roles':{c:sum(c in v['roles'] for v in assets.values()) for c in ('reference_gif','input_image','video1','video2')},'vote_list_events':votes,'invalid_detailed_json':bad,'columns':list(rows[0]) if rows else [],'first_row_structure':{k:type(v).__name__ for k,v in rows[0].items()} if rows else {},'hosts':sorted({urlparse(u).hostname for u in assets})}
  elif key=='acam':
   summary[key]={}
   for p in (out/'native').glob('*.jsonl'):
    rows=[json.loads(l) for l in p.read_text().splitlines() if l.strip()]
    summary[key][p.name]={'rows':len(rows),'first_row':rows[0] if rows else None}
  else:
   summary[key]={'downloaded_files':len(list((out/'native').rglob('*'))),'available_files':[{'path':v['path'],'size':v.get('size')} for v in json.loads((out/'source_tree.json').read_text()) if v['type']=='file']}
   if (out/'native/README.md').exists():summary[key]['readme']=(out/'native/README.md').read_text()[:5000]
 write_json(root/'SUMMARY.json',summary)
 print('CC17_SUMMARY '+json.dumps(summary,ensure_ascii=False),flush=True)

def et_core(root):
 import numpy as np
 out=root/'et'
 wanted={'bounds.tar.gz','cam_segments.tar.gz','caption.tar.gz','caption_cam.tar.gz','char.tar.gz','char_segments.tar.gz','intrinsics.tar.gz','traj.tar.gz'}
 acquire_files('et',out,lambda v:v['path'] in wanted or v['path'].endswith(('.txt','.md','.sh')))
 summary={};indexes={}
 for p in sorted((out/'native').glob('*.tar.gz')):
  family=p.name[:-7];count=0;bytes_=0;bad=[];examples=[];index={}
  with tarfile.open(p,'r|gz') as t,open(out/(family+'_index.jsonl'),'w') as jf:
   for m in t:
    if not m.isfile():continue
    if m.name.startswith('/') or '..' in Path(m.name).parts:raise ValueError('unsafe native archive member')
    data=t.extractfile(m).read();count+=1;bytes_+=len(data)
    row={'member':m.name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'native_archive':p.name}
    if m.name.endswith('.npy'):
     try:
      a=np.load(io.BytesIO(data),allow_pickle=False);row.update(shape=list(a.shape),dtype=str(a.dtype),finite=bool(np.isfinite(a).all()))
      if not row['finite']:bad.append(m.name)
      if family=='traj' and a.ndim==3 and a.shape[-2:]==(4,4):
       row['homogeneous_bottom_row_ok']=bool(np.allclose(a[:,3,:],np.array([0,0,0,1]),atol=1e-5))
       row['rotation_orthogonality_max']=float(np.max(np.abs(a[:,:3,:3]@np.transpose(a[:,:3,:3],(0,2,1))-np.eye(3))))
     except Exception as e:row['array_validation_error']=str(e);bad.append(m.name)
    elif m.name.endswith(('.txt','.json')):
     try:row['native_text']=data.decode('utf-8')
     except UnicodeDecodeError:row['text_error']=True;bad.append(m.name)
    jf.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')
    index[Path(m.name).stem]=m.name
    if len(examples)<3:examples.append({k:v for k,v in row.items() if k!='native_text'})
  indexes[family]=index;summary[family]={'files':count,'bytes':bytes_,'bad_files':bad,'examples':examples}
 common=set(indexes.get('traj',{}))&set(indexes.get('caption',{}))
 with open(out/'joined_native_records.jsonl','w') as f:
  for key in sorted(common):
   f.write(json.dumps({'record_id':key,'source':'et','modalities':{name:{'archive':name+'.tar.gz','member':idx[key]} for name,idx in indexes.items() if key in idx},'label_origin':'source_machine_extracted','human_gold':False,'operator_utility':None,'capture_time_intent':None,'commercial_eligibility':'unresolved'})+'\n')
 summary['joined_trajectory_caption']=len(common)
 write_json(root/'SUMMARY.json',summary);print('CC17_SUMMARY '+json.dumps(summary),flush=True)

def acam_videos(root,kind):
 out=root/'acam'
 archive='real_videos.zip' if kind=='real' else 'syn_videos.zip'
 acquire_files('acam',out,lambda v:v['path']==archive or v['path'].endswith(('.jsonl','.md')))
 p=out/'native'/archive;summary={'archive':archive,'videos':0,'other_files':0,'invalid':[],'official_split':'test','license_scope':'CC-BY-NC-SA-4.0; research evaluation only; not a training pool'}
 tmp=root/'temp';tmp.mkdir(exist_ok=True)
 with zipfile.ZipFile(p) as z,open(out/(kind+'_media_index.jsonl'),'w') as jf:
  for n in z.namelist():
   if n.endswith('/'):continue
   if n.startswith('/') or '..' in Path(n).parts:raise ValueError('unsafe archive member')
   data=z.read(n);row={'member':n,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
   if n.lower().endswith(('.mp4','.mov','.avi','.mkv','.webm','.gif')):
    summary['videos']+=1;v=tmp/('clip'+Path(n).suffix);v.write_bytes(data)
    r=subprocess.run(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,nb_frames,r_frame_rate,duration:format=duration','-of','json',str(v)],capture_output=True,text=True,timeout=25)
    if r.returncode or not json.loads(r.stdout or '{}').get('streams'):summary['invalid'].append(n);row['decoded_header']=False
    else:row['decoded_header']=True;row['probe']=json.loads(r.stdout)
    v.unlink()
   else:summary['other_files']+=1
   jf.write(json.dumps(row)+'\n')
 tmp.rmdir();write_json(root/'SUMMARY.json',summary);print('CC17_SUMMARY '+json.dumps(summary),flush=True)

def pack(root,mode):
 files=[]
 for p in sorted(root.rglob('*')):
  if p.is_file():files.append({'path':str(p.relative_to(root)),'bytes':p.stat().st_size,'sha256':digest(p)})
 write_json(root/'PAYLOAD_MANIFEST.json',{'mode':mode,'files':files,'model_calls':0,'training_runs':0})
 delivery=Path('delivery');delivery.mkdir(exist_ok=True)
 plain=Path(mode+'.tar')
 with tarfile.open(plain,'w') as t:
  for p in sorted(root.rglob('*')):
   if p.is_file():t.add(p,arcname=str(p.relative_to(root)),recursive=False)
 out=delivery/(mode+'.tar.cms')
 subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',str(plain),'-out',str(out),'-outform','DER','tools/dataset/cc17/transport_public.pem'],check=True)
 write_json(delivery/(mode+'.transport.json'),{'plaintext_sha256':digest(plain),'plaintext_bytes':plain.stat().st_size,'encrypted_sha256':digest(out),'encrypted_bytes':out.stat().st_size,'files':len(files),'public_payload':False})
 plain.unlink()
 print('CC17_TRANSPORT '+json.dumps({'mode':mode,'files':len(files),'encrypted_bytes':out.stat().st_size,'sha256':digest(out)}),flush=True)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('mode',choices=['metadata','et-core','acam-real','acam-syn']);args=ap.parse_args()
 root=Path('work')/args.mode;root.mkdir(parents=True,exist_ok=True)
 if args.mode=='metadata':inspect_metadata(root)
 elif args.mode=='et-core':et_core(root)
 else:acam_videos(root,args.mode.split('-')[1])
 pack(root,args.mode)
if __name__=='__main__':main()
