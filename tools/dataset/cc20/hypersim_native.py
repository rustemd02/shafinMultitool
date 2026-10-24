"""Bounded native Hypersim acquisition and task-specific CameraCoach records.
This is photorealistic SIMULATED imagery, not real capture-time operator utility.
Source RGB/instance/depth/poses are retained byte-for-byte. New goals are explicit
numeric task definitions, never fabricated historical intent. No model calls.
"""
from __future__ import annotations
import argparse,collections,csv,hashlib,io,json,math,os,random,shutil,sys,time,zipfile
from pathlib import Path
import h5py,numpy as np,requests
from PIL import Image
PIN='3463c5c4a75f3cbfc65ed31cfd6e87204b3a2254'
REPO='https://raw.githubusercontent.com/apple-aiml-research/ml-hypersim/'+PIN+'/'
CDN='https://docs-assets.developer.apple.com/ml-research/datasets/hypersim/v1/scenes/'
SPLIT_PATH='evermotion_dataset/analysis/metadata_images_split_scene_v1.csv'
INTRINSICS_PATH='contrib/mikeroberts3000/metadata_camera_parameters.csv'
GOALS=[
 {'id':'visible_detail_extent','height_min':.30,'height_max':.80,'center_x_min':.05,'center_x_max':.95,'edge_margin_min':.01},
 {'id':'visible_context_extent','height_min':.08,'height_max':.28,'center_x_min':.05,'center_x_max':.95,'edge_margin_min':.01},
 {'id':'explicit_left_placement','height_min':.08,'height_max':.80,'center_x_min':.10,'center_x_max':.40,'edge_margin_min':.01},
 {'id':'explicit_right_placement','height_min':.08,'height_max':.80,'center_x_min':.60,'center_x_max':.90,'edge_margin_min':.01},
]
SESSION=requests.Session();SESSION.headers.update({'Accept-Encoding':'identity','User-Agent':'CameraCoach-native-dataset/20'})

def sha(b):return hashlib.sha256(b).hexdigest()
def dump(path,data):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,ensure_ascii=False,allow_nan=False,indent=2)+'\n')
def lines(path,values):
 with Path(path).open('w') as f:
  for value in values:f.write(json.dumps(value,ensure_ascii=False,allow_nan=False)+'\n')
def get(url,headers=None):
 for attempt in range(4):
  try:
   r=SESSION.get(url,headers=headers,timeout=(15,90))
   if r.status_code in [429,500,502,503,504]:
    delay=min(60,max(2**attempt,float(r.headers.get('Retry-After',0) or 0)));r.close();time.sleep(delay);continue
   r.raise_for_status();return r
  except (requests.ConnectionError,requests.Timeout):
   if attempt==3:raise
   time.sleep(2**attempt)
 raise RuntimeError('Bounded retries exhausted: '+url)

class RangeFile(io.RawIOBase):
 """Seekable ZIP input using validated HTTP ranges; never fetches whole corpus."""
 def __init__(self,url):
  self.url=url;self.pos=0;self.cache=collections.OrderedDict();self.transferred=0
  r=get(url,{'Range':'bytes=0-0'});assert r.status_code==206 and len(r.content)==1
  self.size=int(r.headers['Content-Range'].split('/')[-1]);self.etag=r.headers.get('ETag');self.transferred=1
 def readable(self):return True
 def seekable(self):return True
 def tell(self):return self.pos
 def seek(self,n,whence=0):
  self.pos=n if whence==0 else self.pos+n if whence==1 else self.size+n
  if self.pos<0:raise ValueError('Negative archive seek')
  return self.pos
 def read(self,n=-1):
  if n<0:n=self.size-self.pos
  n=min(n,self.size-self.pos)
  if n<=0:return b''
  end=self.pos+n;out=[];block=2*1024*1024
  while self.pos<end:
   k=self.pos//block
   if k not in self.cache:
    lo=k*block;hi=min(self.size-1,lo+block-1);r=get(self.url,{'Range':f'bytes={lo}-{hi}'})
    assert r.status_code==206 and len(r.content)==hi-lo+1
    assert r.headers['Content-Range']==f'bytes {lo}-{hi}/{self.size}'
    if self.etag:assert r.headers.get('ETag')==self.etag,'Source archive changed during read'
    self.cache[k]=r.content;self.transferred+=len(r.content)
    while len(self.cache)>32:self.cache.popitem(last=False)
   self.cache.move_to_end(k);b=self.cache[k];offset=self.pos%block;take=min(end-self.pos,len(b)-offset)
   assert take>0;out.append(b[offset:offset+take]);self.pos+=take
  return b''.join(out)

