"""Canonical RGB encoding and explicit co-planar ambiguity masks.
An equal-distance overlap between same-role cuboids has no unique instance ID.
Those pixels are loss-masked, not silently admitted as exact segmentation GT.
Depth and selected-vs-background disagreements always remain hard failures.
"""
import argparse,collections,json,random
from pathlib import Path
import numpy as np
from PIL import Image
import cc18_run as R
from acquire import digest,write_json
S=R.S
raw_render=R.C.state_render
raw_package=R.package
CTX={};COUNTS=collections.Counter()


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


def checked_rays(s,c,ids,depth,seed):
    rng=random.Random(seed);ds=S.rays(c);deps=R.bpy.context.evaluated_depsgraph_get();bad=[]
    boxes=CTX['boxes'];lookup={b['id']:b for b in boxes};amb,cross=ambiguity(c,boxes,depth)
    CTX['ambiguous']=amb;CTX['cross_role']=cross
    if cross.any():
        # A mixed selected/nonselected coplanar surface would invalidate visibility.
        bad.append(['mixed-role-coplanar-pixels',int(cross.sum())]);return bad
    for _ in range(48):
        y=rng.randrange(S.H);x=rng.randrange(S.W)
        hit,loc,normal,face,obj,m=s.ray_cast(deps,S.Vector(c['position']),S.Vector(ds[y,x]),distance=100)
        actual=int(obj.name.split('_')[1]) if hit and obj.name.startswith('box_') else 0;expected=int(ids[y,x])
        actual_depth=float(np.linalg.norm(np.asarray(loc)-c['position'])) if hit else float('inf')
        if hit!=bool(expected):bad.append([x,y,'hit/miss',expected,actual]);continue
        if hit and abs(actual_depth-depth[y,x])>1e-3:bad.append([x,y,'depth',float(depth[y,x]),actual_depth]);continue
        if actual!=expected:
            same_role=actual in lookup and expected in lookup and lookup[actual]['selected']==lookup[expected]['selected']
            if not(amb[y,x] and same_role):bad.append([x,y,'unexplained-instance',expected,actual])
            else:COUNTS['sampled_equal_depth_same_role_ties']+=1
        COUNTS['independent_rays_checked']+=1
    return bad
S.check_rays=checked_rays


def canonical_render(s,scene,a,folder):
    CTX['boxes']=R.C.boxes_at(scene,a['duration_s'])
    state,pixels=raw_render(s,scene,a,folder)
    path=Path(state['rgb_path']);Image.fromarray(pixels,mode='RGB').save(path,format='PNG',compress_level=6)
    state['rgb_sha256']=digest(path);state['encoding']='canonical lossless RGB PNG without variable Blender metadata'
    gp=Path(state['geometry_path'])
    with np.load(gp,allow_pickle=False) as z:arrays={k:z[k] for k in z.files}
    arrays['instance_loss_valid']=~CTX['ambiguous'];arrays['normal_loss_valid']=arrays['depth_valid']&~CTX['ambiguous']
    arrays['selected_visibility_loss_valid']=~CTX['cross_role']
    np.savez_compressed(gp,**arrays);state['geometry_sha256']=digest(gp)
    state['ambiguous_instance_pixels']=int(CTX['ambiguous'].sum());state['mixed_role_ambiguities']=int(CTX['cross_role'].sum())
    state['ambiguity_rule']='equal-depth same-role AABB front surfaces <=2e-5m; instance and normal losses masked; selected-role conflicts forbidden'
    COUNTS['masked_instance_pixels']+=state['ambiguous_instance_pixels'];COUNTS['rendered_states_including_repro_checks']+=1
    # Clean unreferenced renderer allocations; source data on disk remain intact.
    for mesh in list(R.bpy.data.meshes):
        if mesh.users==0:R.bpy.data.meshes.remove(mesh)
    for mat in list(R.bpy.data.materials):
        if mat.users==0:R.bpy.data.materials.remove(mat)
    return state,pixels
R.C.state_render=canonical_render


def verified_package(root,label):
    report=json.loads((root/'QA.json').read_text());report['coplanar_ambiguity_audit']=dict(COUNTS)
    report['instance_normal_loss_masks_required']=True;report['depth_or_selected_role_mismatches_admitted']=0
    report['entrypoint_sha256']=digest(Path(__file__));write_json(root/'QA.json',report)
    print('CC18_FINAL_QA '+json.dumps(report),flush=True)
    raw_package(root,label)
R.package=verified_package
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--shards',type=int,default=8);p.add_argument('--count',type=int,default=512);p.add_argument('--label-prefix',default='cc18-final');a=p.parse_args()
    R.run(a.shard,a.shards,a.count,a.label_prefix)
