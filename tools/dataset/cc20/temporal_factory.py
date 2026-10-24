"""CameraCoach CC20 mesh temporal component. Blender-only data, no model calls.
Targets are finite-time, finite-surface sampled geometric conditions, not aesthetics.
Every counterfactual shares the same initial scene and one-second exogenous motion.
The selected subject may change while the RGB history remains exactly identical.
"""
from __future__ import annotations
import argparse,collections,copy,hashlib,json,math,random,shutil,sys
from pathlib import Path
import numpy as np
from PIL import Image
import bpy
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'cc17'))
from acquire import digest,write_json
from release_pack import package
W,H=256,192
TIMES=[0.,.25,.5,.75,1.]
ACTIONS=[{'id':'keep','dx_m':0.,'yaw_deg':0.,'focal_factor':1.,'cost':0.}]
for rate in [-25.,-10.,10.,25.]:ACTIONS.append({'id':'pan_'+str(rate),'dx_m':0.,'yaw_deg':rate,'focal_factor':1.,'cost':.5+abs(rate)/50})
for dx in [-.8,-.4,.4,.8]:ACTIONS.append({'id':'truck_'+str(dx),'dx_m':dx,'yaw_deg':0.,'focal_factor':1.,'cost':1+abs(dx)})
for ff in [.65,1.45]:ACTIONS.append({'id':'focal_'+str(ff),'dx_m':0.,'yaw_deg':0.,'focal_factor':ff,'cost':.6})
GOALS=[{'id':'track','min_visible':.75,'max_center_shift':.12,'height_min':.035,'height_max':.9,'temporal':'all_samples'},
 {'id':'reveal','min_visible':.92,'max_center_shift':1.,'height_min':.035,'height_max':.9,'temporal':'endpoint'},
 {'id':'conceal','max_visible':.12,'max_center_shift':1.,'height_min':.035,'height_max':.9,'temporal':'endpoint'},
 {'id':'context','min_visible':.75,'max_center_shift':1.,'height_min':.05,'height_max':.25,'temporal':'endpoint'},
 {'id':'detail','min_visible':.75,'max_center_shift':1.,'height_min':.35,'height_max':.8,'temporal':'endpoint'}]
FAMILIES=['moving_target','crossing_occluder','two_opposing_targets','lateral_reveal']

def emit(f,x):f.write(json.dumps(x,ensure_ascii=False,allow_nan=False)+'\n')
def rot_z(a):
    a=math.radians(a);return np.array([[math.cos(a),-math.sin(a),0],[math.sin(a),math.cos(a),0],[0,0,1.]])
def cam_at(base,a,t):
    right=np.array([1.,0.,0.]);forward=np.array([0.,1.,0.]);up=np.array([0.,0.,1.]);R=rot_z(a['yaw_deg']*t)
    return {'p':np.array(base)+right*a['dx_m']*t,'right':R@right,'forward':R@forward,'up':up,'focal':34*(1+(a['focal_factor']-1)*t)}
def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True);s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=8;s.cycles.use_denoising=False;s.cycles.device='CPU'
    s.render.resolution_x=W;s.render.resolution_y=H;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB'
    s.view_settings.view_transform='Standard';s.view_settings.look='Medium High Contrast';s.world=bpy.data.worlds.new('World');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[1].default_value=.2
    data=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',data);s.collection.objects.link(camera);s.camera=camera;data.sensor_width=36.;data.sensor_fit='HORIZONTAL';data.clip_start=.05
    ld=bpy.data.lights.new('Key','AREA');light=bpy.data.objects.new('Key',ld);s.collection.objects.link(light);light.location=(-3,-4,6);ld.energy=1100;ld.size=5.
    light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler();return s

