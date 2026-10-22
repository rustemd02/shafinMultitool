"""Audited CC18 production data runner. No model execution.
Reuses deterministic Blender and independent AABB geometry, not learned labels.
A matched one-second horizon is used for every counterfactual, including keep.
"""
from __future__ import annotations
import argparse,collections,copy,hashlib,json,random,shutil
from pathlib import Path
import numpy as np
from PIL import Image
import bpy
import complete_synthetic as C
from acquire import digest,write_json
from release_pack import package
S=C.S
BASE_APPLY=S.apply

def local_apply(base,a):
    a=copy.deepcopy(a);v=np.asarray(a['translation'],float)
    a['translation']=(base['right']*v[0]+base['forward']*v[1]+base['up']*v[2]).tolist()
    return BASE_APPLY(base,a)
S.apply=local_apply
# The same exogenous evolution and observation horizon in ALL alternatives.
for a in C.ACTIONS:
    a['duration_s']=1.0
    a['translation_frame']='initial_camera_right_forward_up'

BASE_BUILD=C.build_scene

def build_scene(index):
    scene=BASE_BUILD(index);b=scene['boxes'];family=scene['family'];rng=random.Random(scene['seed']+77)
    def add(center,size,color):
        b.append({'id':len(b)+1,'center':center,'size':size,'selected':False,'color':color,'noncolliding':False})
    if family=='dialogue_proxy':
        add([1.0,.4,.72],[.48,.35,1.1],[.4,.12,.24]);add([1.,.4,1.48],[.3,.3,.35],[.7,.45,.3])
    if family=='hand_tool_proxy':
        add([-.48,.25,.9],[.18,.6,.17],[.7,.4,.27]);add([.7,.15,.55],[.8,.8,.15],[.24,.2,.17])
    scene['action_coordinate_frame']='camera_local_at_t0:right,forward,up'
    scene['counterfactual_horizon_s']=1.0
    scene['constraints']['one_second_action_execution_assumption']=True
    return scene
C.build_scene=build_scene
BASE_FEASIBLE=C.continuous_feasible

def feasible(scene,cam,a):
    if not BASE_FEASIBLE(scene,cam,a):return False
    if any(a['key_shift_m']):
        start=np.asarray(scene['key_position']);end=start+np.asarray(a['key_shift_m'])
        # Conservative swept envelope for actors during the one-second action.
        boxes=copy.deepcopy(scene['boxes'])
        for b in boxes:
            if b['selected']:
                v=np.asarray(scene['subject_velocity_m_s']);b['center']=(np.asarray(b['center'])+v*.5).tolist();b['size']=(np.asarray(b['size'])+np.abs(v)).tolist()
        if not S.segment_clear(start,end,boxes,.1):return False
    return True
C.continuous_feasible=feasible