def hdf(data):
 with h5py.File(io.BytesIO(data),'r') as f:return f['dataset'][:]

def metadata(root):
 native=root/'source';native.mkdir(exist_ok=True);receipts=[];result={}
 for path in ['README.md','LICENSE.txt',SPLIT_PATH,INTRINSICS_PATH,'code/python/tools/scene_generate_images_tonemap.py']:
  response=get(REPO+path);b=response.content;dest=native/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
  receipts.append({'url':REPO+path,'path':str(dest.relative_to(root)),'bytes':len(b),'sha256':sha(b)})
  result[path]=b
 assert 'Creative Commons Attribution-ShareAlike 3.0' in result['README.md'].decode()
 rows=list(csv.DictReader(io.StringIO(result[SPLIT_PATH].decode())))
 intrinsics={r['scene_name']:r for r in csv.DictReader(io.StringIO(result[INTRINSICS_PATH].decode()))}
 grouped=collections.defaultdict(lambda:collections.defaultdict(list));splits={}
 for row in rows:
  if row['included_in_public_release']!='True' or row['split_partition_name'] not in ['train','val','test']:continue
  scene=row['scene_name'];split={'val':'validation'}.get(row['split_partition_name'],row['split_partition_name'])
  if scene in splits:assert splits[scene]==split
  splits[scene]=split;grouped[scene][row['camera_name']].append(int(row['frame_id']))
 # Source-defined scene splits are retained. Selection is metadata-only, prior to targets.
 # Reserve different source collection volumes when available; no claim of unique assets.
 chosen=[];used_volumes=set()
 for split,num in [('test',8),('validation',8),('train',32)]:
  pool=sorted([s for s in grouped if splits[s]==split and any(len(v)>=6 for v in grouped[s].values())],key=lambda s:sha(('cc20-native-scenes:'+s).encode()))
  accepted=[]
  for s in pool:
   volume=s.split('_')[1]
   if volume in used_volumes:continue
   accepted.append(s);used_volumes.add(volume)
   if len(accepted)==num:break
  if len(accepted)<num:
   for s in pool:
    if s not in accepted:accepted.append(s)
    if len(accepted)==num:break
  assert len(accepted)==num,(split,len(accepted))
  for s in accepted:
   camera=sorted(grouped[s],key=lambda c:(-len(grouped[s][c]),c))[0]
   frames=sorted(grouped[s][camera]);take=np.linspace(0,len(frames)-1,6).astype(int)
   chosen.append({'scene':s,'source_split':split,'camera':camera,'frames':[frames[i] for i in take]})
 chosen.sort(key=lambda r:(r['source_split'],r['scene']))
 dump(root/'SOURCE_LOCK.json',{'repository_revision':PIN,'files':receipts,'dataset_release':'v1','license':'CC-BY-SA-3.0 for dataset; toolkit separately licensed','selected_scenes':chosen,
   'selection':'48 scene-disjoint native source scenes, 6 views per scene, only publicly released frames; source split retained; volume diversity metadata heuristic','asset_reuse':'source warns some assets recur across scenes; semantic asset independence not asserted'})
 return chosen,intrinsics


