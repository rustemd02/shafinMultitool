"""Recover v19 camera-basis metadata omitted from its compact delivery.
This does not render scenes, create labels, load models, or read private keys.
Only three inspected pure functions from one exact source blob are evaluated.
The resulting calibration is deterministic simulator metadata, NOT device data.
"""
from __future__ import annotations
import argparse,ast,hashlib,json,random,re
from pathlib import Path
import numpy as np
SOURCE_COMMIT='dd9cc68c3e1c12fb913a4a8590b55ff0bbdff2ed'
SOURCE_BLOB='df775f4338db60b629aee82ebede989343720b87'
EXCLUDED=frozenset({'cc18-topology-0-1','cc18-topology-0-6','cc18-topology-2-5','cc18-topology-6-6'})
FIELDS=('right','forward','up','focal_mm')

def git_blob_sha(data):
    return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()

def validate_camera(camera):
    if set(camera)!=set(FIELDS):raise ValueError('Camera calibration fields differ from the declared basis contract')
    B=np.stack([np.asarray(camera[k],float) for k in FIELDS[:3]],axis=1)
    if B.shape!=(3,3) or not np.isfinite(B).all():raise ValueError('Nonfinite/invalid camera basis')
    if not np.allclose(B.T@B,np.eye(3),atol=1e-10,rtol=0) or not np.isclose(np.linalg.det(B),1.,atol=1e-10):raise ValueError('Camera basis is not right-handed orthonormal')
    if not np.isfinite(camera['focal_mm']) or not 27<=camera['focal_mm']<=34:raise ValueError('Unexpected focal length in frozen corpus')
    return camera

def build_index(source):
    data=Path(source).read_bytes()
    if git_blob_sha(data)!=SOURCE_BLOB:raise ValueError('Source blob differs from the exact frozen generator; refusing reconstruction')
    tree=ast.parse(data.decode('utf-8'));wanted={'unit','camera','make_scene'}
    functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in wanted]
    families=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FAMILIES' for t in n.targets))
    if {n.name for n in functions}!=wanted:raise ValueError('Frozen pure metadata functions missing')
    # No module-level import or generator/render entrypoint is executed.
    env={'np':np,'random':random,'FAMILIES':ast.literal_eval(families)}
    exec(compile(ast.Module(body=functions,type_ignores=[]),'<pinned-v19-pure-metadata>','exec'),env)
    records={}
    for index in range(512):
        group=f'cc18-topology-{index%8}-{(index//8)%8}'
        if index==114 or group in EXCLUDED:continue
        lowlevel=env['make_scene'](10000+index)['camera']
        camera={k:lowlevel[k].tolist() if isinstance(lowlevel[k],np.ndarray) else lowlevel[k] for k in FIELDS}
        validate_camera(camera)
        split='train' if (index//8)%8<5 else 'validation' if (index//8)%8==5 else 'test'
        records[f'cc18-{index:06d}']={'camera':camera,'origin_group':group,'split':split}
    if len(records)!=479:raise AssertionError('Unexpected selected metadata count')
    return {'schema':'cc21.compact-v19-calibration.v1','source_commit':SOURCE_COMMIT,'source_blob_sha1':SOURCE_BLOB,
      'source_sha256':hashlib.sha256(data).hexdigest(),'derivation':'complete_synthetic.build_scene(index) retains synthetic_physical.make_scene(10000+index).camera unchanged',
      'authority':'deterministic frozen simulator configuration, not measured camera pose','render_calls':0,'model_calls':0,'dataset_examples_created':0,
      'archived_scene_basis_comparison':'not performed by index generation; merge checks against scenes.jsonl when supplied',
      'excluded_groups':sorted(EXCLUDED),'records':records}

def load_index(path):
    value=json.loads(Path(path).read_text())
    if value.get('schema')!='cc21.compact-v19-calibration.v1' or value.get('source_commit')!=SOURCE_COMMIT or value.get('source_blob_sha1')!=SOURCE_BLOB:raise ValueError('Calibration provenance mismatch')
    if len(value['records'])!=479:raise ValueError('Incomplete calibration index')
    for record in value['records'].values():validate_camera(record['camera'])
    return value

def for_row(row,index,archived_camera=None):
    sid=row['provenance']['scene_id']
    if re.fullmatch(r'cc18-[0-9]{6}',sid) is None or sid not in index['records']:raise ValueError('Unknown or excluded source scene')
    entry=index['records'][sid];camera=entry['camera']
    if row['origin_group']!=entry['origin_group'] or row['split']!=entry['split']:raise ValueError('Origin/split disagrees with frozen calibration')
    focal=row['observations']['current_focal_mm']
    if not np.isclose(focal,camera['focal_mm'],atol=1e-10,rtol=0):raise ValueError('Focal metadata disagrees with calibration reconstruction')
    if archived_camera is not None:
        for key in FIELDS:
            if not np.allclose(archived_camera[key],camera[key],atol=1e-10,rtol=0):raise ValueError('Archived camera differs from frozen reconstruction: '+key)
    return camera

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    result=build_index(a.source);a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(result,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
    print('CC21_CALIBRATION_METADATA '+json.dumps({'selected_camera_bases':len(result['records']),'index_sha256':hashlib.sha256(a.out.read_bytes()).hexdigest(),'source_blob_sha1':SOURCE_BLOB,'render_calls':0,'model_calls':0,'new_training_records':0}))
