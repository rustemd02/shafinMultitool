"""Collect all public media referenced by the pinned Rapidata native comparison table.
Raw votes are retained only in the encrypted metadata package; demographics never
become model inputs. This is movement adherence, not real operator utility.
"""
import argparse, concurrent.futures as cf, hashlib, json, subprocess
from pathlib import Path
from urllib.parse import urlparse
import pyarrow.parquet as pq
from acquire import acquire_files,download,write_json,pack

ap=argparse.ArgumentParser();ap.add_argument('--shard',type=int,required=True);ap.add_argument('--shards',type=int,default=4);args=ap.parse_args()
mode=f'rapidata-media-{args.shard:02d}';root=Path('work')/mode;out=root/'rapidata';out.mkdir(parents=True,exist_ok=True)
acquire_files('rapidata',out,lambda v:v['path'].endswith(('.parquet','.md')))
rows=[]
for p in sorted((out/'native/data').glob('*.parquet')):rows.extend(pq.read_table(p).to_pylist())
assets={}
for i,row in enumerate(rows):
 for col in ('reference_gif','input_image','video1','video2'):
  u=row.get(col)
  if isinstance(u,str) and u.startswith('https://assets.rapidata.ai/'):
   a=assets.setdefault(u,{'roles':set(),'row_indices':[]});a['roles'].add(col);a['row_indices'].append(i)
all_assets=sorted(assets)
chosen=[u for u in all_assets if int(hashlib.sha256(u.encode()).hexdigest()[:8],16)%args.shards==args.shard]

def worker(u):
 aid=hashlib.sha256(u.encode()).hexdigest();ext=Path(urlparse(u).path).suffix.lower()
 dest=out/'media'/(aid+ext)
 row={'asset_id':aid,'source_url':u,'roles':sorted(assets[u]['roles']),'row_indices':assets[u]['row_indices']}
 try:
  receipt=download(u,dest);row.update(receipt);row['path']=str(dest.relative_to(root));row['status']='downloaded'
  if ext in ('.mp4','.mov','.webm','.gif'):
   r=subprocess.run(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,nb_frames,r_frame_rate,duration:format=duration','-of','json',str(dest)],capture_output=True,text=True,timeout=30)
   p=json.loads(r.stdout or '{}');row['header_valid']=r.returncode==0 and bool(p.get('streams'));row['probe']=p
   if row['header_valid']:
    frame=out/'preview_frames'/(aid+'.jpg');frame.parent.mkdir(exist_ok=True)
    q=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(dest),'-frames:v','1','-vf','scale=320:320:force_original_aspect_ratio=decrease','-q:v','3',str(frame)],capture_output=True,timeout=45)
    row['first_frame_decoded']=q.returncode==0 and frame.exists()
  else:
   from PIL import Image
   with Image.open(dest) as im:im.verify()
   row['image_valid']=True
 except Exception as e:row['status']='failed';row['error']=type(e).__name__+': '+str(e).split('?')[0]
 return row
receipts=[]
with cf.ThreadPoolExecutor(max_workers=8) as pool,open(out/'media_receipts.jsonl','w') as f:
 for row in pool.map(worker,chosen):
  receipts.append(row);f.write(json.dumps(row,ensure_ascii=False)+'\n');f.flush()
  if len(receipts)%250==0:print('MEDIA_PROGRESS',args.shard,len(receipts),len(chosen),flush=True)
summary={'source_rows':len(rows),'all_unique_urls':len(all_assets),'shard':args.shard,'shards':args.shards,'expected_assets':len(chosen),'downloaded_assets':sum(r['status']=='downloaded' for r in receipts),'failed_assets':sum(r['status']=='failed' for r in receipts),'bytes':sum(r.get('bytes',0) for r in receipts),'invalid_video_headers':sum(r.get('header_valid') is False for r in receipts),'decoded_first_frames':sum(r.get('first_frame_decoded') is True for r in receipts),'task':'human_comparison_of_prompted_generated_camera_movement','operator_utility_labels':0}
write_json(root/'SUMMARY.json',summary);print('CC17_SUMMARY '+json.dumps(summary),flush=True);pack(root,mode)