def make_mesh(kind,name,center,scale,color):
    if kind=='sphere':bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,radius=1.)
    elif kind=='cylinder':bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=1.,depth=2.)
    elif kind=='cone':bpy.ops.mesh.primitive_cone_add(vertices=20,radius1=1.,radius2=.3,depth=2.)
    else:bpy.ops.mesh.primitive_cube_add(size=2.)
    ob=bpy.context.object;ob.name=name;ob.location=center;ob.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mat=bpy.data.materials.new(name);mat.diffuse_color=(*color,1.);mat.use_nodes=True
    node=mat.node_tree.nodes.get('Principled BSDF');node.inputs['Base Color'].default_value=(*color,1.);node.inputs['Roughness'].default_value=.55;ob.data.materials.append(mat)
    return ob

def mesh_samples(ob,rng,n=192):
    mesh=ob.data;mesh.calc_loop_triangles();verts=np.array([v.co[:] for v in mesh.vertices]);tri=np.array([t.vertices[:] for t in mesh.loop_triangles]);xyz=verts[tri]
    area=np.linalg.norm(np.cross(xyz[:,1]-xyz[:,0],xyz[:,2]-xyz[:,0]),axis=1)/2
    picked=rng.choice(len(tri),n,p=area/area.sum());uv=rng.random((n,2));su=np.sqrt(uv[:,0]);weights=np.stack([1-su,su*(1-uv[:,1]),su*uv[:,1]],axis=1)
    samples=np.sum(xyz[picked]*weights[:,:,None],axis=1)
    bvh=BVHTree.FromPolygons([Vector(v) for v in verts],tri.tolist(),all_triangles=True)
    return verts,tri,samples,bvh

def make_scene(index):
    rng=np.random.default_rng(2026102400+index);family=FAMILIES[index%4];group=index//4;split=['train']*10+['validation']*3+['test']*3;split=split[group%16]
    for ob in list(bpy.context.scene.objects):
        if ob.type=='MESH':bpy.data.objects.remove(ob,do_unlink=True)
    objects=[];targets=[]
    def add(kind,name,p,sz,color,velocity=(0,0,0),target=False,collide=True):
        ob=make_mesh(kind,name,p,sz,color);v,tri,points,bvh=mesh_samples(ob,rng) if target else (None,None,None,None)
        entry={'ob':ob,'name':name,'kind':kind,'p':np.array(p,float),'size':np.array(sz)*2,'v':np.array(velocity,float),'target':target,'collide':collide,'verts':v,'samples':points,'bvh':bvh}
        objects.append(entry)
        if target:targets.append(entry)
    shapes=['sphere','cylinder','cone']
    shape=shapes[int(rng.integers(3))];height=float(rng.uniform(.38,.72));speed=float(rng.uniform(.7,1.45))*([-1,1][index%2])
    base=[0.,-float(rng.uniform(4.2,5.8)),1.25];x0=float(rng.uniform(-.25,.25))
    add(shape,'target_A',[x0,0.,1.25],[.27,.27,height],[.85,.13,.05],(speed,0,0) if family in ['moving_target','two_opposing_targets'] else (0,0,0),True)
    add(shapes[(shapes.index(shape)+1)%3],'target_B',[float(rng.uniform(.9,1.45)),.35,1.25],[.24,.24,height*.85],[.04,.32,.85],(-speed,0,0) if family=='two_opposing_targets' else (0,0,0),True)
    if family=='crossing_occluder':
        vx=float(rng.uniform(1.5,2.4));add('box','occluder',[-vx*.5,-1.0,1.25],[.28,.12,.9],[.12,.18,.16],(vx,0,0))
    elif family=='lateral_reveal':add('box','occluder',[x0+.12,-1.1,1.25],[.30,.12,.85],[.2,.22,.2])
    else:add('box','screen',[float(rng.choice([-1,1])*rng.uniform(1.7,2.4)),-1.2,1.],[.35,.2,1.],[.16,.24,.14])
    for j in range(3):
        add(shapes[int(rng.integers(3))],'prop_'+str(j),[float(rng.uniform(-3,3)),float(rng.uniform(1.3,3.)),float(rng.uniform(.5,1.2))],[float(rng.uniform(.15,.5))]*3,rng.uniform(.05,.6,3).tolist())
    add('box','backdrop',[0,4,2],[5,.1,2.5],rng.uniform(.15,.4,3).tolist(),collide=False)
    add('box','floor',[0,0,-.12],[8,9,.1],[.3,.3,.3],collide=False)
    return {'id':f'cc20-t-{index:05d}','origin_group':f'cc20-dynamic-arrangement-{index:05d}','split':split,'family':family,'objects':objects,'targets':targets,'base':base,
      'seed':2026102400+index,'constraints':{'translation_available':index%5!=0,'optical_zoom_available':index%4!=0,'radius_m':.15},'new_scene_geometry':True}

