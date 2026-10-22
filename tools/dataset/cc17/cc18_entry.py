"""CC18 verified rendering entrypoint.
Most labels use independent analytic AABB rays. At equal-depth cross-role
boundaries only, the renderer's own center ray resolves object ownership.
Ambiguous instance/normal/segmentation pixels remain explicitly loss-masked.
No unresolved selected-role or depth disagreement is admitted.
"""
import argparse,collections,copy,json,random
from pathlib import Path
import numpy as np
from PIL import Image
import cc18_run as R
from cc18_dataset import load_batch,audit
from acquire import digest,write_json
S=R.S;raw_render=R.C.state_render;raw_package=R.package;raw_measure=S.measure
CTX={};COUNTS=collections.Counter()
R.load_batch=load_batch


def ambiguity(cam,boxes,depth):
    ds=S.rays(cam);origin=cam['position'];inv=np.divide(1.,ds,out=np.full_like(ds,1e16),where=np.abs(ds)>1e-16)
    count=np.zeros(depth.shape,np.uint8);selected=np.zeros(depth.shape,bool);other=np.zeros(depth.shape,bool)
    for b in boxes:
        lo=np.asarray(b['center'])-np.asarray(b['size'])/2;hi=np.asarray(b['center'])+np.asarray(b['size'])/2
        a=(lo-origin)*inv;c=(hi-origin)*inv;near=np.max(np.minimum(a,c),axis=-1);far=np.min(np.maximum(a,c),axis=-1)
        hit=np.where(near>1e-5,near,far);valid=(far>=np.maximum(near,1e-5))&np.isfinite(depth)
        delta=np.full_like(depth,np.inf);np.subtract(hit,depth,out=delta,where=valid)
        tied=valid&(np.abs(delta)<=2e-5);count+=tied
        if b['selected']:selected|=tied
        else:other|=tied
    return count>1,selected&other


def measured_with_renderer_boundaries(cam,boxes):
    m,ids,depth,alone=raw_measure(cam,boxes)
    amb,cross=ambiguity(cam,boxes,depth);CTX['ambiguous']=amb;CTX['cross_role']=cross
    if cross.any():
        s=CTX['scene'];deps=R.bpy.context.evaluated_depsgraph_get();ds=S.rays(cam)
        for y,x in np.argwhere(cross):
            hit,loc,norm,face,obj,mat=s.ray_cast(deps,S.Vector(cam['position']),S.Vector(ds[y,x]),distance=100)
            assert hit and obj.name.startswith('box_'),'Renderer did not resolve an analytic boundary hit'
            exact=float(np.linalg.norm(np.asarray(loc)-cam['position']))
            assert abs(exact-depth[y,x])<=1e-3,'Boundary depth disagreement'
            ids[y,x]=int(obj.name.split('_')[1]);depth[y,x]=exact
        COUNTS['cross_role_boundary_pixels_resolved_by_renderer']+=int(cross.sum())
        selected=np.isin(ids,[b['id'] for b in boxes if b['selected']]);amask=alone>0
        m['visible_fraction']=float(selected.sum()/amask.sum()) if amask.any() else 0.
        # Preserve original metric names if present; their semantics stay unchanged.
        if 'visible_pixels' in m:m['visible_pixels']=int(selected.sum())
    m['selected_boundary_pixels_renderer_resolved']=int(cross.sum())
    return m,ids,depth,alone
S.measure=measured_with_renderer_boundaries


def checked_rays(s,c,ids,depth,seed):
    rng=random.Random(seed);ds=S.rays(c);deps=R.bpy.context.evaluated_depsgraph_get();bad=[]
    lookup={b['id']:b for b in CTX['boxes']};amb=CTX['ambiguous'];cross=CTX['cross_role']
    for _ in range(48):
        y=rng.randrange(S.H);x=rng.randrange(S.W)
        hit,loc,normal,face,obj,m=s.ray_cast(deps,S.Vector(c['position']),S.Vector(ds[y,x]),distance=100)
        actual=int(obj.name.split('_')[1]) if hit and obj.name.startswith('box_') else 0;expected=int(ids[y,x])
        actual_depth=float(np.linalg.norm(np.asarray(loc)-c['position'])) if hit else float('inf')
        if hit!=bool(expected):bad.append([x,y,'hit/miss',expected,actual]);continue
        if hit and abs(actual_depth-depth[y,x])>1e-3:bad.append([x,y,'depth',float(depth[y,x]),actual_depth]);continue
        if actual!=expected:
            same_role=actual in lookup and expected in lookup and lookup[actual]['selected']==lookup[expected]['selected']
            if not(amb[y,x] and same_role):bad.append([x,y,'unexplained-instance-or-role',expected,actual])
            else:COUNTS['sampled_equal_depth_same_role_ties']+=1
        COUNTS['renderer_boundary_consistency_rays' if cross[y,x] else 'independent_rays_checked']+=1
    return bad
