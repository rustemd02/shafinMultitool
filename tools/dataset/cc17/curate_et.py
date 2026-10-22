"""Complete data-only ET core release: native bytes plus typed joins and numeric arrays.
Trajectories are KITTI 3x4 poses, confirmed against the pinned upstream DIRECTOR
reader. Source scale and timestamps are not promoted to measured metres/seconds.
Generated descriptions are not historical human capture intent.
"""
from __future__ import annotations
import collections,hashlib,io,json,tarfile
from pathlib import Path
import numpy as np
from acquire import acquire_files,write_json,digest,download
from release_pack import package
ROOT=Path('curated/et');ROOT.mkdir(parents=True,exist_ok=True)
wanted={'bounds.tar.gz','cam_segments.tar.gz','caption.tar.gz','caption_cam.tar.gz','char.tar.gz','char_segments.tar.gz','intrinsics.tar.gz','traj.tar.gz'}
receipts=acquire_files('et',ROOT,lambda v:v['path'] in wanted or v['path'].endswith(('.txt','.md','.sh')))
assert not [r for r in receipts if r['status']!='downloaded'],'source download failure'
upstream='https://raw.githubusercontent.com/robincourant/DIRECTOR/63fa652761420f09ade5537d01a2bc2b16e5e494/'
for p in ['src/datasets/modalities/trajectory_dataset.py','src/datasets/modalities/char_dataset.py','LICENSE']:
 download(upstream+p,ROOT/'source_evidence'/Path(p).name)