def load_batch(root,rows,target_map):
    """Returns only numeric inputs plus separate supervised targets/loss masks.
    IDs, origins, filenames, future states and GT geometry never enter X.
    No training, feature extractor, gradient, or model calls occur here.
    """
    from PIL import ImageOps
    xs=[];subject=[];subject_valid=[];goals=[];goal_valid=[];candidates=[];available=[];labels=[];masks=[];decisions=[];optics=[];constraints=[];times=[]
    decision_names=['keep','recommend','ask','abstain']
    for row in rows:
        o=row['observations'];t=target_map[row['record_id']]
        assert all(h['t_seconds']<=0 for h in o['history']) and o['history'][-1]['t_seconds']==0
        frames=[]
        for h in o['history']:
            with Image.open(root/h['rgb']) as im:
                im=ImageOps.exif_transpose(im).convert('RGB').resize((224,224),Image.Resampling.BILINEAR)
                frames.append(np.asarray(im,dtype=np.float32).transpose(2,0,1)/255.)
        xs.append(np.stack(frames));times.append([h['t_seconds'] for h in o['history']])
        roi=o['selected_subject'];subject.append((roi['tap_xy'] or [0.,0.])+(roi['bbox_xyxy'] or [0.,0.,0.,0.]));subject_valid.append(roi['visible'])
        g=o['intent'];keys=['height_min','height_max','visible_min','visible_max','luminance_min','luminance_max']
        goals.append([float(g.get(k,0.)) if g else 0. for k in keys]);goal_valid.append([bool(g and k in g) for k in keys]+[g is not None])
        rng=random.Random(int(hashlib.sha256(row['record_id'].encode()).hexdigest()[:16],16));order=list(range(len(C.ACTIONS)));rng.shuffle(order)
        af=[]
        for j in order:
            a=C.ACTIONS[j];af.append(a['translation']+[a['pan_deg'],a['tilt_deg'],a['focal_factor'],a['exposure_ev'],a['fill_watts']]+a['key_shift_m']+[a['duration_s'],a['cost']])
        candidates.append(af);available.append([o['candidate_available'][j] for j in order]);labels.append([t['action_success'][j] for j in order]);masks.append([t['loss_masks']['action_success'][j] for j in order]);decisions.append(decision_names.index(t['decision']))
        optics.append([o['current_focal_mm'],*o['constraints']['focal_bounds_mm']])
        constraints.append([bool(o['constraints'][k]) for k in ['allow_translation','allow_optical_zoom','allow_exposure','fill_light_available','movable_key_light']])
    X={'rgb_history':np.stack(xs),'history_time_s':np.asarray(times,np.float32),'subject_tap_bbox':np.asarray(subject,np.float32),
       'subject_available':np.asarray(subject_valid,bool),'goal_bounds':np.asarray(goals,np.float32),'goal_field_mask':np.asarray(goal_valid,bool),
       'candidate_params':np.asarray(candidates,np.float32),'candidate_available':np.asarray(available,bool),'current_optics':np.asarray(optics,np.float32),'equipment_constraints':np.asarray(constraints,bool)}
    Y={'action_success':np.asarray(labels,np.float32),'decision':np.asarray(decisions,np.int64)}
    M={'action_success':np.asarray(masks,bool),'decision':np.ones(len(rows),bool),'human_utility':np.zeros(len(rows),bool)}
    assert X['rgb_history'].shape[1:]==(3,3,224,224)
    assert X['candidate_params'].shape[1:]==(len(C.ACTIONS),13)
    for a in list(X.values())+list(Y.values()):assert np.isfinite(a).all()
    assert Y['action_success'].shape==M['action_success'].shape
    return X,Y,M