def position(scene,t):
    for e in scene['objects']:e['ob'].location=(e['p']+e['v']*t).tolist()
    bpy.context.view_layer.update()

def projection(cam,points):
    rel=points-cam['p'];z=rel@cam['forward'];fx=W*cam['focal']/36.;xy=np.stack([.5+fx*(rel@cam['right'])/np.maximum(z,1e-9)/W,.5-fx*(rel@cam['up'])/np.maximum(z,1e-9)/H],axis=1)
    return xy,z

def measure(scene,cam,t):
    position(scene,t);s=bpy.context.scene;deps=bpy.context.evaluated_depsgraph_get();results=[]
    for e in scene['targets']:
        pos=e['p']+e['v']*t;points=e['samples']+pos;xy,z=projection(cam,points);self_front=0;visible=0;valid_taps=[];visible_depth=[]
        for k,p in enumerate(points):
            direction=p-cam['p'];dist=float(np.linalg.norm(direction));d=direction/dist
            loc,n,fi,depth=e['bvh'].ray_cast(Vector(cam['p']-pos),Vector(d),dist+.01)
            if loc is None or abs(depth-dist)>.003:continue
            self_front+=1
            if z[k]<=.05 or not np.all((xy[k]>=0)&(xy[k]<=1)):continue
            hit,loc,n,fi,ob,_=s.ray_cast(deps,Vector(cam['p']),Vector(d),distance=dist+.01)
            if hit and ob==e['ob'] and abs(float((loc-Vector(cam['p'])).length)-dist)<.004:
                visible+=1;valid_taps.append(xy[k].tolist());visible_depth.append(dist)
        vertices=e['verts']+pos;corners,zz=projection(cam,vertices);low=np.min(corners,axis=0);high=np.max(corners,axis=0);height=float(high[1]-low[1]);center=((low+high)/2).tolist()
        retained=bool(np.all(zz>.05) and np.all(low>=0) and np.all(high<=1))
        results.append({'subject':e['name'],'visible_surface_fraction':visible/self_front if self_front else None,'sample_denominator':self_front,'visible_samples':visible,
          'center_xy':center,'bbox_xyxy':[float(low[0]),float(low[1]),float(high[0]),float(high[1])],'height':height,'fully_in_frame':retained,
          'tap_xy':valid_taps[len(valid_taps)//2] if valid_taps else None,'median_visible_range_m':float(np.median(visible_depth)) if visible_depth else None})
    return results

def feasible(scene,a):
    c=scene['constraints']
    if a['dx_m'] and not c['translation_available']:return False
    if a['focal_factor']!=1 and not c['optical_zoom_available']:return False
    p=np.array(scene['base']);end=p+np.array([a['dx_m'],0,0]);radius=c['radius_m']
    for e in scene['objects']:
        if not e['collide']:continue
        start=p-e['p'];delta=end-p-e['v'];half=e['size']/2+radius;tlo,thi=0.,1.
        for k in range(3):
            if abs(delta[k])<1e-9:
                if abs(start[k])>half[k]:tlo,thi=1.,0.;break
            else:
                q0=(-half[k]-start[k])/delta[k];q1=(half[k]-start[k])/delta[k];tlo=max(tlo,min(q0,q1));thi=min(thi,max(q0,q1))
            if tlo>thi:break
        if tlo<=thi:return False
    return True

def render(s,scene,cam,t,path):
    position(scene,t);mat=np.eye(4);mat[:3,0]=cam['right'];mat[:3,1]=cam['up'];mat[:3,2]=-cam['forward'];mat[:3,3]=cam['p'];s.camera.matrix_world=Matrix(mat.tolist());s.camera.data.lens=cam['focal'];s.cycles.seed=scene['seed']
    path.parent.mkdir(parents=True,exist_ok=True);s.render.filepath=str(path.resolve());bpy.ops.render.render(write_still=True)
    with Image.open(path) as im:rgb=np.asarray(im.convert('RGB'));assert rgb.shape==(H,W,3)
    Image.fromarray(rgb).save(path,compress_level=6);return digest(path)

def succeeds(measurements,subject,g,initial):
    seq=[m[subject] for m in measurements];seq=seq if g['temporal']=='all_samples' else seq[-1:]
    for m in seq:
        if m['visible_surface_fraction'] is None or not m['fully_in_frame']:return False
        if not g['height_min']<=m['height']<=g['height_max']:return False
        if 'min_visible' in g and m['visible_surface_fraction']<g['min_visible']:return False
        if 'max_visible' in g and m['visible_surface_fraction']>g['max_visible']:return False
        if np.linalg.norm(np.array(m['center_xy'])-initial['center_xy'])>g['max_center_shift']:return False
    return True

def run(shard,shards,count):
    label=f'cc20-temporal-{shard:02d}';root=Path(label);root.mkdir(exist_ok=False);s=setup();stats=collections.Counter();rows=[];outs=[];scene_rows=[]
    write_json(root/'ACTIONS.json',ACTIONS);write_json(root/'GOALS.json',GOALS)
    with (root/'outcomes.jsonl').open('w') as fo:
        for index in range(shard,count,shards):
            scene=make_scene(index);oid=scene['id'];history=[]
            for i,t in enumerate([-.4,-.2,0.]):
                p=root/'media'/oid/f'prefix_{i}.png';h=render(s,scene,cam_at(scene['base'],ACTIONS[0],0),t,p);history.append({'path':str(p.relative_to(root)),'t_s':t,'sha256':h});stats['rgb_files']+=1
            first=measure(scene,cam_at(scene['base'],ACTIONS[0],0),0);states=[]
            for j,a in enumerate(ACTIONS):
                series=[];media=[]
                for t in TIMES:
                    cam=cam_at(scene['base'],a,t);series.append(measure(scene,cam,t))
                    if t in [.5,1.]:
                        p=root/'media'/oid/f'a{j:02d}_t{t}.png';h=render(s,scene,cam,t,p);media.append({'path':str(p.relative_to(root)),'t_s':t,'sha256':h});stats['rgb_files']+=1
                physical=feasible(scene,a);states.append({'series':series,'feasible':physical,'media':media})
                emit(fo,{'origin_group':scene['origin_group'],'scene_id':oid,'split':scene['split'],'action':a,'times':TIMES,'measurements':series,'path_feasible':physical,'after_media':media,'authority':'Blender_scene_and_mesh_raycast_surface_samples','not_pixel_area_fraction':True})
                stats['action_sequences']+=1;stats['measurement_states']+=len(TIMES)
            winners={}
            for subject in [0,1]:
                for goal in GOALS+[None]:
                    success=[bool(st['feasible'] and succeeds(st['series'],subject,goal,first[subject])) if goal else False for st in states]
                    available=[(not a['dx_m'] or scene['constraints']['translation_available']) and (a['focal_factor']==1 or scene['constraints']['optical_zoom_available']) for a in ACTIONS]
                    usable=first[subject]['tap_xy'] is not None;good=[j for j,x in enumerate(success) if x];best=min(good,key=lambda j:(ACTIONS[j]['cost'],j)) if good and usable and goal else None
                    decision='ask' if goal is None and usable else 'abstain' if best is None else 'keep' if best==0 else 'recommend'
                    rid=oid+':'+str(subject)+':'+(goal['id'] if goal else 'missing_intent')
                    rows.append({'record_id':rid,'origin_group':scene['origin_group'],'split':scene['split'],'observations':{'history':history,'subject_tap_xy':first[subject]['tap_xy'],'intent':goal,'equipment':scene['constraints'],'candidate_actions':ACTIONS,'candidate_available':available,'observation_cutoff_s':0.},
                      'provenance':{'source':'own_procedural_mesh_simulator','seed':scene['seed'],'family':scene['family'],'intent_origin':'predeclared_simulator_task','human_utility':None,'camera_motion_gt_not_in_inputs':True}})
                    outs.append({'record_id':rid,'decision':decision,'target_action_index':best,'action_success':success,'loss_masks':{'action_success':[bool(goal and usable and av) for av in available],'decision':True,'human_utility':False,'real_action_performed':False},'human_utility':None,'real_action_performed':None,'simulated_goal_achieved':True if best is not None else None})
                    stats['policy_rows']+=1;stats[decision]+=1
                    if best is not None:winners[(subject,goal['id'])]=best
                    if goal:
                        for j,st in enumerate(states):
                            final=st['series'][-1][subject];mid=st['series'][2][subject]
                            stats['endpoint_clear_mid_occluded']+=int(final['visible_surface_fraction'] is not None and mid['visible_surface_fraction'] is not None and final['visible_surface_fraction']>=.9 and mid['visible_surface_fraction']<.5)
            for g in GOALS:
                if (0,g['id']) in winners and (1,g['id']) in winners and winners[(0,g['id'])]!=winners[(1,g['id'])]:stats['different_action_after_subject_switch']+=1
            objects=[{'name':e['name'],'kind':e['kind'],'initial_position_m':e['p'].tolist(),'velocity_m_s':e['v'].tolist(),'aabb_dimensions_m':e['size'].tolist(),'selected_candidate':e['target']} for e in scene['objects']]
            scene_rows.append({'id':oid,'origin_group':scene['origin_group'],'split':scene['split'],'family':scene['family'],'seed':scene['seed'],'camera_position':scene['base'],'objects':objects,'camera_sensor_mm':36.,'resolution':[W,H]})
            stats['scenes']+=1;stats['split:'+scene['split']]+=1;stats['family:'+scene['family']]+=1
            for data in [bpy.data.meshes,bpy.data.materials]:
                for item in list(data):
                    if item.users==0:data.remove(item)
            print('CC20_TEMPORAL_PROGRESS '+json.dumps({'shard':shard,'scenes':stats['scenes']}),flush=True)
    for filename,values in [('inputs.jsonl',rows),('targets.jsonl',outs),('scenes.jsonl',scene_rows)]:
        with (root/filename).open('w') as f:
            for row in values:emit(f,row)
    sys.path.insert(0,str(Path(__file__).resolve().parent));from temporal_reader import audit
    report=audit(root);report.update(stats=dict(stats),full_cameracoach_training_ready=False,human_responses=0,models_executed=0,
      limitations=['Procedural geometric objects, no human-expression or artistic utility labels','5 temporal sample instants are not continuous visibility guarantees','192 surface samples, not exact pixel-area visibility','Scene-level split; primitive shape families are shared across splits','Conservative swept sphere/AABB feasibility does not represent operator body clearance','Tap initialized from simulator visible surface; noisy real subject selection not validated'])
    write_json(root/'QA.json',report);code=root/'reproduction';code.mkdir()
    for p in Path(__file__).parent.glob('temporal*.py'):shutil.copyfile(p,code/p.name)
    (root/'README_RU.md').write_text('# CC20: временные действия\nНовые реальные Blender-рендеры процедурных mesh-объектов. Два разных выбранных субъекта в неизменной RGB-истории. Перекрытия проверены на пяти моментах времени, а не только в конце. Никаких эстетических или human-utility меток.\n\nРежим чтения: temporal_reader.batches(root, split="train"). Послекадры находятся только в outcomes.jsonl, запрещены как вход политики. Полный CameraCoach DoD не закрыт этим компонентом.\n')
    print('CC20_TEMPORAL_QA '+json.dumps(report),flush=True);package(root,label)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--shards',type=int,default=4);p.add_argument('--count',type=int,default=128);a=p.parse_args();run(a.shard,a.shards,a.count)
