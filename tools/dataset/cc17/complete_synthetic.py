"""CameraCoach CC18: complete data-only physical-action component corpus.
No learned model, API teacher, or human-utility labels. Procedural geometry only.
The eight scene families remain explicit geometric proxies, not photoreal humans.
All candidate states are rendered; inputs never include counterfactual geometry.
"""
from __future__ import annotations
import argparse, collections, contextlib, copy, hashlib, json, math, os, random, shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps
import bpy
import synthetic_physical as S
from acquire import digest, write_json
from release_pack import package

S.W,S.H=256,192
W,H=S.W,S.H
SCHEMA='cameracoach.component.v18.1'
# Topology assignment is fixed before outcome generation; test templates are not
# used to tune thresholds. Different seeds from one topology stay in one split.
TOPOLOGIES=['open_table','shelving','doorway','parallel_corridor','staggered_blocks','overhead_frame','split_islands','slalom_columns']
SPLITS=['train']*5+['validation']+['test']*2
BASE_GOALS=copy.deepcopy(S.GOALS)
GOALS=BASE_GOALS+[
 {'id':'subject_midtones','height_min':.04,'height_max':.9,'visible_min':.65,'luminance_min':.30,'luminance_max':.65},
 {'id':'preserve_dark_subject','height_min':.04,'height_max':.9,'visible_min':.65,'luminance_min':.015,'luminance_max':.13},
]
ACTIONS=copy.deepcopy(S.ACTIONS)
for a in ACTIONS:a.update(exposure_ev=0.,fill_watts=0.,key_shift_m=[0.,0.,0.],duration_s=1.0 if a['id']!='keep' else 0.)
for ev in [-2.,-1.,1.,2.]:ACTIONS.append({'id':'exposure_'+str(ev),'translation':[0.,0.,0.],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'cost':.2+abs(ev)/10,'exposure_ev':ev,'fill_watts':0.,'key_shift_m':[0.,0.,0.],'duration_s':.4})
for watts in [100.,400.]:ACTIONS.append({'id':'fill_'+str(watts),'translation':[0.,0.,0.],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'cost':1.5+watts/1000,'exposure_ev':0.,'fill_watts':watts,'key_shift_m':[0.,0.,0.],'duration_s':2.})
for x in [-2.,2.]:ACTIONS.append({'id':'key_shift_'+str(x),'translation':[0.,0.,0.],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'cost':2.,'exposure_ev':0.,'fill_watts':0.,'key_shift_m':[x,0.,0.],'duration_s':2.})
ACTIONS.append({'id':'wait_1s','translation':[0.,0.,0.],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'cost':.15,'exposure_ev':0.,'fill_watts':0.,'key_shift_m':[0.,0.,0.],'duration_s':1.})


def dump_line(f,obj):f.write(json.dumps(obj,ensure_ascii=False,allow_nan=False)+'\n')