def bbox_measure(inst,subject_id):
 mask=inst==subject_id;y,x=np.where(mask);h,w=inst.shape
 if len(x)==0:return {'pixels':0,'height':0.,'area':0.,'center_x':None,'edge_margin':None,'bbox':None,'tap':None}
 box=[float(x.min()/w),float(y.min()/h),float((x.max()+1)/w),float((y.max()+1)/h)];mid=len(x)//2
 return {'pixels':len(x),'height':box[3]-box[1],'area':float(len(x)/(h*w)),'center_x':(box[0]+box[2])/2,
   'edge_margin':min(box[0],box[1],1-box[2],1-box[3]),'bbox':box,'tap':[(float(x[mid])+.5)/w,(float(y[mid])+.5)/h]}
def compatible(measure,goal):
 return bool(measure['pixels']>=100 and goal['height_min']<=measure['height']<=goal['height_max'] and
  goal['center_x_min']<=measure['center_x']<=goal['center_x_max'] and measure['edge_margin']>=goal['edge_margin_min'])
def critique(measure,goal):
 if goal is None:return {'goal_missing':True,'too_small':None,'too_large':None,'placement_mismatch':None,'border_margin_shortfall':None}
 return {'goal_missing':False,'too_small':measure['height']<goal['height_min'],'too_large':measure['height']>goal['height_max'],
   'placement_mismatch':not goal['center_x_min']<=measure['center_x']<=goal['center_x_max'],'border_margin_shortfall':measure['edge_margin']<goal['edge_margin_min']}

def acquire_scene(root,item,intrinsic):
 scene=item['scene'];cam=item['camera'];remote=RangeFile(CDN+scene+'.zip');z=zipfile.ZipFile(remote);receipts=[]
 def member(name):
  assert name.startswith(scene+'/') and '..' not in Path(name).parts
  info=z.getinfo(name);b=z.read(info) # ZipFile verifies the member CRC, unlike metadata-only acquisition.
  target=root/'native'/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b)
  receipts.append({'source_url':remote.url,'source_etag':remote.etag,'source_archive_bytes':remote.size,'member':name,'member_crc32':info.CRC,
    'path':str(target.relative_to(root)),'bytes':len(b),'sha256':sha(b),'crc_verified':True})
  return b
 scene_meta=list(csv.DictReader(io.StringIO(member(scene+'/_detail/metadata_scene.csv').decode())))
 scale=float(next(r['parameter_value'] for r in scene_meta if r['parameter_name']=='meters_per_asset_unit'))
 positions=hdf(member(scene+f'/_detail/{cam}/camera_keyframe_positions.hdf5'))
 rotations=hdf(member(scene+f'/_detail/{cam}/camera_keyframe_orientations.hdf5'))
 indices=hdf(member(scene+f'/_detail/{cam}/camera_keyframe_frame_indices.hdf5'))
 assert positions.shape==(len(indices),3) and rotations.shape==(len(indices),3,3)
 assert np.isfinite(positions).all() and np.isfinite(rotations).all() and np.isfinite(scale) and scale>0
 assert np.max(np.abs(rotations.transpose(0,2,1)@rotations-np.eye(3)))<1e-4
 assert np.max(np.abs(np.linalg.det(rotations)-1))<1e-4
 by_frame={int(v):j for j,v in enumerate(indices)};views=[];arrays={}
 projection=[[float(intrinsic[f'M_proj_{i}{j}']) for j in range(4)] for i in range(4)]
 ray_transform=[[float(intrinsic[f'M_cam_from_uv_{i}{j}']) for j in range(3)] for i in range(3)]
 for frame in item['frames']:
  key=f'frame.{frame:04d}';fp=scene+f'/images/scene_{cam}_final_hdf5/{key}.color.hdf5'
  rgb=hdf(member(fp)).astype(np.float32);native={}
  for modality in ['semantic_instance','semantic','depth_meters','render_entity_id']:
   path=scene+f'/images/scene_{cam}_geometry_hdf5/{key}.{modality}.hdf5';native[modality]=hdf(member(path))
  inst=native['semantic_instance'];sem=native['semantic'];depth=native['depth_meters'].astype(np.float32);entity=native['render_entity_id']
  assert rgb.ndim==3 and rgb.shape[2]==3 and all(x.shape==rgb.shape[:2] for x in native.values())
  assert inst.dtype.kind in 'iu' and sem.dtype.kind in 'iu'
  valid=(entity!=-1)&np.isfinite(rgb).all(axis=2);assert valid.any()
  bright=rgb@np.asarray([.3,.59,.11],np.float32);p90=float(np.percentile(bright[valid],90));factor=(.8**2.2)/p90 if p90>=.0001 else 0.
  # Source-specified per-frame tone-map. It is NOT an exposure/control intervention.
  mapped=np.clip(np.maximum(np.nan_to_num(rgb)*factor,0)**(1/2.2),0,1)
  png=root/'rgb'/scene/(cam+'_'+key+'.png');png.parent.mkdir(parents=True,exist_ok=True)
  Image.fromarray(np.rint(mapped*255).astype(np.uint8),'RGB').save(png,compress_level=6)
  with Image.open(png) as image:assert image.size==(rgb.shape[1],rgb.shape[0]);image.verify()
  target_file=root/'geometry'/scene/(cam+'_'+key+'.npz');target_file.parent.mkdir(parents=True,exist_ok=True)
  np.savez_compressed(target_file,semantic_instance=inst,semantic=sem,range_m=depth,range_valid=np.isfinite(depth)&(depth>0),rgb_valid=valid)
  j=by_frame[frame];view={'id':scene+':'+cam+':'+str(frame),'scene':scene,'split':item['source_split'],'frame_ordinal':frame,
    'rgb':str(png.relative_to(root)),'rgb_sha256':sha(png.read_bytes()),'geometry':str(target_file.relative_to(root)),'geometry_sha256':sha(target_file.read_bytes()),
    'width':rgb.shape[1],'height':rgb.shape[0],'camera_position_m':(positions[j]*scale).tolist(),'world_from_camera_rotation':rotations[j].tolist(),
    'M_proj':projection,'M_cam_from_uv':ray_transform,'meters_per_asset_unit':scale,'tone_map':{'gamma':1/2.2,'brightness_percentile':90,'desired':.8,'scale':factor},
    'source_RGB_member':fp,'source_RGB_precision':'float16 native HDR','source_clock_seconds':None,'labels':'source-native photorealistic synthetic scene','license':'CC-BY-SA-3.0'}
  views.append(view);arrays[view['id']]={'instance':inst,'semantic':sem,'rgb_valid':valid}
 dump(root/'native_receipts'/f'{scene}.json',{'archive_url':remote.url,'archive_size':remote.size,'archive_etag':remote.etag,'range_bytes_fetched':remote.transferred,'source_members':receipts,'whole_archive_downloaded':False})
 return views,arrays


