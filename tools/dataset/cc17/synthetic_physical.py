"""Physical proxy-scenes for intent-conditioned camera actions; no model calls.
All geometry is procedural. Human likeness, aesthetics and human utility are NOT
labels. Four predeclared objectives use projected size and visible surface only.
Blender renders the observations; independent analytic AABB rays compute targets.
"""
from __future__ import annotations
import argparse,collections,hashlib,json,math,os,random
from pathlib import Path
import numpy as np
from PIL import Image
import bpy
from mathutils import Matrix,Vector
from acquire import write_json,digest
from release_pack import package
W,H=160,120
FAMILIES=['product','portrait_proxy','dialogue_proxy','hand_tool_proxy','reveal','establishing','silhouette_geometry_only','moving_subject_geometry_only']
GOALS=[{'id':'detail','height_min':.42,'height_max':.85,'visible_min':.65},{'id':'context','height_min':.10,'height_max':.23,'visible_min':.65},{'id':'expose','height_min':.04,'height_max':.90,'visible_min':.92},{'id':'conceal','height_min':.04,'height_max':.90,'visible_max':.10}]

def unit(v):
 v=np.asarray(v,dtype=float);return v/np.linalg.norm(v)
def rotation(axis,angle):
 x,y,z=unit(axis);c=math.cos(angle);s=math.sin(angle);C=1-c
 return np.array([[c+x*x*C,x*y*C-z*s,x*z*C+y*s],[y*x*C+z*s,c+y*y*C,y*z*C-x*s],[z*x*C-y*s,z*y*C+x*s,c+z*z*C]])
def camera(pos,target,focal=30.):
 forward=unit(np.asarray(target)-pos);right=unit(np.cross(forward,[0,0,1]));up=unit(np.cross(right,forward))
 return {'position':np.asarray(pos,dtype=float),'right':right,'up':up,'forward':forward,'focal_mm':float(focal)}
def rays(cam):
 fx=W*cam['focal_mm']/36.;y,x=np.mgrid[:H,:W];xx=(x+.5-W/2)/fx;yy=-(y+.5-H/2)/fx
 ds=xx[...,None]*cam['right']+yy[...,None]*cam['up']+cam['forward'];return ds/np.linalg.norm(ds,axis=-1,keepdims=True)
def intersect(cam,boxes,selected_only=False):
 ds=rays(cam);origin=cam['position'];dist=np.full((H,W),np.inf);ids=np.zeros((H,W),dtype=np.uint16)
 inv=np.divide(1.,ds,out=np.full_like(ds,1e16),where=np.abs(ds)>1e-16)
 for box in boxes:
  if selected_only and not box['selected']:continue
  lo=np.asarray(box['center'])-np.asarray(box['size'])/2;hi=np.asarray(box['center'])+np.asarray(box['size'])/2
  a=(lo-origin)*inv;b=(hi-origin)*inv;near=np.max(np.minimum(a,b),axis=-1);far=np.min(np.maximum(a,b),axis=-1)
  hit=np.where(near>1e-5,near,far);valid=(far>=np.maximum(near,1e-5))&(hit<dist)
  dist[valid]=hit[valid];ids[valid]=box['id']
 return ids,dist

