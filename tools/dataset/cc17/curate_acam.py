"""Complete released ACaM test annotations and learning-sized evaluation media.
Official test data never enter training. Native archives are acquired and every
member CRC checked. Source hashes and all native annotations are retained.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,json,subprocess,zipfile,shutil
from pathlib import Path
from acquire import acquire_files,write_json,digest
from release_pack import package
root=Path('curated/acam');root.mkdir(parents=True,exist_ok=True)
receipts=acquire_files('acam',root,lambda v:v['path'] in ('real_videos.zip','syn_videos.zip') or v['path'].endswith(('.jsonl','.md')))
assert all(r['status']=='downloaded' for r in receipts)
cache=Path('acam_source_videos');cache.mkdir(exist_ok=True)
media={};other=[]
for archive in sorted((root/'native').glob('*.zip')):
 with zipfile.ZipFile(archive) as z:
  for info in z.infolist():
   if info.is_dir():continue
   name=info.filename
   if name.startswith('/') or '..' in Path(name).parts:raise ValueError('unsafe member path')
   data=z.read(info)
   if not name.lower().endswith(('.mp4','.mov','.mkv','.avi','.webm')):
    other.append({'archive':archive.name,'member':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()});continue
   identifier=hashlib.sha256((archive.name+':'+name).encode()).hexdigest()
   dest=cache/(identifier+Path(name).suffix);dest.write_bytes(data)
   media[identifier]={'asset_id':identifier,'native_archive':archive.name,'native_member':name,'native_sha256':hashlib.sha256(data).hexdigest(),'native_bytes':len(data),'local_source':str(dest),'official_split':'test'}
 print('ACAM_CRC_COMPLETE',archive.name,len(media),flush=True)
def work(row):
 row=dict(row);src=Path(row.pop('local_source'))
 try:
  r=subprocess.run(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,avg_frame_rate,duration:format=duration','-of','json',str(src)],capture_output=True,text=True,timeout=30)
  p=json.loads(r.stdout or '{}');assert r.returncode==0 and p.get('streams')
  duration=float(p.get('format',{}).get('duration') or p['streams'][0].get('duration'));assert 0<duration<1800
  dest=root/'media'/(row['asset_id']+'.mp4');dest.parent.mkdir(exist_ok=True)
  filt=f'fps={16/duration:.12g}:start_time=0,scale=320:320:force_original_aspect_ratio=decrease:force_divisible_by=2'
  q=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(src),'-an','-vf',filt,'-frames:v','16','-c:v','libx264','-preset','veryfast','-crf','20','-threads','1','-pix_fmt','yuv420p','-movflags','+faststart',str(dest)],capture_output=True,timeout=180)
  assert q.returncode==0,'derivative encode failed'
  v=subprocess.run(['ffprobe','-v','error','-count_frames','-select_streams','v:0','-show_entries','stream=width,height,nb_read_frames,avg_frame_rate:format=duration','-of','json',str(dest)],capture_output=True,text=True,timeout=30)
  d=json.loads(v.stdout);n=int(d['streams'][0]['nb_read_frames']);assert 2<=n<=16
  check=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(dest),'-f','null','-'],capture_output=True,timeout=30);assert check.returncode==0
  row.update(status='ready',path=str(dest.relative_to(root)),sha256=digest(dest),bytes=dest.stat().st_size,native_probe=p,derivative_probe=d,valid_frames=n,source_sampling_interval_s=duration/16,source_sampling_start_s=0.,all_derivative_frames_decoded=True,recipe='fps=16/source_duration; max320 aspect-preserved; H264 CRF20; audio removed')
 except Exception as e:row.update(status='failed',error=type(e).__name__+': '+str(e))
 return row
with cf.ThreadPoolExecutor(max_workers=8) as pool:result=list(pool.map(work,media.values()))
media={r['asset_id']:r for r in result}
with open(root/'media_manifest.jsonl','w') as f:
 for row in sorted(result,key=lambda r:r['asset_id']):f.write(json.dumps(row,allow_nan=False)+'\n')
by_path=collections.defaultdict(list)
for row in result:
 n=row['native_member'];by_path[n].append(row['asset_id']);prefix='real_videos/' if 'real' in row['native_archive'] else 'syn_videos/'
 if not n.startswith(prefix):by_path[prefix+n].append(row['asset_id'])
# Exact path first; a suffix is admissible only when it resolves uniquely.
counts=collections.Counter();unmatched=[];records=[];categories=collections.Counter();badanswers=[]
for file in sorted((root/'native').glob('*.jsonl')):
 for i,line in enumerate(file.read_text().splitlines()):
  if not line.strip():continue
  r=json.loads(line);n=r['image'];matches=set(by_path.get(n,[]))
  if not matches:matches={v['asset_id'] for v in result if n.endswith('/'+v['native_member']) or v['native_member'].endswith('/'+n)}
  answer=r.get('correct_answer',r.get('label'));opts=r.get('options');valid=answer in opts if opts else answer in ('Yes','No')
  if not valid:badanswers.append({'file':file.name,'row':i,'answer':answer})
  if len(matches)!=1:unmatched.append({'file':file.name,'row':i,'media_path':n,'matches':len(matches)});continue
  mid=next(iter(matches));m=media[mid]
  row={'schema':'cc17.camera_motion_test.v1','record_id':file.stem+':'+str(i),'official_split':'test','use':'evaluation_only','source_annotation_file':file.name,'source_row_index':i,'native_annotation':r,'media_asset_id':mid,'input':{'video_path':m.get('path'),'question':r['question'],'options':opts},'target':{'answer':answer,'camera_motion':r.get('camera movement',r.get('camera_motion')),'known':valid},'media_ready':m['status']=='ready','training_eligible':False,'license_scope':'CC-BY-NC-SA-4.0; noncommercial evaluation; preserve attribution','operator_utility':None,'capture_time_user_intent':None}
  records.append(row);counts[file.name]+=1;categories.update(row['target']['camera_motion'] or [])
with open(root/'records.jsonl','w') as f:
 for row in records:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')
write_json(root/'unmatched.json',unmatched);write_json(root/'invalid_answers.json',badanswers);write_json(root/'other_native_files.json',other)
summary={'annotation_rows':sum(counts.values())+len(unmatched),'joined_rows':len(records),'joined_rows_by_file':dict(counts),'unique_native_video_members':len(media),'unique_native_video_hashes':len({r['native_sha256'] for r in result}),'unique_referenced_assets':len({r['media_asset_id'] for r in records}),'ready_media':sum(r['status']=='ready' for r in result),'invalid_media':sum(r['status']!='ready' for r in result),'all_derivative_frames_decoded':sum(r.get('all_derivative_frames_decoded') is True for r in result),'unmatched_rows':len(unmatched),'invalid_answer_keys':len(badanswers),'motion_labels':dict(categories),'native_zip_bytes':sum(r['bytes'] for r in receipts if r['source_path'].endswith('.zip')),'source_archive_crc_checked':True,'model_calls':0,'train_rows':0}
write_json(root/'QA.json',summary)
assert not unmatched and not badanswers and summary['invalid_media']==0,summary
# Preserve source identity receipts; bulk native archives remain in the earlier encrypted
# acquisition artifacts and at their pinned upstream URLs, not in this compact release.
for p in (root/'native').glob('*.zip'):p.unlink()
shutil.rmtree(cache)
(root/'README_RU.txt').write_text('ACaM: все опубликованные тестовые задания real/synthetic/binary с разрешёнными ссылками на проверенные native-видеофайлы.\nВ этой компактной поставке видео — производные до 16 кадров, max320, H264 CRF20. Их нельзя выдавать за неизменённые native-видео или напрямую сравнивать результаты с оригинальным full-video benchmark без оговорки о preprocessing.\nОба native ZIP полностью получены и проверены по CRC; SHA, размеры и pinned URL сохранены. Native ZIP находятся в исходных зашифрованных acquisition-артефактах, не в этой компактной поставке.\nРазбиение official test сохранено: ни один пример не допускается в обучение. Синтетические видео источника не являются физическим ground truth нашего симулятора.\n')
print('CC17_CURATED_SUMMARY '+json.dumps(summary),flush=True)
package(root,'acam-curated-complete-test')