def build_records(views,arrays):
 inputs=[];targets=[];perception=[];pairs=0;physical=np.asarray([[1.,0.,0.],[0.,0.,-1.],[0.,1.,0.]])
 for view in views:
  inst=arrays[view['id']]['instance'];sem=arrays[view['id']]['semantic']
  ids,counts=np.unique(inst,return_counts=True);candidates=[]
  for sid,count in zip(ids,counts):
   if sid<0 or count<max(100,int(inst.size*.001)):continue
   labels,num=np.unique(sem[inst==sid],return_counts=True);category=int(labels[np.argmax(num)])
   if category in [-1,0,1,2,22]:continue # void, wall, floor, ceiling are not chosen foreground subjects.
   candidates.append((int(count),int(sid),category))
  candidates=sorted(candidates,reverse=True)[:4]
  R=np.asarray(view['world_from_camera_rotation']);p=np.asarray(view['camera_position_m'])
  alternatives=[]
  for other in views:
   r=np.asarray(other['world_from_camera_rotation']);q=np.asarray(other['camera_position_m']);delta=physical@R.T@(q-p);relative=physical@R.T@r@physical.T
   alternatives.append({'id':other['id'],'type':'keep_view' if other['id']==view['id'] else 'native_compound_view_transition',
     'translation_right_forward_up_m':delta.tolist(),'relative_rotation_right_forward_up':relative.tolist(),
     'duration_s':None,'path_feasible':None,'availability':'recorded endpoint exists; traversability unknown'})
  for _,sid,category in candidates:
   initial=bbox_measure(inst,sid);all_measures=[bbox_measure(arrays[o['id']]['instance'],sid) for o in views]
   perception.append({'record_id':view['id']+':subject:'+str(sid),'split':view['split'],'origin_group':view['scene'],
      'input':{'rgb':view['rgb'],'tap_xy':initial['tap']},'targets':{'semantic_instance_id':sid,'semantic_category':category,'source_geometry':view['geometry'],'visible_bbox_xyxy':initial['bbox'],
       'amodal_mask':None,'physical_occlusion_fraction':None},'label_authority':'source_native_instance_labels','loss_masks':{'visible_instance_mask':True,'visible_bbox':True,'depth':True,'semantic_category':True,'physical_occlusion_fraction':False}})
   outcomes={}
   for goal in GOALS+[None]:
    rid=view['id']+':s'+str(sid)+':'+(goal['id'] if goal else 'missing_goal')
    success=[compatible(m,goal) for m in all_measures] if goal else [False]*len(views)
    keep=next(i for i,o in enumerate(views) if o['id']==view['id'])
    state='ask' if goal is None else 'keep' if success[keep] else 'alternative_view_available' if any(success) else 'abstain'
    inputs.append({'schema':'cc20.goal_conditioned_native_view.v1','record_id':rid,'task_type':'goal_conditioned_view_compatibility','split':view['split'],'origin_group':view['scene'],
      'observations':{'rgb':view['rgb'],'tap_xy':initial['tap'],'goal':goal,'candidate_views':alternatives,'M_proj':view['M_proj'],
       'observation_cutoff':'current native frame only; frame index is ordinal, not a clock','protected_style':None,'equipment_constraints':None},
      'provenance':{'source':'Hypersim v1','revision':PIN,'intent_origin':'assigned_numeric_task_defined_before_outcome_evaluation','label_origin':'derived_native_visible_instance_extents',
       'rgb_sha256':view['rgb_sha256'],'source_scene':view['scene'],'native_instance_id':sid,'license':'CC-BY-SA-3.0'}})
    targets.append({'record_id':rid,'view_goal_satisfied':success,'decision':state,'critique':critique(initial,goal),
      'measured_visible_instance_extents':all_measures,'action_proposed':None,'action_performed':None,'human_utility':None,'aesthetic_preference':None,'candidate_path_feasible':[None]*len(views),
      'loss_masks':{'view_goal_satisfied':[goal is not None]*len(views),'decision':True,'action_proposed':False,'action_performed':False,'human_utility':False,'aesthetic_preference':False,'candidate_path_feasible':[False]*len(views)},
      'authority':'measured native visible-region extents with explicit new geometric goals; not human intent or safe movement commands'})
    if goal:outcomes[goal['id']]=success
   for a,b in [('visible_detail_extent','visible_context_extent'),('explicit_left_placement','explicit_right_placement')]:
    if any(x and not y for x,y in zip(outcomes[a],outcomes[b])) and any(y and not x for x,y in zip(outcomes[a],outcomes[b])):pairs+=1
 return inputs,targets,perception,pairs


