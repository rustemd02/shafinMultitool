"""Merge existing restored v19/v20 deliveries; no download, renderer or model.
Compact v19 omits scenes.jsonl. Supply the checked V19_CAMERA_CALIBRATION.json
sidecar; full v19 sources may instead provide native scenes.jsonl.
The merge never changes a source file and never counts a source replay as new data.
"""
from __future__ import annotations
import argparse,collections,hashlib,json,shutil,tarfile,tempfile
from pathlib import Path
import numpy as np
import unified_dataset as U
import calibration_index as C
EXCLUDED=C.EXCLUDED
EXPECTED={'v19':3353,'v20':1536}
EXPECTED_SPLITS={'train':3144,'validation':680,'test':1065}

def dump(p,x):Path(p).write_text(json.dumps(x,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def indexed_rows(path):
    result={}
    for r in U.lines(path):
        if r['record_id'] in result:raise ValueError('Duplicate target ID in '+str(path))
        result[r['record_id']]=r
    return result

def component_rows(file):
    rows=list(U.lines(file));ids=[r['record_id'] for r in rows];targets=indexed_rows(file.parent/'targets.jsonl')
    if len(ids)!=len(set(ids)) or set(ids)!=set(targets):raise ValueError('Input/target identity mismatch in '+str(file.parent))
    return rows,targets

def camera_for_row(row,component,calibration,native_cameras):
    sid=row['provenance']['scene_id'];archived=native_cameras.get(sid)
    if calibration is not None:
        return C.for_row(row,calibration,archived),'archived_and_reconstructed_agree' if archived is not None else 'pinned_metadata_reconstruction'
    if archived is None:raise ValueError('Compact v19 has no scenes.jsonl. Supply --calibration V19_CAMERA_CALIBRATION.json; do not invent identity camera axes.')
    result={key:archived[key] for key in C.FIELDS};C.validate_camera(result)
    if not np.isclose(result['focal_mm'],row['observations']['current_focal_mm'],atol=1e-10,rtol=0):raise ValueError('Native focal mismatch')
    return result,'archived_scene_metadata'

def copy_media(src,relative,dest,expected_sha):
    original=U.safe(src,relative)
    if not original.is_file():raise FileNotFoundError('Missing referenced source media: '+relative)
    actual=sha(original)
    if actual!=expected_sha:raise ValueError('Source image checksum mismatch: '+relative)
    if dest.exists():
        if sha(dest)!=actual:raise ValueError('Destination collision for different media')
    else:dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(original,dest)

def copy_history(src,row,out,prefix,version):
    for h in row['observations']['history']:
        relative=h['rgb'] if version=='v19' else h['path'];copy_media(src,relative,out/prefix/relative,h['sha256'])

def collect(v19,v20,out,calibration=None):
    rows=[];native=[];counts=collections.Counter();verifier=[];ids=set();calibration_modes=collections.Counter()
    inputs19=sorted(Path(v19).rglob('inputs.jsonl'));inputs20=sorted(Path(v20).rglob('inputs.jsonl'))
    if not inputs19 or not inputs20:raise ValueError('Both source components must be present')
    for ci,file in enumerate(inputs19):
        root=file.parent;source,targets=component_rows(file);scene_file=root/'scenes.jsonl';cameras={}
        if scene_file.is_file():
            for r in U.lines(scene_file):
                sid=r['origin_id']
                if sid in cameras:raise ValueError('Duplicate native scene ID')
                cameras[sid]=r['camera']
        prefix=f'media/v19/component_{ci:03d}'
        for row in source:
            if row['origin_group'] in EXCLUDED:continue
            camera,authority=camera_for_row(row,root,calibration,cameras);target=targets[row['record_id']]
            converted=U.convert_v19(row,target,camera,prefix)
            if converted['record_id'] in ids:raise ValueError('Duplicate source corpus supplied more than once')
            ids.add(converted['record_id']);copy_history(root,row,out,prefix,'v19');rows.append(converted);counts['v19']+=1;calibration_modes[authority]+=1
            native.append({'record_id':converted['record_id'],'native_input':row,'native_target':target,'action_coordinate_conversion_basis':camera,'calibration_authority':authority})
    for ci,file in enumerate(inputs20):
        root=file.parent;source,targets=component_rows(file);prefix=f'media/v20/component_{ci:03d}';histories={}
        for row in source:
            target=targets[row['record_id']];converted=U.convert_v20(row,target,prefix)
            if converted['record_id'] in ids:raise ValueError('Duplicate temporal source corpus supplied more than once')
            ids.add(converted['record_id']);copy_history(root,row,out,prefix,'v20');rows.append(converted);counts['v20']+=1
            native.append({'record_id':converted['record_id'],'native_input':row,'native_target':target})
            scene=row['record_id'].split(':')[0];history=converted['observations']['history']
            if scene in histories and histories[scene]!=history:raise ValueError('Goals/subjects from one scene have different input history')
            histories[scene]=history
        for record in U.lines(root/'outcomes.jsonl'):
            record['origin_group']='v20:'+record['origin_group'];record['history']=histories[record['scene_id']]
            for media in record['after_media']:
                relative=media['path'];copy_media(root,relative,out/prefix/relative,media['sha256']);media['path']=prefix+'/'+relative
            verifier.append(record)
    return rows,native,verifier,dict(counts),dict(calibration_modes)

def assert_native_fidelity(rows,evidence):
    byid={r['record_id']:r for r in rows}
    if len(byid)!=len(rows) or len(evidence)!=len(rows):raise ValueError('Duplicate or missing native provenance')
    for e in evidence:
        row=byid[e['record_id']];target=e['native_target'];indices=[a['native_index'] for a in row['observations']['actions']]
        if row['targets']['success']!=[target['action_success'][i] for i in indices]:raise ValueError('Changed native outcome')
        if row['targets']['success_known']!=[target['loss_masks']['action_success'][i] for i in indices]:raise ValueError('Changed native target eligibility')
        if row['targets']['decision']!=target['decision']:raise ValueError('Changed native decision')
        chosen=target['target_action_index'];expected=indices.index(chosen) if chosen is not None else None
        if row['targets']['chosen_index']!=expected:raise ValueError('Changed chosen candidate')

def build(v19,v20,out,calibration_path=None):
    out=Path(out);out.mkdir(exist_ok=False)
    calibration=C.load_index(calibration_path) if calibration_path is not None else None
    rows,native,verifier,counts,modes=collect(v19,v20,out,calibration)
    if counts!=EXPECTED or len(verifier)!=1408:raise ValueError('Incomplete or unexpected source delivery: '+str(counts))
    assert_native_fidelity(rows,native)
    U.write_lines(out/'records.jsonl',rows);U.write_lines(out/'NATIVE_RECORD_EVIDENCE.jsonl',native);U.write_lines(out/'verifier_sequences.jsonl',verifier)
    report=U.audit(out)
    if {s:report['counts'][s] for s in EXPECTED_SPLITS}!=EXPECTED_SPLITS:raise ValueError('Source split totals changed')
    report.update(native_label_fidelity_rows=len(native),verifier_sequences=len(verifier),source_kind='existing supplied restored component bytes; no new renders or new independent examples',
      calibration_rows_by_authority=modes,original_Drive_bytes_restored_in_this_command=False,full_cameracoach_training_ready=False)
    dump(out/'ACTUAL_UNIFIED_QA.json',report)
    dump(out/'SCHEMA.json',{'version':U.SCHEMA,'metrics':U.METRICS,'candidate_parameters':U.PARAMS,'decisions':U.DECISIONS,'max_candidates':U.MAX_ACTIONS,
      'metric_scope':{'0':'absent','1':'endpoint','2':'all five discrete native times'},'motion_profile':{'0':'endpoint-only source','1':'linear camera motion over duration'},
      'coordinate_frame':'initial camera right,forward,up; rotations use axis-angle radians','input_preprocessing':'EXIF transpose, RGB, independent X/Y bilinear resize 224x224, float32 0..1',
      'padding':'padded candidates have candidate_present=false and all action losses false'})
    shutil.copyfile(Path(__file__).parent/'unified_dataset.py',out/'unified_dataset.py')
    (out/'requirements.txt').write_text('numpy==1.26.4\nPillow==11.3.0\n')
    if calibration_path is not None:shutil.copyfile(calibration_path,out/'V19_CAMERA_CALIBRATION.json')
    (out/'START_HERE_RU.md').write_text('# CameraCoach: единый корпус физических действий\n\nЭтот файл создаётся только после полного чтения 3353 задач v19 и 1536 задач v20. Это объединение существующих данных, не новые независимые наблюдения.\n\n`from unified_dataset import batches; X,Y,M=next(batches(root, split="train"))`\n\nTrain=3144, validation=680, test=1065. 31 и 11 кандидатов объединены padding/masks без выдуманных негативов. Видимость пикселей и поверхностных проб разделена. NATIVE_RECORD_EVIDENCE и after_media verifier_sequences запрещены во входе policy.\n\nВ компактном v19 нет scenes.jsonl: используем отдельный индекс калибровки из закреплённых чистых функций симулятора, с обязательной проверкой focal/origin/split. Это не измерения реальной камеры.\n\nМодель/обучение не запускались; человеческая полезность и перенос на iPhone этим объединением не доказаны.\n')
    return report

def extract_verified(archive,dest,manifest):
    dest=Path(dest);dest.mkdir(exist_ok=False);seen=set()
    with tarfile.open(archive,'r:gz') as z:
        for member in z:
            if not member.isfile() or member.name not in manifest or member.name in seen:raise ValueError('Unexpected, nonregular or duplicate archive member')
            path=U.safe(dest,member.name);seen.add(member.name);entry=manifest[member.name]
            if member.size!=entry['bytes']:raise ValueError('Archive size mismatch')
            h=hashlib.sha256();path.parent.mkdir(parents=True,exist_ok=True)
            with z.extractfile(member) as src,path.open('xb') as dst:
                for block in iter(lambda:src.read(1024*1024),b''):h.update(block);dst.write(block)
            if h.hexdigest()!=entry['sha256']:raise ValueError('Archive checksum mismatch')
    if seen!=set(manifest):raise ValueError('Archive missing required payload files')
    return len(seen)

def clean_replay(root):
    root=Path(root);manifest={str(p.relative_to(root)):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in root.rglob('*') if p.is_file()}
    with tempfile.TemporaryDirectory(prefix='cc21-clean-readback-',dir=root.parent) as td:
        temp=Path(td);archive=temp/'data.tar.gz'
        with tarfile.open(archive,'w:gz') as z:
            for name in sorted(manifest):z.add(root/name,arcname=name,recursive=False)
        restored=temp/'restored';verified=extract_verified(archive,restored,manifest)
        before=json.loads((root/'ACTUAL_UNIFIED_QA.json').read_text());after=U.audit(restored)
        if before['stream_hashes']!=after['stream_hashes']:raise ValueError('Tensor stream changed on archive readback')
    receipt={'all_payload_files_verified':verified,'all_split_tensor_hashes_equal':True,'from_Google_Drive':False,'source':'same-command clean archive extraction of supplied data','model_calls':0}
    dump(root/'CLEAN_REPLAY_RECEIPT.json',receipt);return receipt

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--v19',required=True,type=Path);p.add_argument('--v20',required=True,type=Path);p.add_argument('--out',required=True,type=Path)
    p.add_argument('--calibration',type=Path,default=Path(__file__).with_name('V19_CAMERA_CALIBRATION.json'));a=p.parse_args()
    calibration=a.calibration if a.calibration.is_file() else None
    report=build(a.v19,a.v20,a.out,calibration);replay=clean_replay(a.out)
    print('CC21_UNIFIED_QA '+json.dumps({'report':report,'clean_replay':replay}),flush=True)
