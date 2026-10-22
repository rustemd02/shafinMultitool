"""Private research acquisition of the complete released DataDoP processed corpus.
No raw YouTube download; no inference; no commercial admission. Source README
contains conflicting CC-BY and research/no-redistribution provisions, retained.
Native ZIP bytes are encrypted immediately and never exposed as public artifacts.
"""
import argparse,hashlib,io,json,re,subprocess,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
from acquire import SOURCES,source_info,download,write_json,digest,pack
SOURCES['datadop']=('Dubhe-zmc/DataDoP','e726e57debb8675bbfdf0919e6f7edb79d98fec6')
ap=argparse.ArgumentParser();ap.add_argument('--shard',type=int,required=True);ap.add_argument('--shards',type=int,default=8);args=ap.parse_args()
mode=f'datadop-{args.shard:02d}';root=Path('work')/mode;root.mkdir(parents=True,exist_ok=True)
repo,rev,tree=source_info('datadop',root)
archives=sorted([v for v in tree if v['path'].endswith('.zip')],key=lambda v:v['path'])
chosen=[v for i,v in enumerate(archives) if i%args.shards==args.shard]
for v in tree:
 if v['path'].endswith(('.md','.txt')):
  download(f'https://huggingface.co/datasets/{repo}/resolve/{rev}/'+v['path'],root/'native_metadata'/v['path'],v.get('size'),v.get('lfs',{}).get('oid'))
records={};archive_receipts=[];bad=[];members=0;native_bytes=0
encdir=Path('native_delivery');encdir.mkdir(exist_ok=True)
for spec in chosen:
 archive=Path('temp_'+Path(spec['path']).name)
 receipt=download(f'https://huggingface.co/datasets/{repo}/resolve/{rev}/'+spec['path'],archive,spec.get('size'),spec.get('lfs',{}).get('oid'))
 receipt['source_path']=spec['path'];receipt.pop('path',None)
 with zipfile.ZipFile(archive) as z,open(root/(archive.stem+'_members.jsonl'),'w') as jf:
  for info in z.infolist():
   if info.is_dir():continue
   n=info.filename
   if n.startswith('/') or '..' in Path(n).parts:raise ValueError('unsafe archive path')
   data=z.read(info);members+=1;native_bytes+=len(data)
   row={'archive':spec['path'],'member':n,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
   match=re.search(r'([01]_\d+)/((?:shot_)\d+)_',n)
   if match:
    key=match.group(1)+'/'+match.group(2)
    record=records.setdefault(key,{'record_id':key,'source_video_id':match.group(1),'source_revision':rev,'source_archive':spec['path'],'native_modalities':{},'label_origin':'source_machine_extracted_trajectory_and_generated_caption','capture_time_user_intent':None,'operator_utility':None,'commercial_use':'rights_conflict_quarantine'})
    kind=None
    for suffix,label in [('_caption.json','caption'),('_rgb.png','rgb'),('_depth.npy','depth'),('_intrinsics.txt','intrinsics'),('_traj.txt','trajectory_raw'),('_transforms_cleaning.json','trajectory_clean')]:
     if n.endswith(suffix):kind=label;break
    if kind:
     record['native_modalities'][kind]={'archive':spec['path'],'member':n,'sha256':row['sha256']}
     try:
      if kind=='caption':record['native_caption']=json.loads(data)
      elif kind=='trajectory_clean':
       t=json.loads(data);record['trajectory_schema_keys']=list(t) if isinstance(t,dict) else ['list'];record['native_modalities'][kind]['valid_json']=True
       if isinstance(t,dict):
        fs=t.get('frames');record['trajectory_frames']=len(fs) if isinstance(fs,list) else None
        if isinstance(fs,list) and fs and isinstance(fs[0],dict) and 'transform_matrix' in fs[0]:
         a=np.asarray([f['transform_matrix'] for f in fs],dtype=float)
         record['trajectory_finite']=bool(np.isfinite(a).all());record['trajectory_shape']=list(a.shape)
      elif kind=='depth':
       a=np.load(io.BytesIO(data),allow_pickle=False);record['depth_shape']=list(a.shape);record['depth_finite']=bool(np.isfinite(a).all());record['depth_nonfinite_count']=int(np.sum(~np.isfinite(a)))
      elif kind=='rgb':
       with Image.open(io.BytesIO(data)) as im:record['rgb_size']=list(im.size);im.verify()
     except Exception as e:record.setdefault('validation_errors',[]).append({'modality':kind,'error':str(e)});bad.append({'record_id':key,'modality':kind,'error':str(e)})
   jf.write(json.dumps(row)+'\n')
 encrypted=encdir/(Path(spec['path']).name+'.cms')
 subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',str(archive),'-out',str(encrypted),'-outform','DER','tools/dataset/cc17/transport_public.pem'],check=True)
 receipt.update(encrypted_file=encrypted.name,encrypted_bytes=encrypted.stat().st_size,encrypted_sha256=digest(encrypted));archive_receipts.append(receipt);archive.unlink()
 print('NATIVE_ARCHIVE_ACQUIRED',spec['path'],receipt['bytes'],'records_so_far',len(records),flush=True)
required={'caption','rgb','depth','intrinsics','trajectory_raw','trajectory_clean'}
complete=0
with open(root/'records.jsonl','w') as f:
 for key,row in sorted(records.items()):
  row['missing_modalities']=sorted(required-set(row['native_modalities']));row['all_six_modalities_present']=not row['missing_modalities'];complete+=int(row['all_six_modalities_present'])
  f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')
summary={'shard':args.shard,'shards':args.shards,'all_source_archives':len(archives),'acquired_archives':len(archive_receipts),'native_zip_bytes':sum(r['bytes'] for r in archive_receipts),'native_members':members,'native_uncompressed_bytes':native_bytes,'shot_records':len(records),'complete_six_modality_records':complete,'source_video_ids':len({r['source_video_id'] for r in records.values()}),'validation_errors':len(bad),'operator_utility_labels':0,'human_capture_time_intent_labels':0}
write_json(root/'archive_receipts.json',archive_receipts);write_json(root/'validation_errors.json',bad);write_json(root/'SUMMARY.json',summary)
print('CC17_SUMMARY '+json.dumps(summary),flush=True);pack(root,mode)