def run(shard,shards,count,label_prefix='cc18-final'):
    label=f'{label_prefix}-{shard:02d}';root=Path('complete')/label;root.mkdir(parents=True,exist_ok=True)
    s=S.setup_blender();s.cycles.samples=8;s.render.image_settings.color_depth='8';stats=collections.Counter();groups=collections.defaultdict(set);inputs=[];targets=[];contrasts=0;rerenders=0;exact_pixels=collections.defaultdict(set);image_signatures=[]
    write_json(root/'actions.json',C.ACTIONS);write_json(root/'goals.json',C.GOALS)
    write_json(root/'split_definition.json',{'topologies':C.TOPOLOGIES,'assignments':C.SPLITS,'seed':18000000,'assignment_declared_before_targets':True})
    with open(root/'counterfactuals.jsonl','w') as fc,open(root/'scenes.jsonl','w') as fs,open(root/'outcome_verifier.jsonl','w') as fv:
        for index in range(shard,count,shards):
            scene=build_scene(index);origin=scene['origin_id'];current=copy.deepcopy(C.ACTIONS[0]);current['duration_s']=0.
            before,before_rgb=C.state_render(s,scene,current,root/'media'/origin/'state_00')
            for k in ['rgb_path','geometry_path']:before[k]=str(Path(before[k]).relative_to(root))
            subject=C.initial_subject(root/before['geometry_path'])
            history=[]
            for h,tau in enumerate([-.4,-.2]):
                past=copy.deepcopy(scene);past['boxes']=C.boxes_at(scene,tau)
                v,pix=C.state_render(s,past,current,root/'media'/origin/f'prefix_{h}')
                history.append({'rgb':str(Path(v['rgb_path']).relative_to(root)),'t_seconds':tau,'sha256':v['rgb_sha256']})
            history.append({'rgb':before['rgb_path'],'t_seconds':0.,'sha256':before['rgb_sha256']})
            stats['rendered_rgb']+=3;stats['ray_checks']+=144
            if stats['scene_configurations']%8==0:
                repeat,repeat_pixels=C.state_render(s,scene,current,root/'repro_check'/origin)
                assert np.array_equal(before_rgb,repeat_pixels),{'pixel_rerender_mismatch':origin}
                assert before['rgb_sha256']==repeat['rgb_sha256'],{'png_rerender_mismatch':origin}
                shutil.rmtree(root/'repro_check');rerenders+=1
            ph=hashlib.sha256(before_rgb.tobytes()).hexdigest();exact_pixels[ph].add(scene['split'])
            tiny=np.asarray(Image.fromarray(before_rgb).convert('L').resize((9,8)));bits=(tiny[:,1:]>tiny[:,:-1]).reshape(-1);dh=int(''.join('1' if b else '0' for b in bits),2)
            image_signatures.append({'origin_id':origin,'origin_group':scene['layout_group'],'split':scene['split'],'pixel_sha256':ph,'dhash_hex':f'{dh:016x}'})
            states=[]
            for j,a in enumerate(C.ACTIONS):
                v,pixels=C.state_render(s,scene,a,root/'media'/origin/f'state_{j+1:02d}')
                for k in ['rgb_path','geometry_path']:v[k]=str(Path(v[k]).relative_to(root))
                v.update(action_id=a['id'],origin_id=origin,split=scene['split']);states.append(v);C.dump_line(fc,v)
                stats['rendered_rgb']+=1;stats['ray_checks']+=48
            available=[C.permitted(a,scene['constraints']) for a in C.ACTIONS];decisions={}
            for goal in C.GOALS+[None]:
                success=[bool(v['path_feasible'] and C.goal_success(v['metrics'],goal)) if goal else False for v in states]
                good=[j for j,v in enumerate(success) if v and available[j]]
                best=min(good,key=lambda j:(C.ACTIONS[j]['cost'],C.ACTIONS[j]['id'])) if good and subject['visible'] and goal else None
                mode='ask' if goal is None and subject['visible'] else 'abstain' if best is None else 'keep' if best==0 else 'recommend'
                record=origin+':'+(goal['id'] if goal else 'missing_intent')
                o={'rgb':before['rgb_path'],'history':history,'selected_subject':subject,'intent':goal,'protected_style':('dark_subject_tone' if goal and goal['id']=='preserve_dark_subject' else None),'constraints':scene['constraints'],
                   'current_focal_mm':scene['camera']['focal_mm'],'action_candidates':C.ACTIONS,'candidate_available':available,'observation_cutoff_s':0.}
                inputs.append({'schema':'cameracoach.component.v18.2','record_id':record,'task_type':'candidate_action_ranking','origin_group':scene['layout_group'],'split':scene['split'],'observations':o,
                  'provenance':{'source':'own_procedural_simulator','scene_id':origin,'intent_origin':'simulator_task_definition_before_outcomes','label_authority':'synthetic_task_oracle','rgb_sha256':before['rgb_sha256'],
                  'rights_scope':'procedural_outputs_no_external_assets','renderer':'Blender '+bpy.app.version_string,'generator_sha256':digest(Path(__file__))}})
                targets.append({'record_id':record,'decision':mode,'target_action_index':best,'action_success':success,'action_feasible':[v['path_feasible'] for v in states],
                  'successful_action_ids':[C.ACTIONS[j]['id'] for j in good],'label_authority':'synthetic_task_oracle','tie_break':'minimum predeclared effort cost, not human preference',
                  'action_proposed':C.ACTIONS[best]['id'] if best is not None else None,'action_performed':None,'goal_achieved':success[best] if best is not None else None,'outcome_preferred':None,
                  'comparison_validity':'matched-time simulator counterfactuals','causal_attribution':'one control change; matched deterministic exogenous motion','human_utility':None,
                  'loss_masks':{'decision':True,'action_success':[bool(goal and subject['visible'] and av) for av in available],'action_feasible':True,'action_performed':False,'goal_achieved':best is not None,'outcome_preferred':False,'human_utility':False}})
                stats['policy_rows']+=1;stats[mode]+=1
                if goal:
                    decisions[goal['id']]=(best,success)
                    for j,v in enumerate(states):
                        C.dump_line(fv,{'record_id':record+':'+str(j),'origin_group':scene['layout_group'],'split':scene['split'],
                          'observations':{'before_rgb':before['rgb_path'],'after_rgb':v['rgb_path'],'selected_subject_before':subject,'action':C.ACTIONS[j],'goal':goal,'t_before_s':0.,'t_after_s':1.},
                          'targets':{'goal_achieved':C.goal_success(v['metrics'],goal),'action_feasible':v['path_feasible'],'simulator_action_applied':True,'real_action_performed':None,'human_preference':None},
                          'loss_masks':{'goal_achieved':True,'action_feasible':True,'real_action_performed':False,'human_preference':False},'label_authority':'synthetic_physics_gt'})
                        stats['verifier_rows']+=1
            for ga,gb in [('detail','context'),('expose','conceal'),('subject_midtones','preserve_dark_subject')]:
                ka,sa=decisions[ga];kb,sb=decisions[gb]
                if ka is not None and kb is not None and ka!=kb and not sa[kb] and not sb[ka]:contrasts+=1
            C.dump_line(fs,{**scene,'camera':S.serialize(scene['camera']),'goals_predeclared':C.GOALS,'supervision_limit':'physical framing, visibility, simulator motion and rendered pixel tone; not aesthetics or human usefulness'})
            groups[scene['split']].add(scene['layout_group']);stats['scene_configurations']+=1;stats['family:'+scene['family']]+=1;stats['split:'+scene['split']]+=1
            for mat in list(bpy.data.materials):
                if mat.users==0:bpy.data.materials.remove(mat)
            if stats['scene_configurations']%8==0:print('CC18_PROGRESS',shard,stats['scene_configurations'],flush=True)
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    assert not any(len(v)>1 for v in exact_pixels.values())
    for name,rows in [('inputs.jsonl',inputs),('targets.jsonl',targets),('image_signatures.jsonl',image_signatures)]:
        with open(root/name,'w') as f:
            for row in rows:C.dump_line(f,row)
    tm={t['record_id']:t for t in targets};assert len(tm)==len(inputs)
    batches=0
    for offset in range(0,len(inputs),8):
        X,Y,M=load_batch(root,inputs[offset:offset+8],tm);batches+=1
        assert not any(k in X for k in ['origin_group','scene_id','split','target_action_index','camera_pose','depth','future_rgb','action_feasible'])
    consumer={'rows_traversed':len(inputs),'actual_numpy_batches':batches,'batch_size':8,'rgb_shape':['B',3,3,224,224],
       'goal_and_constraint_tensors':True,'selected_subject_tensor':True,'randomized_candidate_order':True,'only_past_history':True,'no_geometry_or_path_oracle_inputs':True,
       'future_frames_in_policy':0,'cross_split_origin_groups':0,'human_utility_losses':0,'model_calls':0,
       'preprocessing':'RGB independent XY bilinear 224; exact Metal/CoreML parity NOT claimed'}
    stats.update({'opposing_successful_goal_pairs':contrasts,'conservative_topology_groups':sum(map(len,groups.values())),'actions_per_scene':len(C.ACTIONS),'goals_plus_missing_intent':len(C.GOALS)+1,'exact_rerender_scenes':rerenders})
    report={'schema':'cameracoach.component.v18.2','stats':dict(stats),'consumer':consumer,'model_execution':False,'real_human_responses':0,
      'dataset_scope':'synthetic physical-action component experiment only','full_cameracoach_training_ready':False,'not_proven':['real-world transfer','independent human usefulness','current MVP comparison','operational noisy subject initialization','exact Apple preprocessing parity'],
      'geometry':'eight geometric proxy families, eight topology templates; test templates excluded from train; multiple seed configurations per conservative topology group',
      'exposure_labels':'median rendered display-RGB brightness, NOT illumination, expression readability or cinematic style judgement',
      'motion':'known simulator velocity with genuinely rendered pre-t0 frames; matched one-second endpoints; continuous path collision, not full high-frame-rate tracking',
      'asset_manifest':{'external_models':[],'external_textures':[],'external_fonts':[],'procedural_only':True}}
    write_json(root/'QA.json',report)
    (root/'README_RU.md').write_text('# CameraCoach CC18 — физический компонент\n\nЭто фактические рендеры, не текстовые placeholders. Исходные наблюдения включают t=-0.4,-0.2,0. Все 32 действия и control сравниваются на t=1. Геометрические instance/mask/range/normal доступны только как supervision, никогда как вход online policy.\n\nload_batch в reproduction/cc18_run.py собирает RGB history, выбранную область, intent, equipment и перемешанные параметризованные кандидаты отдельно от Y/M.\n\nОбъекты — процедурные геометрические прокси. Нет доказанной человеческой полезности, выразительности, face/text readability или real-world transfer. Это не весь готовый CameraCoach.\n\nКоординаты действий: right/forward/up исходной камеры; радиус collision 0.15м. Метры и секунды относятся к симулятору. Смена key-light проверена по непрерывному пути; оборудование должно быть доступно.\n\nПолитика inputs.jsonl не содержит послекадров, GT depth или фактической проходимости. outcome_verifier.jsonl — отдельная задача, послекадры в ней разрешены.\n')
    print('CC18_SUMMARY '+json.dumps(report),flush=True);package(root,label)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--shards',type=int,default=8);p.add_argument('--count',type=int,default=512);p.add_argument('--label-prefix',default='cc18-final');a=p.parse_args();run(a.shard,a.shards,a.count,a.label_prefix)