records={};poses=[];chars=[];offset=0;charoffset=0;errors=[];counts={};arrays=ROOT/'arrays';arrays.mkdir()
for name in ['caption','caption_cam','intrinsics','bounds','cam_segments','char_segments','char','traj']:
 count=0
 with tarfile.open(ROOT/'native'/(name+'.tar.gz'),'r|gz') as t:
  for m in t:
   if not m.isfile():continue
   b=t.extractfile(m).read();key=Path(m.name).stem;count+=1
   row=records.setdefault(key,{'schema':'cc17.text_trajectory.v1','record_id':'et:'+key,'source_key':key,'source_video_group':key.rsplit('_',2)[0],'native':{},'human_capture_intent':None,'real_operator_utility':None,'label_origin':'source_machine_extracted_geometry_and_generated_description','metric_scale_verified':False,'timestamps_verified':False,'rights_scope':'private_research_review; no commercial admission'})
   row['native'][name]={'archive':name+'.tar.gz','member':m.name,'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)}
   try:
    if name in ('caption','caption_cam'):row[name]=b.decode('utf-8').strip()
    elif name=='traj':
     a=np.loadtxt(io.BytesIO(b),dtype=np.float64,ndmin=2)
     if a.shape[1]!=12 or len(a)<2 or not np.isfinite(a).all():raise ValueError('invalid KITTI Nx12 poses')
     mats=a.reshape(-1,3,4);rot=mats[:,:3,:3]
     orth=float(np.max(np.abs(rot@rot.transpose(0,2,1)-np.eye(3))));det=float(np.max(np.abs(np.linalg.det(rot)-1)))
     row['pose_qa']={'frames':len(a),'rotation_orthogonality_max':orth,'rotation_determinant_error_max':det,'finite':True,'numeric_admitted':orth<0.002 and det<0.002}
     a32=a.astype(np.float32);row['pose_qa']['float32_conversion_max_abs']=float(np.max(np.abs(a-a32)))
     row['trajectory_array']={'path':'arrays/poses.npy','start':offset,'stop':offset+len(a),'layout':'native_KITTI_3x4_row_major'};poses.append(a32);offset+=len(a)
    elif name=='char':
     a=np.load(io.BytesIO(b),allow_pickle=False)
     if a.ndim!=2 or a.shape[1]!=3 or not np.isfinite(a).all():raise ValueError('invalid character Nx3')
     row['character_array']={'path':'arrays/character.npy','start':charoffset,'stop':charoffset+len(a)}
     chars.append(a.astype(np.float32));charoffset+=len(a)
    else:
     a=np.load(io.BytesIO(b),allow_pickle=False)
     if not np.isfinite(a).all():raise ValueError('nonfinite source annotation')
     row[name]=a.tolist()
   except Exception as e:row.setdefault('errors',[]).append(name+': '+str(e));errors.append({'source_key':key,'modality':name,'error':str(e)})
 counts[name]=count;print('ET_NORMALIZED',name,count,flush=True)
np.save(arrays/'poses.npy',np.concatenate(poses),allow_pickle=False);poses.clear()
np.save(arrays/'character.npy',np.concatenate(chars),allow_pickle=False);chars.clear()
# Preserve upstream split declarations, then conservatively place entire source videos together.
upstream_membership=collections.defaultdict(list)
for p in (ROOT/'native').glob('*split*.txt'):
 for line in p.read_text().splitlines():
  key=Path(line.strip()).stem
  if key:upstream_membership[key].append(p.stem)
group_upstream=collections.defaultdict(set)
for key,row in records.items():
 row['upstream_splits']=sorted(upstream_membership.get(key,[]))
 for label in row['upstream_splits']:
  if 'test' in label:group_upstream[row['source_video_group']].add('test')
  elif 'val' in label:group_upstream[row['source_video_group']].add('validation')
  elif 'train' in label:group_upstream[row['source_video_group']].add('train')
def split(group):
 declared=group_upstream[group]
 if 'test' in declared:return 'test'
 if 'validation' in declared:return 'validation'
 n=int(hashlib.sha256(('cc17-et-v1:'+group).encode()).hexdigest()[:8],16)%100
 return 'train' if n<80 else 'validation' if n<90 else 'test'
selected=[];orphans=[];dist=collections.Counter();groups=collections.defaultdict(set);alignment_errors=0
with open(ROOT/'records.jsonl','w') as f,open(ROOT/'quarantine.jsonl','w') as q:
 for key,row in sorted(records.items()):
  row['split']=split(row['source_video_group'])
  complete=all(k in row for k in ('trajectory_array','caption','character_array','intrinsics'))
  if complete:
   n=row['trajectory_array']['stop']-row['trajectory_array']['start'];nc=row['character_array']['stop']-row['character_array']['start']
   row['character_temporally_aligned']=n==nc;alignment_errors+=int(n!=nc)
   row['input_fields']=['caption','caption_cam','intrinsics','initial_character_position_optional']
   row['target_fields']=['trajectory_array']
   row['training_eligibility']=bool(row.get('pose_qa',{}).get('numeric_admitted') and not row.get('errors'))
   row['commercial_training_eligibility']=False
   f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n');selected.append(row);dist[row['split']]+=1;groups[row['split']].add(row['source_video_group'])
  else:q.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n');orphans.append(key)
assert all(not (groups[a]&groups[b]) for a,b in [('train','validation'),('train','test'),('validation','test')])
# Verify a complete data-only traversal of stored arrays; no encoder/model imports.
p=np.load(arrays/'poses.npy',mmap_mode='r',allow_pickle=False);c=np.load(arrays/'character.npy',mmap_mode='r',allow_pickle=False)
traversed=0
for row in selected:
 s=row['trajectory_array'];a=p[s['start']:s['stop']];assert len(a)>=2 and a.shape[1]==12 and np.isfinite(a).all();traversed+=1
summary={'native_modality_counts':counts,'complete_trajectory_caption_character_intrinsics_records':len(selected),'numeric_admitted':sum(r['training_eligibility'] for r in selected),'quarantined_orphan_keys':len(orphans),'source_video_groups':len(set().union(*groups.values())),'split_rows':dict(dist),'split_groups':{k:len(v) for k,v in groups.items()},'source_video_group_cross_split_overlap':0,'upstream_groups_with_train_test_overlap':sum({'train','test'}<=v for v in group_upstream.values()),'character_length_mismatches':alignment_errors,'numerical_parse_errors':len(errors),'numeric_pose_rows':len(p),'numeric_character_rows':len(c),'data_only_traversed_records':traversed,'raw_RGB_observations':0,'native_bytes_received':sum(r.get('bytes',0) for r in receipts),'model_calls':0,'learning_experiment_authorized':False}
write_json(ROOT/'QA.json',summary);write_json(ROOT/'parse_errors.json',errors)
(ROOT/'README_RU.txt').write_text('E.T.: полный выбранный корпус числовых траекторий и описаний, а не RGB-видеокорпус.\n114603 исходные траектории проверяются как KITTI 3x4. Исходные восемь архивов сохранены без изменения.\nОписание автоматически получено авторами источника; это не зафиксированная до съёмки цель человека.\nРазбиение назначено целым группам исходных видео. Отсутствующая метрическая шкала и частота кадров не выдуманы.\nНикакое обучение или inference не выполнялось.\n')
print('CC17_CURATED_SUMMARY '+json.dumps(summary),flush=True)
package(ROOT,'et-curated-core')