S.check_rays=checked_rays


def canonical_render(s,scene,a,folder):
    CTX['boxes']=R.C.boxes_at(scene,a['duration_s']);CTX['scene']=s
    # Geometry must already be current before S.measure resolves boundary rays.
    S.load_boxes(s,CTX['boxes']);R.bpy.context.view_layer.update()
    state,pixels=raw_render(s,scene,a,folder)
    path=Path(state['rgb_path']);Image.fromarray(pixels,mode='RGB').save(path,format='PNG',compress_level=6)
    state['rgb_sha256']=digest(path);state['encoding']='canonical lossless RGB PNG without variable Blender metadata'
    gp=Path(state['geometry_path'])
    with np.load(gp,allow_pickle=False) as z:arrays={k:z[k] for k in z.files}
    arrays['instance_loss_valid']=~CTX['ambiguous'];arrays['normal_loss_valid']=arrays['depth_valid']&~CTX['ambiguous']
    arrays['selected_visibility_loss_valid']=~CTX['cross_role']
    np.savez_compressed(gp,**arrays);state['geometry_sha256']=digest(gp)
    state['ambiguous_instance_pixels']=int(CTX['ambiguous'].sum());state['renderer_resolved_selected_boundary_pixels']=int(CTX['cross_role'].sum())
    state['ambiguity_rule']='equal-depth surfaces <=2e-5m; cross-role ownership uses Blender center-ray GT; ambiguous dense losses masked'
    COUNTS['masked_instance_pixels']+=state['ambiguous_instance_pixels'];COUNTS['rendered_states_including_repro_checks']+=1
    for mesh in list(R.bpy.data.meshes):
        if mesh.users==0:R.bpy.data.meshes.remove(mesh)
    for mat in list(R.bpy.data.materials):
        if mat.users==0:R.bpy.data.materials.remove(mat)
    return state,pixels
R.C.state_render=canonical_render


def verified_package(root,label):
    result=audit(root);write_json(root/'RENDERER_FREE_CONSUMER_AUDIT.json',result)
    report=json.loads((root/'QA.json').read_text());report['coplanar_ambiguity_audit']=dict(COUNTS)
    report['instance_normal_loss_masks_required']=True;report['unresolved_depth_or_selected_role_mismatches_admitted']=0
    report['boundary_authority']='Blender center rays for cross-role analytic ties; these are not counted as independent analytic validation'
    report['renderer_free_consumer']={k:v for k,v in result.items() if k!='dhash_review_candidates'}
    report['near_duplicate_review_candidate_count']=len(result['dhash_review_candidates'])
    report['entrypoint_sha256']=digest(Path(__file__));report['policy_input_mode']='tap_only_no_oracle_bounding_box';report['training_candidates']=31
    write_json(root/'QA.json',report)
    print('CC18_FINAL_QA '+json.dumps(report),flush=True);raw_package(root,label)
R.package=verified_package


def regression():
    s=S.setup_blender();s.cycles.samples=8
    for index,action in [(71,'dolly_-1.0'),(257,'dolly_1.0')]:
        scene=R.build_scene(index);a=next(a for a in R.C.ACTIONS if a['id']==action)
        state,pixels=canonical_render(s,scene,a,Path('boundary_regression')/str(index))
        assert state['renderer_resolved_selected_boundary_pixels']>=1
    print('CC18_BOUNDARY_REGRESSION_PASS',dict(COUNTS),flush=True);COUNTS.clear()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--shards',type=int,default=8);p.add_argument('--count',type=int,default=512);p.add_argument('--label-prefix',default='cc18-final');p.add_argument('--regression',action='store_true');a=p.parse_args()
    if a.regression:regression()
    R.run(a.shard,a.shards,a.count,a.label_prefix)