def build_scene(index):
    scene=S.make_scene(10000+index)
    family_index=index%8;family=S.FAMILIES[family_index]
    template=(index//8)%8;variant=index//64
    rng=random.Random(18000000+index)
    scene.update(origin_id=f'cc18-{index:06d}',seed=18000000+index,family=family,
        topology=TOPOLOGIES[template],topology_id=f'{family_index}:{template}',
        layout_group=f'cc18-topology-{family_index}-{template}',split=SPLITS[template],variant=variant)
    # Regenerate room layout, not merely materials. Preserve selected proxies.
    boxes=[b for b in scene['boxes'] if b['selected'] or b.get('noncolliding')]
    def add(center,size,color=None,noncolliding=False):
        boxes.append({'id':0,'center':list(center),'size':list(size),'selected':False,
            'color':color or [rng.uniform(.06,.75) for _ in range(3)],'noncolliding':noncolliding})
    if template==0:
        add([0,.3,.18],[3.5,1.8,.18]);add([-1.6,2.,1.1],[.4,.4,2.2])
    elif template==1:
        for z in [.4,1.2,2.1]:add([0,2.4,z],[5.,.45,.12])
        for x in [-2.,0.,2.]:add([x,2.4,1.2],[.12,.6,2.5])
    elif template==2:
        for x in [-1.3,1.3]:add([x,-1.4,1.2],[.8,.3,2.4])
        add([0,-1.4,2.5],[3.4,.3,.25])
    elif template==3:
        for x in [-1.7,1.7]:add([x,0.,1.4],[.18,7.,2.8])
    elif template==4:
        for j in range(5):add([(-1 if j%2 else 1)*rng.uniform(.5,1.4),-2+j*.8,.6],[.5,.4,rng.uniform(.6,1.7)])
    elif template==5:
        add([0,-.8,2.2],[3.6,.2,.2]);add([-1.7,-.8,1.1],[.15,.25,2.2]);add([1.7,-.8,1.1],[.15,.25,2.2])
    elif template==6:
        for x in [-1.7,1.7]:
            for y in [-1.,1.5]:add([x,y,.45],[1.3,1.2,.9])
    else:
        for j in range(6):add([(-1 if j%2 else 1)*(.7+.1*j),-2.5+j*.8,1.0],[.24,.24,2.0])
    if index%4:
        add([rng.uniform(.12,.42),-1.4,.9],[rng.uniform(.28,.65),.13,1.8])
    # Physically distinct camera/subject dimensions and finite barriers.
    for b in boxes:
        if b['selected']:
            b['size']=[float(v*rng.uniform(.85,1.15)) for v in b['size']]
    add([0,4.,1.5],[10.,.15,3.],color=[rng.uniform(.12,.65)]*3)
    for i,b in enumerate(boxes):b['id']=i+1
    scene['boxes']=boxes
    # Same exogenous actor trajectory for every action. Native simulator clock.
    scene['subject_velocity_m_s']=[rng.choice([-1,1])*rng.uniform(.35,.85),0.,0.] if family_index==7 else [0.,0.,0.]
    scene['base_exposure_ev']=rng.choice([-1.,0.,1.])
    scene['key_position']=[rng.uniform(-3.,3.),rng.choice([-3.,1.8]),rng.uniform(3.5,5.5)]
    scene['key_watts']=rng.uniform(200.,900.)
    scene['world_strength']=rng.uniform(.015,.18)
    scene['constraints']={'allow_translation':index%5!=0,'allow_optical_zoom':index%3!=0,
      'allow_exposure':True,'fill_light_available':index%3==1,'movable_key_light':index%4==2,
      'camera_swept_sphere_radius_m':.15,'focal_bounds_mm':[17.,85.],
      'workspace_bounds_m':{'x':[-4.5,4.5],'y':[-8.5,2.],'z':[.25,3.]}}
    return scene

def boxes_at(scene,t):
    out=copy.deepcopy(scene['boxes']);v=np.asarray(scene['subject_velocity_m_s'])
    for b in out:
        if b['selected']:b['center']=(np.asarray(b['center'])+v*t).tolist()
    return out

def permitted(a,c):
    return bool((c['allow_translation'] or not any(a['translation'])) and
       (c['allow_optical_zoom'] or a['focal_factor']==1) and
       (c['fill_light_available'] or not a['fill_watts']) and
       (c['movable_key_light'] or not any(a['key_shift_m'])))

def continuous_feasible(scene,cam,a):
    c=scene['constraints'];p=scene['camera']['position'];q=cam['position'];bounds=c['workspace_bounds_m']
    if any(not(bounds[k][0]<=q[i]<=bounds[k][1]) for i,k in enumerate(['x','y','z'])):return False
    if not c['focal_bounds_mm'][0]<=cam['focal_mm']<=c['focal_bounds_mm'][1]:return False
    if not permitted(a,c):return False
    # Continuous relative-motion slab intersection for all moving/static boxes.
    for b in scene['boxes']:
        if b.get('noncolliding'):continue
        center=np.asarray(b['center']);half=np.asarray(b['size'])/2+c['camera_swept_sphere_radius_m']
        velocity=np.asarray(scene['subject_velocity_m_s']) if b['selected'] else np.zeros(3)
        start=p-center;delta=(q-p)-velocity*a['duration_s'];t0,t1=0.,1.
        for k in range(3):
            if abs(delta[k])<1e-12:
                if abs(start[k])>half[k]:t0,t1=1.,0.;break
            else:
                lo=(-half[k]-start[k])/delta[k];hi=(half[k]-start[k])/delta[k]
                t0=max(t0,min(lo,hi));t1=min(t1,max(lo,hi))
            if t0>t1:break
        if t0<=t1:return False
    return True

def normals_for_ids(cam,boxes,ids,depth):
    ds=S.rays(cam);pts=cam['position']+ds*np.where(np.isfinite(depth),depth,0)[...,None]
    normals=np.zeros((H,W,3),np.float32)
    for b in boxes:
        mask=ids==b['id']
        if not mask.any():continue
        rel=(pts[mask]-np.asarray(b['center']))/(np.asarray(b['size'])/2)
        axes=np.argmax(np.abs(rel),axis=1);n=np.zeros_like(rel);n[np.arange(len(n)),axes]=np.sign(rel[np.arange(len(n)),axes]);normals[mask]=n
    return normals

def state_render(s,scene,a,folder):
    cam=S.apply(scene['camera'],a);boxes=boxes_at(scene,a['duration_s'])
    m,ids,depth,alone=S.measure(cam,boxes)
    S.load_boxes(s,boxes);S.set_camera(s,cam)
    s.view_settings.exposure=scene['base_exposure_ev']+a['exposure_ev']
    s.world.node_tree.nodes['Background'].inputs[1].default_value=scene['world_strength']
    key=s.objects.get('key');key.location=np.asarray(scene['key_position'])+np.asarray(a['key_shift_m']);key.data.energy=scene['key_watts']
    fill=s.objects.get('fill')
    if fill is None:
        ld=bpy.data.lights.new('fill','AREA');fill=bpy.data.objects.new('fill',ld);s.collection.objects.link(fill);ld.size=2.
    fill.location=scene['camera']['position']+np.array([0.,0.,1.]);fill.data.energy=a['fill_watts']
    fill.rotation_euler=(np.asarray([0,0,1])-np.asarray(fill.location)).tolist() if False else (0.,0.,0.)
    # AREA points along local -Z; point towards the selected subject.
    target=np.mean([b['center'] for b in boxes if b['selected']],axis=0)
    fill.rotation_euler=(S.Vector(target)-fill.location).to_track_quat('-Z','Y').to_euler()
    key.rotation_euler=(S.Vector(target)-key.location).to_track_quat('-Z','Y').to_euler()
    s.cycles.seed=scene['seed']
    folder.mkdir(parents=True,exist_ok=True);png=folder/'rgb.png';s.render.filepath=str(png.resolve())
    bpy.context.view_layer.update();bpy.ops.render.render(write_still=True)
    with Image.open(png) as im:rgb=np.asarray(im.convert('RGB'));assert im.size==(W,H)
    selection=np.isin(ids,[b['id'] for b in boxes if b['selected']]);lum=(rgb.astype(np.float32)/255)@np.array([.2126,.7152,.0722])
    m['subject_display_luminance_median']=float(np.median(lum[selection])) if selection.any() else None
    m['subject_display_clipping_fraction']=float(np.mean(np.max(rgb[selection],axis=1)>=254)) if selection.any() else None
    geometry=folder/'geometry.npz'
    np.savez_compressed(geometry,instance_id=ids,selected_visible=selection,selected_amodal=alone>0,
        range_m=np.where(np.isfinite(depth),depth,0).astype(np.float32),depth_valid=np.isfinite(depth),
        normals_world=normals_for_ids(cam,boxes,ids,depth).astype(np.float16))
    bad=S.check_rays(s,cam,ids,depth,scene['seed']+int(abs(a['cost'])*100))
    if bad:raise AssertionError({'origin':scene['origin_id'],'action':a['id'],'ray_mismatch':bad})
    # Explicit intrinsics match Blender HORIZONTAL sensor and pixel centers.
    fx=W*cam['focal_mm']/36.
    return {'metrics':m,'camera':S.serialize(cam),'K':[[fx,0,W/2],[0,fx,H/2],[0,0,1]],
       't_seconds':a['duration_s'],'path_feasible':continuous_feasible(scene,cam,a),
       'rgb_path':str(png),'rgb_sha256':digest(png),'geometry_path':str(geometry),'geometry_sha256':digest(geometry),
       'ray_checks':48},rgb

def goal_success(m,g):
    ok=S.succeeds(m,g)
    value=m.get('subject_display_luminance_median')
    if 'luminance_min' in g:ok=ok and value is not None and g['luminance_min']<=value<=g['luminance_max']
    return bool(ok)

def initial_subject(geo):
    with np.load(geo,allow_pickle=False) as z:
        y,x=np.where(z['selected_visible'])
    if not len(x):return {'tap_xy':None,'bbox_xyxy':None,'initialization':'simulator_oracle_visible_region','visible':False}
    k=len(x)//2
    return {'tap_xy':[(float(x[k])+.5)/W,(float(y[k])+.5)/H],
        'bbox_xyxy':[float(x.min()/W),float(y.min()/H),float((x.max()+1)/W),float((y.max()+1)/H)],
        'initialization':'simulator_oracle_visible_region','visible':True}

def validate_and_batch(root):
    inputs=[json.loads(l) for l in (root/'inputs.jsonl').read_text().splitlines()]
    targets=[json.loads(l) for l in (root/'targets.jsonl').read_text().splitlines()]
    assert len(inputs)==len(targets)
    target_map={t['record_id']:t for t in targets};assert len(target_map)==len(targets)
    groups=collections.defaultdict(set);seen=set();batches=0
    for offset in range(0,len(inputs),16):
        block=inputs[offset:offset+16];rgb=[];tap=[];availability=[];labels=[];masks=[]
        for row in block:
            assert set(row)=={'schema','record_id','task_type','origin_group','split','observations','provenance'}
            obs=row['observations'];assert set(obs)=={'rgb','selected_subject','intent','protected_style','constraints','action_candidates','candidate_available','observation_cutoff_s'}
            assert obs['observation_cutoff_s']==0. and obs['rgb'].endswith('/state_00/rgb.png')
            p=root/obs['rgb'];assert p.is_file()
            with Image.open(p) as im:im=ImageOps.exif_transpose(im).convert('RGB');rgb.append(np.asarray(im.resize((224,224),Image.Resampling.BILINEAR),dtype=np.float32)/255.)
            xy=obs['selected_subject']['tap_xy'];tap.append(xy if xy is not None else [0.,0.]);availability.append(obs['candidate_available'])
            t=target_map[row['record_id']];labels.append(t['action_success']);masks.append(t['loss_masks']['action_success'])
            assert len(t['action_success'])==len(ACTIONS) and len(t['loss_masks']['action_success'])==len(ACTIONS)
            assert t['human_utility'] is None and not t['loss_masks']['human_utility']
            assert t['decision'] in ['keep','recommend','ask','abstain']
            if t['target_action_index'] is not None:
                k=t['target_action_index'];assert t['action_success'][k] and obs['candidate_available'][k]
            assert row['record_id'] not in seen;seen.add(row['record_id']);groups[row['split']].add(row['origin_group'])
        X=np.stack(rgb).transpose(0,3,1,2);Y=np.asarray(labels,dtype=np.float32);M=np.asarray(masks,dtype=bool)
        assert np.isfinite(X).all() and X.shape[1:]==(3,224,224) and Y.shape==M.shape
        assert np.isfinite(Y).all();batches+=1
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    return {'rows_traversed':len(inputs),'actual_numpy_batches':batches,'batch_size':16,'image_layout':'NCHW','image_size':[224,224],
      'input_target_schema_disjoint':True,'post_action_input_paths':0,'origin_group_overlap':0,'human_utility_losses':0,
      'preprocessing':'RGB EXIF transpose then independent XY bilinear resize; no exact Metal/CoreML parity claim','model_calls':0}

def run(shard,shards,count):
    label=f'cc18-synthetic-{shard:02d}';root=Path('complete')/label;root.mkdir(parents=True,exist_ok=True)
    s=S.setup_blender();s.cycles.samples=8;s.render.image_settings.color_depth='8'
    stats=collections.Counter();independent_groups=set();manifest=[];contrasts=0;pixel_hashes=collections.defaultdict(set)
    for name,data in [('actions.json',ACTIONS),('goals.json',GOALS),('split_definition.json',{'topologies':TOPOLOGIES,'assignments':SPLITS,'seed':18000000})]:write_json(root/name,data)
    with open(root/'inputs.jsonl','w') as fi,open(root/'targets.jsonl','w') as ft,open(root/'counterfactuals.jsonl','w') as fc,open(root/'scenes.jsonl','w') as fs:
        for index in range(shard,count,shards):
            scene=build_scene(index);origin=scene['origin_id'];states=[]
            for j,a in enumerate(ACTIONS):
                v,pixels=state_render(s,scene,a,root/'media'/origin/f'state_{j:02d}')
                for k in ['rgb_path','geometry_path']:v[k]=str(Path(v[k]).relative_to(root))
                v.update(action_id=a['id'],origin_id=origin,split=scene['split']);states.append(v);dump_line(fc,v)
                stats['rendered_rgb']+=1;stats['ray_checks']+=v['ray_checks']
                if j==0:pixel_hashes[hashlib.sha256(pixels.tobytes()).hexdigest()].add(scene['split'])
            subject=initial_subject(root/states[0]['geometry_path']);available=[permitted(a,scene['constraints']) for a in ACTIONS]
            decisions={}
            for goal in GOALS+[None]:
                success=[bool(v['path_feasible'] and goal_success(v['metrics'],goal)) if goal else False for v in states]
                good=[j for j,v in enumerate(success) if v and available[j]]
                k=min(good,key=lambda j:(ACTIONS[j]['cost'],ACTIONS[j]['id'])) if good and subject['visible'] and goal else None
                mode='ask' if goal is None and subject['visible'] else 'abstain' if k is None else 'keep' if k==0 else 'recommend'
                record=origin+':'+(goal['id'] if goal else 'missing_intent')
                obs={'rgb':states[0]['rgb_path'],'selected_subject':subject,'intent':goal,'protected_style':('dark_subject_tone' if goal and goal['id']=='preserve_dark_subject' else None),
                     'constraints':scene['constraints'],'action_candidates':ACTIONS,'candidate_available':available,'observation_cutoff_s':0.}
                dump_line(fi,{'schema':SCHEMA,'record_id':record,'task_type':'candidate_action_ranking','origin_group':scene['layout_group'],'split':scene['split'],'observations':obs,
                  'provenance':{'source':'own_procedural_simulator','scene_id':origin,'intent_origin':'simulator_task_definition_before_outcomes','label_authority':'synthetic_task_oracle',
                  'rgb_sha256':states[0]['rgb_sha256'],'rights_scope':'procedural_outputs_no_external_assets','renderer':'Blender '+bpy.app.version_string,'generator_sha256':digest(Path(__file__))}})
                dump_line(ft,{'record_id':record,'decision':mode,'target_action_index':k,'action_success':success,
                  'action_feasible':[v['path_feasible'] for v in states],'successful_action_ids':[ACTIONS[j]['id'] for j in good],
                  'label_authority':'synthetic_task_oracle','tie_break':'minimum predeclared effort cost, not human preference',
                  'action_proposed':ACTIONS[k]['id'] if k is not None else None,'action_performed':None,
                  'goal_achieved':success[k] if k is not None else None,'outcome_preferred':None,'comparison_validity':'known simulator counterfactuals only',
                  'causal_attribution':'single camera/light/control action with explicit deterministic exogenous motion; no real causal claim',
                  'human_utility':None,'loss_masks':{'decision':True,'action_success':[bool(goal and subject['visible'] and av) for av in available],
                    'action_feasible':True,'action_performed':False,'goal_achieved':k is not None,'outcome_preferred':False,'human_utility':False}})
                stats['policy_rows']+=1;stats[mode]+=1
                if goal:decisions[goal['id']]=(k,success)
            for ga,gb in [('detail','context'),('expose','conceal'),('subject_midtones','preserve_dark_subject')]:
                ka,sa=decisions[ga];kb,sb=decisions[gb]
                if ka is not None and kb is not None and ka!=kb and not sa[kb] and not sb[ka]:contrasts+=1
            dump_line(fs,{**scene,'camera':S.serialize(scene['camera']),'goals_predeclared':GOALS,'supervision_limit':'physical framing, visibility and rendered pixel tone; no aesthetic, face, text-readability or human utility claim'})
            independent_groups.add(scene['layout_group']);stats['scene_configurations']+=1;stats['family:'+scene['family']]+=1;stats['split:'+scene['split']]+=1
            for mat in list(bpy.data.materials):
                if mat.users==0:bpy.data.materials.remove(mat)
            if stats['scene_configurations']%8==0:print('CC18_PROGRESS',shard,stats['scene_configurations'],flush=True)
    assert not any(len(v)>1 for v in pixel_hashes.values())
    consumer=validate_and_batch(root)
    stats.update({'opposing_successful_goal_pairs':contrasts,'conservative_topology_groups':len(independent_groups),'actions_per_scene':len(ACTIONS),'goals_plus_missing_intent':len(GOALS)+1})
    report={'schema':SCHEMA,'stats':dict(stats),'consumer':consumer,'model_execution':False,'real_human_responses':0,
      'dataset_scope':'synthetic physical-action component experiment only','full_cameracoach_training_ready':False,
      'not_proven':['real-world transfer','independent human usefulness','current MVP comparison','operational noisy subject initialization','exact Apple preprocessing parity'],
      'geometry':'procedural axis-aligned cuboid assemblies; eight proxy task families and eight different room topologies; heldout topologies excluded from train',
      'exposure_labels':'measured median of rendered display RGB within selected visible region, not lux or aesthetic judgement',
      'collision':'continuous relative-motion swept sphere/AABB conservative test; not operator body clearance',
      'asset_manifest':{'external_models':[],'external_textures':[],'external_fonts':[],'procedural_only':True}}
    write_json(root/'QA.json',report)
    (root/'README_RU.md').write_text('# CameraCoach: физические действия, CC18\n\nВсе исходные и все кандидатные состояния реально отрендерены Blender Cycles. Метки относятся к измеримому размеру, видимости, геометрическим препятствиям и уровню яркости пикселей, а не художественной ценности.\n\ninputs.jsonl — только исходное состояние, выбранная видимая область, заранее заданная цель и доступное оборудование. targets.jsonl и counterfactuals.jsonl не подавать в online policy. Нормали мировые, depth — дальность по лучу в метрах симулятора, а не z-depth.\n\nОбъекты процедурные геометрические прокси. Нет человеческих оценок, реальных iPhone interventions или доказанного переноса. Нельзя называть этот компонент всей готовой CameraCoach policy.\n\nИзображения 256x192; data-only consumer реально читает каждую запись и собирает NCHW 224x224 batch. Метры и время относятся к симулятору. Для реального устройства физическая доступность не даётся как oracle-input.\n')
    print('CC18_SUMMARY '+json.dumps(report),flush=True);package(root,label)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--shards',type=int,default=8);p.add_argument('--count',type=int,default=512);a=p.parse_args()
    run(a.shard,a.shards,a.count)
