"""Data-only complete Rapidata movement-adherence release.
Every native comparison is retained; every referenced media asset is acquired.
Learning media are documented 16-frame / max320 derivatives, never source raw.
Demographic fields and generator identities are excluded from learning inputs.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,json,math,subprocess
from pathlib import Path
from urllib.parse import urlparse
import numpy as np
import pyarrow.parquet as pq
from PIL import Image,ImageOps
from acquire import acquire_files,download,write_json,digest
from release_pack import package
root=Path('curated/rapidata');root.mkdir(parents=True,exist_ok=True)
receipts=acquire_files('rapidata',root,lambda v:v['path'].endswith(('.parquet','.md')))
assert all(r['status']=='downloaded' for r in receipts)
rows=[]
for p in sorted((root/'native/data').glob('*.parquet')):rows.extend(pq.read_table(p).to_pylist())
def aid(u):return hashlib.sha256(u.encode()).hexdigest()
assets={}
for i,row in enumerate(rows):
 for role in ('input_image','reference_gif','video1','video2'):
  u=row[role];assert u.startswith('https://assets.rapidata.ai/')
  a=assets.setdefault(u,{'asset_id':aid(u),'roles':set(),'row_indices':[]});a['roles'].add(role);a['row_indices'].append(i)
images=sorted(u for u,a in assets.items() if 'input_image' in a['roles'])
parents={u:u for u in images}
def find(u):
 while parents[u]!=u:parents[u]=parents[parents[u]];u=parents[u]
 return u
def union(a,b):
 x,y=find(a),find(b)
 if x!=y:parents[max(x,y)]=min(x,y)
img_info={}
for u in images:
 dest=root/'input_images'/(aid(u)+Path(urlparse(u).path).suffix)
 rec=download(u,dest)
 with Image.open(dest) as im:
  im=ImageOps.exif_transpose(im).convert('RGB');pixels=np.asarray(im);small=np.asarray(im.resize((9,8)).convert('L'));bits=(small[:,1:]>small[:,:-1]).reshape(-1)
  dh=int(''.join('1' if b else '0' for b in bits),2)
  ph=hashlib.sha256(str(im.size).encode()+pixels.tobytes()).hexdigest()
 img_info[u]={'native_sha256':rec['sha256'],'pixel_sha256':ph,'dhash':dh,'path':str(dest.relative_to(root))}
for i,u in enumerate(images):
 for v in images[i+1:]:
  if img_info[u]['pixel_sha256']==img_info[v]['pixel_sha256'] or (img_info[u]['dhash']^img_info[v]['dhash']).bit_count()<=6:union(u,v)
# A reused candidate video is not allowed to connect different splits.
video_inputs=collections.defaultdict(set)
for row in rows:
 for k in ('video1','video2'):video_inputs[row[k]].add(row['input_image'])
for us in video_inputs.values():
 us=sorted(us)
 for u in us[1:]:union(us[0],u)
cache=Path('raw_cache');cache.mkdir(exist_ok=True)
def work(item):
 u,meta=item;identifier=meta['asset_id'];roles=sorted(meta['roles']);result={'asset_id':identifier,'source_url':u,'roles':roles}
 try:
  src=cache/(identifier+Path(urlparse(u).path).suffix)
  r=download(u,src);result.update(native_bytes=r['bytes'],native_sha256=r['sha256'])
  if 'input_image' in roles:
   result.update(status='ready',path=img_info[u]['path'],transformed=False);src.unlink();return result
  probe=subprocess.run(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,avg_frame_rate,duration:format=duration','-of','json',str(src)],capture_output=True,text=True,timeout=45)
  p=json.loads(probe.stdout or '{}');assert probe.returncode==0 and p.get('streams')
  duration=float(p.get('format',{}).get('duration') or p['streams'][0].get('duration'));assert 0<duration<600
  dest=root/'media'/(identifier+'.mp4');dest.parent.mkdir(exist_ok=True)
  filt=f'fps={16/duration:.12g}:start_time=0,scale=320:320:force_original_aspect_ratio=decrease:force_divisible_by=2'
  cmd=['ffmpeg','-v','error','-threads','1','-i',str(src),'-an','-vf',filt,'-frames:v','16','-c:v','libx264','-preset','veryfast','-crf','20','-threads','1','-pix_fmt','yuv420p','-movflags','+faststart',str(dest)]
  enc=subprocess.run(cmd,capture_output=True,timeout=120)
  if enc.returncode:raise ValueError('video derivative encoding failed')
  check=subprocess.run(['ffprobe','-v','error','-count_frames','-select_streams','v:0','-show_entries','stream=width,height,nb_read_frames,avg_frame_rate:format=duration','-of','json',str(dest)],capture_output=True,text=True,timeout=45)
  q=json.loads(check.stdout or '{}');stream=q['streams'][0];n=int(stream['nb_read_frames']);assert 2<=n<=16
  decode=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(dest),'-f','null','-'],capture_output=True,timeout=45)
  if decode.returncode:raise ValueError('full derivative frame decoding failed')
  result.update(status='ready',path=str(dest.relative_to(root)),sha256=digest(dest),bytes=dest.stat().st_size,native_probe=p,derivative_probe=q,valid_frames=n,source_sampling_interval_s=duration/16,source_sampling_start_s=0.,full_derivative_decode=True,recipe={'max_spatial_size':320,'max_frames':16,'fps':'16 / source_duration','codec':'h264','crf':20,'aspect_preserved':True,'audio_removed':True})
  if 'reference_gif' in roles:
   ref=root/'native_reference_gifs'/src.name;ref.parent.mkdir(exist_ok=True);src.replace(ref);result['native_reference_path']=str(ref.relative_to(root))
  else:src.unlink()
 except Exception as e:result.update(status='failed',error=type(e).__name__+': '+str(e))
 return result
media={};done=0
with cf.ThreadPoolExecutor(max_workers=8) as pool,open(root/'media_manifest.jsonl','w') as f:
 for row in pool.map(work,sorted(assets.items())):
  media[row['asset_id']]=row;f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n');f.flush();done+=1
  if done%500==0:print('CURATED_MEDIA',done,len(assets),flush=True)
# Merge exact native-video duplicates before assigning the final split.
sha_inputs=collections.defaultdict(set)
for u,us in video_inputs.items():
 m=media[aid(u)]
 if m['status']=='ready':sha_inputs[m['native_sha256']].update(us)
for us in sha_inputs.values():
 us=sorted(us)
 for u in us[1:]:union(us[0],u)
groups=sorted({find(u) for u in images},key=lambda u:hashlib.sha256(('cc17-rapidata-split:'+u).encode()).hexdigest())
n=len(groups);nval=max(1,round(n*.2));ntest=nval
if n<3:raise ValueError('too few independent source groups for three splits')
group_split={g:('train' if i<n-nval-ntest else 'validation' if i<n-ntest else 'test') for i,g in enumerate(groups)}
counts=collections.Counter();missing=0;votes=0;seen_pairs=set();invalid=0;weighted_error=0
with open(root/'comparisons.jsonl','w') as f,open(root/'excluded_comparisons.jsonl','w') as q:
 for i,row in enumerate(rows):
  a=float(row['weighted_results_video1_movement']);b=float(row['weighted_results_video2_movement']);den=a+b
  native_votes=json.loads(row['detailed_results_movement']);votes+=len(native_votes)
  weights={'A':0.,'B':0.}
  for vote in native_votes:
   choice=vote.get('vote',vote.get('votedFor',vote.get('answer')))
   if choice in weights:weights[choice]+=float(vote.get('userScore',0))
  if sum(weights.values())>0:weighted_error=max(weighted_error,abs(weights['A']-a),abs(weights['B']-b))
  target_valid=math.isfinite(a) and math.isfinite(b) and a>=0 and b>=0 and den>0
  invalid+=int(not target_valid)
  ids=[aid(row[k]) for k in ('input_image','reference_gif','video1','video2')]
  media_complete=all(media[k]['status']=='ready' for k in ids)
  split=group_split[find(row['input_image'])]
  record={'schema':'cc17.motion_adherence_pair.v1','id':f'rapidata:{i:06d}','split':split,'origin_group':aid(find(row['input_image'])),'input':{'instruction':row['prompt'],'input_image_asset':ids[0],'reference_motion_asset':ids[1],'candidate_video_assets':ids[2:]},'target':{'weighted_share_A':a/den if target_valid else None,'weighted_share_B':b/den if target_valid else None,'native_weight_A':a,'native_weight_B':b,'vote_events':len(native_votes),'preferred':'A' if a>b else 'B' if b>a else 'tie','known':target_valid},'native_row_index':i,'native_row_sha256':hashlib.sha256(json.dumps(row,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest(),'media_complete':media_complete,'task':'evaluate_execution_of_given_camera_motion','real_operator_utility':None,'human_capture_intent':None,'training_authorized':False,'commercial_media_eligibility':'unresolved_provider_and_source_image_terms','human_gold_scope':'pairwise_motion_adherence_only'}
  pair=(ids[0],row['prompt'],*sorted(ids[2:]));assert pair not in seen_pairs;seen_pairs.add(pair)
  if media_complete and target_valid:f.write(json.dumps(record,ensure_ascii=False,allow_nan=False)+'\n');counts[split]+=1
  else:q.write(json.dumps(record,ensure_ascii=False,allow_nan=False)+'\n');missing+=1
summary={'native_comparisons':len(rows),'native_human_vote_events':votes,'unique_source_image_urls':len(images),'unique_source_image_pixels':len({v['pixel_sha256'] for v in img_info.values()}),'conservative_content_groups':n,'split_groups':dict(collections.Counter(group_split.values())),'split_complete_comparisons':dict(counts),'total_media_urls':len(media),'media_ready':sum(m['status']=='ready' for m in media.values()),'media_failed':sum(m['status']!='ready' for m in media.values()),'full_derivative_decode_checked':sum(m.get('full_derivative_decode') is True for m in media.values()),'native_media_bytes':sum(m.get('native_bytes',0) for m in media.values()),'derivative_media_bytes':sum(m.get('bytes',0) for m in media.values()),'excluded_comparisons':missing,'invalid_native_targets':invalid,'duplicate_unordered_pairs':0,'cross_split_reused_video_or_exact_native_hash':0,'demographic_input_fields':0,'generator_identity_input_fields':0,'model_calls':0,'human_operator_utility_labels':0}
write_json(root/'QA.json',summary);write_json(root/'image_groups.json',{u:{**img_info[u],'group':aid(find(u)),'split':group_split[find(u)]} for u in images})
(root/'README_RU.txt').write_text('Все исходные сравнения и их native Parquet сохранены. Учебные видео: до 16 кадров, размер не более 320 px, H.264 CRF20; это явно производные файлы, не оригиналы. Исходные SHA-256 и URL сохранены.\nРазбиение целыми группами исходных изображений объединяет точные и близкие изображения, общие видео и одинаковые native-видеобайты.\nМетки оценивают выполнение заданного движения в сгенерированном ролике. Они не измеряют полезность совета реальному оператору. Демография и имена генераторов не входят в учебные признаки.\nПрименимость лицензии CC BY к аннотациям не переносится автоматически на медиа. Обучение не запускалось.\n')
print('CC17_CURATED_SUMMARY '+json.dumps(summary),flush=True)
package(root,'rapidata-curated-complete')