def batches(root,inputs,targets,batch_size=8):
 target_map={r['record_id']:r for r in targets};cache={}
 for start in range(0,len(inputs),batch_size):
  block=inputs[start:start+batch_size];images=[];taps=[];goals=[];goal_mask=[];candidate=[];labels=[];masks=[]
  for row in block:
   o=row['observations'];p=root/o['rgb']
   if o['rgb'] not in cache:
    assert sha(p.read_bytes())==row['provenance']['rgb_sha256']
    with Image.open(p) as im:cache[o['rgb']]=np.asarray(im.convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255
   images.append(cache[o['rgb']]);taps.append(o['tap_xy']);g=o['goal'];keys=['height_min','height_max','center_x_min','center_x_max','edge_margin_min']
   goals.append([g[k] if g else 0 for k in keys]);goal_mask.append(g is not None)
   order=list(range(len(o['candidate_views'])));random.Random(row['record_id']).shuffle(order)
   candidate.append([o['candidate_views'][i]['translation_right_forward_up_m']+np.asarray(o['candidate_views'][i]['relative_rotation_right_forward_up']).ravel().tolist() for i in order])
   t=target_map[row['record_id']];labels.append([t['view_goal_satisfied'][i] for i in order]);masks.append([t['loss_masks']['view_goal_satisfied'][i] for i in order])
   assert t['human_utility'] is None and not t['loss_masks']['human_utility']
   assert all(v is None for v in t['candidate_path_feasible']) and not any(t['loss_masks']['candidate_path_feasible'])
  X={'rgb':np.stack(images),'tap_xy':np.asarray(taps,np.float32),'goal_bounds':np.asarray(goals,np.float32),'goal_known':np.asarray(goal_mask,bool),'candidate_pose_deltas':np.asarray(candidate,np.float32)}
  Y={'view_goal_satisfied':np.asarray(labels,np.float32)};M={'view_goal_satisfied':np.asarray(masks,bool)}
  assert X['rgb'].shape[1:]==(3,224,224) and X['candidate_pose_deltas'].shape[1:]==(6,12)
  for array in [*X.values(),*Y.values()]:assert np.isfinite(array).all()
  assert Y['view_goal_satisfied'].shape==M['view_goal_satisfied'].shape
  yield X,Y,M

def run(shard,shards):
 root=Path('hypersim')/f'cc20-hypersim-{shard:02d}';root.mkdir(parents=True,exist_ok=True)
 selection,intrinsics=metadata(root);selected=selection[shard::shards];all_inputs=[];all_targets=[];all_perception=[];all_views=[];pair_count=0;failed=[]
 for item in selected:
  try:
   views,arrays=acquire_scene(root,item,intrinsics[item['scene']]);inputs,targets,perception,pairs=build_records(views,arrays)
   assert inputs and perception
   all_inputs+=inputs;all_targets+=targets;all_perception+=perception;all_views+=views;pair_count+=pairs
   print('CC20_SCENE '+json.dumps({'scene':item['scene'],'split':item['source_split'],'views':len(views),'view_records':len(inputs),'subject_records':len(perception),'goal_contrasts':pairs}),flush=True)
  except Exception as exc:
   failed.append({'scene':item['scene'],'type':type(exc).__name__,'error':str(exc)[:1200]})
   print('CC20_SOURCE_FAILURE '+json.dumps(failed[-1]),flush=True)
 assert all_inputs,'No valid scenes received'
 lines(root/'view_inputs.jsonl',all_inputs);lines(root/'view_targets.jsonl',all_targets);lines(root/'subject_perception.jsonl',all_perception);lines(root/'native_views.jsonl',all_views)
 dump(root/'ASSIGNED_GOALS.json',GOALS);dump(root/'SOURCE_FAILURES.json',failed)
 tensor_hash=hashlib.sha256();batch_count=0
 for X,Y,M in batches(root,all_inputs,all_targets):
  for container in [X,Y,M]:
   for name,array in sorted(container.items()):tensor_hash.update(name.encode());tensor_hash.update(str(array.shape).encode());tensor_hash.update(str(array.dtype).encode());tensor_hash.update(array.tobytes())
  batch_count+=1
 splits=collections.defaultdict(set)
 for row in all_inputs:splits[row['split']].add(row['origin_group'])
 assert all(not splits[a]&splits[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
 summary={'source':'Hypersim v1','source_revision':PIN,'native_scene_origins':len({v['scene'] for v in all_views}),'native_hdr_views':len(all_views),'native_hdf5_retained':len(list((root/'native').rglob('*.hdf5'))),
  'subject_perception_records':len(all_perception),'goal_conditioned_view_records':len(all_inputs),'contradictory_successful_numeric_goal_pairs':pair_count,'source_native_files':len(list((root/'native').rglob('*'))),
  'scene_counts_by_split':{k:len(v) for k,v in splits.items()},'actual_numpy_batches':batch_count,'tensor_stream_sha256':tensor_hash.hexdigest(),'failed_scenes':failed,
  'scope':'photorealistic synthetic native subject perception and geometric view compatibility; not safe action commands or real operator utility',
  'native_RGB':'lossless source float16 HDR files retained; display PNG derived by documented per-frame tone mapping','native_masks':'source semantic and semantic-instance HDF5 retained','depth':'native Euclidean range in metres, NOT z-depth',
  'pose_convention':'source world-from-camera right/up/back; candidate deltas converted to current-camera right/forward/up','time':'ordinal source frame IDs; no invented fps or action durations',
  'path_feasibility':'unknown; never enabled as a loss','human_utility':'unknown; never enabled as a loss','new_human_responses':0,'model_calls':0,
  'source_license':'CC-BY-SA-3.0 dataset with attribution/share-alike terms; no determination of downstream model-weight obligations','full_cameracoach_training_ready':False}
 dump(root/'QA.json',summary)
 (root/'ATTRIBUTION_AND_SCOPE.md').write_text('# Hypersim native component for CameraCoach\n\nSource: Mike Roberts et al., Hypersim: A Photorealistic Synthetic Dataset for Holistic Indoor Scene Understanding, ICCV 2021. Official release v1; repository revision '+PIN+'. Dataset license: Creative Commons Attribution-ShareAlike 3.0 Unported. Preserve attribution and applicable share-alike conditions. Native files are unchanged. New PNG tone mapping, geometric goal records and candidate-relative poses are documented adaptations. Toolkit licensing is separately retained in source/LICENSE.txt.\n\nThis dataset is photorealistic SYNTHETIC imagery, not real filming. Source instance annotations supervise selected visible regions and range. Numeric goals were assigned by this builder; they are not historical intentions. Visible bounding extent is not amodal object size or measured physical occlusion fraction.\n\nCandidate entries refer to existing native view endpoints. Camera translation/orientation changes may be compound. Collision-free paths, human execution speed, real equipment constraints, actor intent and aesthetic preference are unknown. These fields are null and their losses disabled. Never use alternative-view availability as permission to move through a real room.\n\nTrain/val/test follows native scene split. Source documentation acknowledges asset reuse. This source does not establish transfer to actual iPhone users or the full CameraCoach DoD. PNG tone mapping is automatic per frame; do not use it as physical exposure-change labels.\n')
 (root/'README_RU.md').write_text('# CameraCoach: native photorealistic component\n\nВ native/ сохранены настоящие исходные HDR, маски, глубина и параметры камер официального Hypersim, без подмены превью. Сцены синтетические фотореалистичные, а не реальные съёмки.\n\nsubject_perception.jsonl — выбранная tap-точкой видимая область и исходные targets. view_inputs.jsonl и view_targets.jsonl разделены: вход содержит только текущий кадр, цель и параметры предложенных переходов, но не будущие изображения, маски или глубину.\n\nСмысл новых целей ограничен измеримым видимым размером и положением области. Путь между известными ракурсами не проверен на столкновения. Это не готовая разметка безопасных физических советов, не художественная экспертиза и не доказательство пользы человеку.\n\nКод batches() в reproduction/hypersim_native.py реально прочитал все строки и собрал NumPy X/Y/loss_masks. Blender и модель для чтения не нужны. Все исходные ZIP-members проверены по CRC и SHA256.\n')
 code=root/'reproduction';code.mkdir(exist_ok=True);shutil.copyfile(__file__,code/Path(__file__).name)
 sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'cc17'));from release_pack import package
 print('CC20_HYPERSIM_SUMMARY '+json.dumps(summary),flush=True);package(root,root.name)
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--shard',type=int,default=0);parser.add_argument('--shards',type=int,default=8);args=parser.parse_args();run(args.shard,args.shards)