def measure(cam,boxes):
 ids,depth=intersect(cam,boxes);alone,_=intersect(cam,boxes,True)
 selected=np.isin(ids,[b['id'] for b in boxes if b['selected']]);amask=alone>0
 yy,xx=np.where(amask)
 if len(xx):bbox=[float(xx.min()/W),float(yy.min()/H),float((xx.max()+1)/W),float((yy.max()+1)/H)];height=bbox[3]-bbox[1]
 else:bbox=None;height=0.
 visible=float(selected.sum()/amask.sum()) if amask.any() else 0.
 # Reject offscreen goals: every selected 3D box corner must lie within the frame
 # and in front of the camera. Hiding by pointing away is never a valid conceal.
 projected=[];fx=W*cam['focal_mm']/36.
 for b in boxes:
  if not b['selected']:continue
  for sx in (-1,1):
   for sy in (-1,1):
    for sz in (-1,1):
     p=np.asarray(b['center'])+np.array([sx,sy,sz])*np.asarray(b['size'])/2-cam['position'];z=float(p@cam['forward'])
     if z<=.05:projected.append([-10.,-10.]);continue
     projected.append([.5+fx*float(p@cam['right'])/z/W,.5-fx*float(p@cam['up'])/z/H])
 full=bool(projected and all(.01<=p[0]<=.99 and .01<=p[1]<=.99 for p in projected))
 return {'visible_fraction':visible,'projected_height':height,'projected_pixels':int(amask.sum()),'visible_pixels':int(selected.sum()),'unoccluded_roi_xyxy':bbox,'all_selected_corners_in_frame':full},ids,depth,alone

def segment_clear(start,end,boxes,radius=.15):
 # Continuous segment/AABB test against conservative radius-expanded boxes.
 delta=end-start
 for b in boxes:
  if b.get('noncolliding'):continue
  lo=np.asarray(b['center'])-np.asarray(b['size'])/2-radius;hi=np.asarray(b['center'])+np.asarray(b['size'])/2+radius
  t0,t1=0.,1.
  for k in range(3):
   if abs(delta[k])<1e-12:
    if start[k]<lo[k] or start[k]>hi[k]:t0,t1=1.,0.;break
   else:
    a,bv=(lo[k]-start[k])/delta[k],(hi[k]-start[k])/delta[k];t0=max(t0,min(a,bv));t1=min(t1,max(a,bv))
   if t0>t1:break
  if t0<=t1:return False
 return bool(end[2]>.25 and abs(end[0])<4.5 and -8.5<end[1]<2.)

def action_space():
 out=[{'id':'keep','translation':[0,0,0],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'cost':0.}]
 for axis,label,amounts in [(0,'truck',[-1.4,-.7,.7,1.4]),(1,'dolly',[-2.,-1.,1.,2.,3.2]),(2,'height',[-.6,-.3,.3,.6])]:
  for v in amounts:
   vec=[0.,0.,0.];vec[axis]=v
   out.append({'id':label+'_'+str(v),'translation':vec,'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'cost':abs(v)})
 for angle in [-20.,-10.,10.,20.]:out.append({'id':'pan_'+str(angle),'translation':[0,0,0],'pan_deg':angle,'tilt_deg':0.,'focal_factor':1.,'cost':abs(angle)/30+.1})
 for angle in [-12.,12.]:out.append({'id':'tilt_'+str(angle),'translation':[0,0,0],'pan_deg':0.,'tilt_deg':angle,'focal_factor':1.,'cost':.5})
 for factor in [.65,1.5,2.]:out.append({'id':'focal_'+str(factor),'translation':[0,0,0],'pan_deg':0.,'tilt_deg':0.,'focal_factor':factor,'cost':abs(math.log(factor))+.3})
 return out
ACTIONS=action_space()

def apply(base,a):
 c={k:(v.copy() if isinstance(v,np.ndarray) else v) for k,v in base.items()}
 c['position']=c['position']+np.asarray(a['translation']);r=rotation([0,0,1],math.radians(a['pan_deg']))
 r=rotation(r@base['right'],math.radians(a['tilt_deg']))@r
 for k in ('right','up','forward'):c[k]=r@base[k]
 c['focal_mm']*=a['focal_factor'];return c

def succeeds(m,g):
 return bool(m['all_selected_corners_in_frame'] and m['projected_pixels']>=20 and g['height_min']<=m['projected_height']<=g['height_max'] and m['visible_fraction']>=g.get('visible_min',0) and m['visible_fraction']<=g.get('visible_max',1))

def make_scene(index):
 seed=17000000+index;rng=random.Random(seed);family=FAMILIES[index%8];layout=index//8
 split='train' if layout%10<7 else 'validation' if layout%10<9 else 'test'
 boxes=[]
 def add(center,size,selected=False,color=None,noncolliding=False):
  boxes.append({'id':len(boxes)+1,'center':center,'size':size,'selected':selected,'color':color or [rng.uniform(.1,.8) for _ in range(3)],'noncolliding':noncolliding})
 add([0,1.,-.12],[14,18,.2],False,[.27,.30,.33],True)
 x=rng.uniform(-.3,.3);width=rng.uniform(.42,.75);height=rng.uniform(.65,1.35);z=height/2+.35
 if family in ('portrait_proxy','dialogue_proxy','silhouette_geometry_only','moving_subject_geometry_only'):
  add([x,0,.7],[width,.35,.8],True);add([x,0,1.3],[width*.65,.35,.35],True)
  if family=='dialogue_proxy':add([x+1.,.25,.8],[.48,.4,1.4],False)
 elif family=='hand_tool_proxy':
  add([x,0,.9],[.65,.25,.12],True);add([x+.38,0,.95],[.14,.18,.4],True);add([x-.3,.3,.7],[.18,.8,.18],False)
 else:add([x,0,z],[width,rng.uniform(.3,.6),height],True)
 # Foreground screen is offset to create partial occlusion at the initial camera.
 if index%4!=0:add([x+rng.uniform(.08,.45),-1.7,1.0],[rng.uniform(.35,.75),.18,1.8],False,[.34,.21,.17])
 # Layout groups hold together all families/variants sharing a room seed.
 for j in range(3+layout%4):
  add([rng.choice([-1,1])*rng.uniform(1.2,3.5),rng.uniform(-.5,3.5),rng.uniform(.3,1.0)],[rng.uniform(.25,.8),rng.uniform(.25,.8),rng.uniform(.4,1.7)],False)
 add([0,4.,1.5],[10,.15,3.],False,[rng.uniform(.15,.55) for _ in range(3)])
 target=[x,0,1.]
 cam=camera(np.array([rng.uniform(-.25,.25),-rng.uniform(4.2,5.8),rng.uniform(1.1,1.8)]),target,rng.uniform(27.,34.))
 return {'origin_id':f'cc17-sim-{index:05d}','seed':seed,'family':family,'layout_group':f'layout-{layout:04d}','split':split,'boxes':boxes,'camera':cam,'object_semantics':'procedural cuboid proxies; no human or text readability claim'}

def setup_blender():
 bpy.ops.wm.read_factory_settings(use_empty=True);s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=4;s.cycles.use_denoising=False;s.render.resolution_x=W;s.render.resolution_y=H;s.render.resolution_percentage=100;s.render.threads_mode='FIXED';s.render.threads=2
 s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB';s.render.film_transparent=False;s.view_settings.view_transform='Standard';s.view_settings.look='Medium High Contrast' if 'Medium High Contrast' in [i.identifier for i in bpy.types.ColorManagedViewSettings.bl_rna.properties['look'].enum_items] else s.view_settings.look
 world=bpy.data.worlds.new('world');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.16,.16,.16,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45;s.world=world
 cd=bpy.data.cameras.new('camera');co=bpy.data.objects.new('camera',cd);s.collection.objects.link(co);s.camera=co;cd.sensor_width=36;cd.sensor_fit='HORIZONTAL';cd.clip_start=.01;cd.clip_end=100
 ld=bpy.data.lights.new('key','AREA');lo=bpy.data.objects.new('key',ld);s.collection.objects.link(lo);lo.location=(-3,-3,6);ld.energy=850;ld.size=4
 return s

def load_boxes(s,boxes):
 for o in list(s.objects):
  if o.type=='MESH':bpy.data.objects.remove(o,do_unlink=True)
 for b in boxes:
  bpy.ops.mesh.primitive_cube_add(size=1,location=b['center']);o=bpy.context.object;o.name='box_'+str(b['id']);o.dimensions=b['size'];o.pass_index=b['id'];bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  mat=bpy.data.materials.new(o.name);mat.diffuse_color=(*b['color'],1);mat.use_nodes=True;mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*b['color'],1);mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.55;o.data.materials.append(mat)
 bpy.context.view_layer.update()

def set_camera(s,c):
 m=np.eye(4);m[:3,0]=c['right'];m[:3,1]=c['up'];m[:3,2]=-c['forward'];m[:3,3]=c['position'];s.camera.matrix_world=Matrix(m.tolist());s.camera.data.lens=c['focal_mm'];bpy.context.view_layer.update()

def check_rays(s,c,ids,depth,seed):
 rng=random.Random(seed);ds=rays(c);bad=[];deps=bpy.context.evaluated_depsgraph_get()
 for _ in range(48):
  y=rng.randrange(H);x=rng.randrange(W);hit,loc,normal,face,obj,m=s.ray_cast(deps,Vector(c['position']),Vector(ds[y,x]),distance=100)
  actual=int(obj.name.split('_')[1]) if hit and obj.name.startswith('box_') else 0
  if actual!=int(ids[y,x]):bad.append([x,y,int(ids[y,x]),actual])
  if hit and actual==int(ids[y,x]) and abs(float(np.linalg.norm(np.asarray(loc)-c['position']))-depth[y,x])>1e-3:bad.append([x,y,'depth'])
 return bad

def serialize(c):return {k:v.tolist() if isinstance(v,np.ndarray) else v for k,v in c.items()}

def run(start,count,label):
 root=Path('synthetic')/label;root.mkdir(parents=True,exist_ok=True);s=setup_blender();totals=collections.Counter();split_groups=collections.defaultdict(set);contrasts=0;rendered=0;raychecks=0
 write_json(root/'actions.json',ACTIONS);write_json(root/'predeclared_goals.json',GOALS)
 with open(root/'scenes.jsonl','w') as sf,open(root/'policy.jsonl','w') as pf,open(root/'counterfactuals.jsonl','w') as cf:
  for index in range(start,start+count):
   scene=make_scene(index);base=scene['camera'];boxes=scene['boxes'];origin=scene['origin_id'];out=root/'observations'/origin;out.mkdir(parents=True)
   variants=[]
   for a in ACTIONS:
    cam=apply(base,a);m,ids,depth,alone=measure(cam,boxes);valid=segment_clear(base['position'],cam['position'],boxes)
    variants.append({'action_id':a['id'],'metrics':m,'path_feasible':valid,'camera':serialize(cam),'goal_success':{g['id']:bool(valid and succeeds(m,g)) for g in GOALS}})
   decisions=[];chosen={0}
   for g in GOALS:
    success=[i for i,v in enumerate(variants) if v['goal_success'][g['id']]]
    best=min(success,key=lambda i:(ACTIONS[i]['cost'],ACTIONS[i]['id'])) if success else None
    mode='keep' if best==0 else 'recommend' if best is not None else 'abstain'
    if best is not None:chosen.add(best)
    decisions.append({'id':origin+':'+g['id'],'origin_id':origin,'layout_group':scene['layout_group'],'split':scene['split'],'observation':str((out/'before.png').relative_to(root)),'selected_subject_ids':[b['id'] for b in boxes if b['selected']],'goal':g,'action_candidates_file':'actions.json','decision':mode,'target_action_id':ACTIONS[best]['id'] if best is not None else None,'successful_actions':[ACTIONS[i]['id'] for i in success],'action_performed_real':None,'human_goal_achieved':None,'label_origin':'synthetic_physics_objective','training_authorized':False})
    totals[mode]+=1
   for ga,gb in [('detail','context'),('expose','conceal')]:
    da=next(d for d in decisions if d['goal']['id']==ga);db=next(d for d in decisions if d['goal']['id']==gb)
    if da['target_action_id'] and db['target_action_id'] and da['target_action_id']!=db['target_action_id']:
     va=next(v for v in variants if v['action_id']==da['target_action_id']);vb=next(v for v in variants if v['action_id']==db['target_action_id'])
     if not va['goal_success'][gb] and not vb['goal_success'][ga]:contrasts+=1
   load_boxes(s,boxes)
   for i in sorted(chosen):
    cam=apply(base,ACTIONS[i]);m,ids,depth,alone=measure(cam,boxes);set_camera(s,cam)
    bad=check_rays(s,cam,ids,depth,scene['seed']+i);assert not bad,{'origin':origin,'action':i,'ray_mismatches':bad};raychecks+=48
    name='before' if i==0 else 'after_'+str(i);path=out/(name+'.png');s.render.filepath=str(path.resolve());bpy.ops.render.render(write_still=True)
    with Image.open(path) as im:assert im.size==(W,H);im.verify()
    np.savez_compressed(out/(name+'_geometry.npz'),object_id=ids,range_m=np.where(np.isfinite(depth),depth,0).astype(np.float32),valid_depth=np.isfinite(depth),unoccluded_subject_id=alone)
    variants[i]['rendered_observation']=str(path.relative_to(root));variants[i]['rgb_sha256']=digest(path);rendered+=1
   for d in decisions:pf.write(json.dumps(d,allow_nan=False)+'\n')
   sf.write(json.dumps({**scene,'camera':serialize(base),'goals_declared_before_evaluation':GOALS,'target_supervision_scope':'projected size, visibility, continuous conservative collision; not artistic utility'},allow_nan=False)+'\n')
   for v in variants:cf.write(json.dumps({'origin_id':origin,'split':scene['split'],**v},allow_nan=False)+'\n')
   split_groups[scene['split']].add(scene['layout_group']);totals[scene['family']]+=1
   if (index-start+1)%16==0:print('SYNTHETIC_PROGRESS',index-start+1,count,rendered,flush=True)
   for mat in list(bpy.data.materials):
    if mat.users==0:bpy.data.materials.remove(mat)
 assert all(not (split_groups[a]&split_groups[b]) for a,b in [('train','validation'),('train','test'),('validation','test')])
 summary={'scene_configurations':count,'policy_records':count*len(GOALS),'evaluated_action_outcomes':count*len(ACTIONS),'actions_per_scene':len(ACTIONS),'predeclared_goals_per_scene':len(GOALS),'rendered_rgb_files':rendered,'independent_blender_ray_checks':raychecks,'ray_mismatches':0,'successful_opposing_goal_pairs':contrasts,'counts':dict(totals),'layout_groups_by_split':{k:len(v) for k,v in split_groups.items()},'blender':bpy.app.version_string,'renderer':'Cycles CPU 4 samples 160x120','scene_independence':'distinct parameter configurations and grouped layouts; repeated procedural primitive vocabulary','human_readability_or_aesthetic_labels':0,'real_operator_utility_labels':0,'model_calls':0}
 write_json(root/'QA.json',summary)
 (root/'README_RU.txt').write_text('Новые физические процедурные 3D-конфигурации. RGB получен Blender Cycles; метки видимости/размера — независимыми точными лучами по AABB, проверенными на Blender ray_cast.\nЦели detail/context/expose/conceal объявлены до оценки действий; ограничение conceal требует сохранения субъекта в поле зрения, нельзя спрятать его поворотом камеры мимо сцены.\nПрепятствия проверяются непрерывным пересечением отрезка перемещения с расширенными AABB. Проверка консервативная для камеры радиуса 0.15 м.\nФигуры — геометрические прокси, не фотореалистичные люди; названия семейств не подтверждают читаемость лица/текста, кинематографический вкус или динамический трекинг. Движущийся субъект в этом дополнении дан только текущей геометрией.\nСохранены все параметры, все 23 кандидата и результаты; RGB только исходный и выбранные успешные результаты. Полные исходные и контрфактические targets разделены от model inputs.\n')
 print('CC17_SYNTHETIC_SUMMARY '+json.dumps(summary),flush=True);package(root,label)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--start',type=int,default=0);p.add_argument('--count',type=int,default=8);p.add_argument('--label',default='synthetic-pilot');a=p.parse_args();run(a.start,a.count,a.label)
