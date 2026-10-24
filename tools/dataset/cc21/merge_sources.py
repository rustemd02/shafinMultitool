"""Merge already local v19/v20 component data and execute the common reader.
This module has no network, credential, encryption or model operations.
"""
from __future__ import annotations
import argparse,collections,json,shutil,sys,tarfile,hashlib
from pathlib import Path
import unified_dataset as U
EXCLUDED={'cc18-topology-0-1','cc18-topology-0-6','cc18-topology-2-5','cc18-topology-6-6'}

def dump(p,x):Path(p).write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def copy_history(src,row,out,prefix,v):
    for h in row['observations']['history']:
        rel=h['rgb'] if v=='v19' else h['path'];dest=out/prefix/rel
        if not dest.exists():dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(U.safe(src,rel),dest)

def build(v19,v20,out):
    out=Path(out);out.mkdir(exist_ok=False);rows=[];native=[];counts=collections.Counter();verifier=[]
    for file in sorted(Path(v19).rglob('inputs.jsonl')):
        root=file.parent;ys={r['record_id']:r for r in U.lines(root/'targets.jsonl')};scenes={r['origin_id']:r for r in U.lines(root/'scenes.jsonl')};prefix='media/v19/'+root.name
        for r in U.lines(file):
            if r['origin_group'] in EXCLUDED:continue
            camera=scenes[r['provenance']['scene_id']]['camera'];t=ys[r['record_id']];x=U.convert_v19(r,t,camera,prefix)
            copy_history(root,r,out,prefix,'v19');rows.append(x);native.append({'record_id':x['record_id'],'native_input':r,'native_target':t,'action_coordinate_conversion_basis':{k:camera[k] for k in ['right','forward','up']}});counts['v19']+=1
    for file in sorted(Path(v20).rglob('inputs.jsonl')):
        root=file.parent;ys={r['record_id']:r for r in U.lines(root/'targets.jsonl')};prefix='media/v20/'+root.name;histories={}
        for r in U.lines(file):
            t=ys[r['record_id']];x=U.convert_v20(r,t,prefix);copy_history(root,r,out,prefix,'v20');rows.append(x);native.append({'record_id':x['record_id'],'native_input':r,'native_target':t});counts['v20']+=1
            histories[r['record_id'].split(':')[0]]=x['observations']['history']
        for r in U.lines(root/'outcomes.jsonl'):
            r['origin_group']='v20:'+r['origin_group'];r['history']=histories[r['scene_id']]
            for h in r['after_media']:
                old=h['path'];dst=out/prefix/old
                if not dst.exists():dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(U.safe(root,old),dst)
                h['path']=prefix+'/'+old
            verifier.append(r)
    assert counts=={'v19':3353,'v20':1536},dict(counts)
    U.write_lines(out/'records.jsonl',rows);U.write_lines(out/'NATIVE_RECORD_EVIDENCE.jsonl',native);U.write_lines(out/'verifier_sequences.jsonl',verifier)
    assert len(verifier)==1408
    report=U.audit(out);assert {s:report['counts'][s] for s in ['train','validation','test']}=={'train':3144,'validation':680,'test':1065}
    # All native labels survive the remapping, including missingness and selected indices.
    byid={r['record_id']:r for r in rows}
    for e in native:
        r=byid[e['record_id']];t=e['native_target'];source=r['provenance']['native_source'];indices=[a['native_index'] for a in r['observations']['actions']]
        assert r['targets']['success']==[t['action_success'][i] for i in indices]
        assert r['targets']['success_known']==[t['loss_masks']['action_success'][i] for i in indices]
        assert r['targets']['decision']==t['decision']
        k=t['target_action_index'];assert r['targets']['chosen_index']==(indices.index(k) if k is not None else None)
    report.update(native_label_fidelity_rows=len(native),verifier_sequences=len(verifier),source_kind='fresh replay of frozen accepted source origins, not additional independent data',original_Drive_bytes_restored=False,full_cameracoach_training_ready=False)
    dump(out/'ACTUAL_UNIFIED_QA.json',report)
    dump(out/'SCHEMA.json',{'version':U.SCHEMA,'metrics':U.METRICS,'candidate_parameters':U.PARAMS,'decisions':U.DECISIONS,'max_candidates':U.MAX_ACTIONS,'metric_scope':{'0':'absent','1':'endpoint','2':'all five discrete native times'},'motion_profile':{'0':'endpoint-only source','1':'linear camera motion over duration'},'coordinate_frame':'initial camera right,forward,up; rotations use axis-angle radians','input_preprocessing':'EXIF transpose, RGB, independent X/Y bilinear resize 224x224, float32 0..1','padding':'padded candidates have candidate_present=false and all action losses false'})
    shutil.copyfile(Path(__file__).parent/'unified_dataset.py',out/'unified_dataset.py')
    (out/'requirements.txt').write_text('numpy==1.26.4\nPillow==11.3.0\n')
    (out/'START_HERE_RU.md').write_text('# CameraCoach: единый корпус действий\n\nЭто фактически объединённые 3353 задачи v19 и 1536 задач v20, не новые 4889 независимых наблюдений. Один загрузчик формирует смешанные пакеты с 31/11 кандидатами, масками и различными семантиками видимости/времени.\n\n`from unified_dataset import batches; X,Y,M=next(batches(root, split="train"))`\n\nTrain=3144, validation=680, test=1065. Полный проход выполнен по реальным изображениям. NATIVE_RECORD_EVIDENCE — только доказательства соответствия, не вход модели. verifier_sequences содержит отдельные послекадры; запрещено подавать их в policy.\n\nЭтот набор пригоден для подготовки ограниченного физического эксперимента. Он не содержит независимых human-utility ответов и не доказывает перенос на реальный iPhone. Целевые model-forward и обучение здесь не выполнялись.\n')
    return report

def clean_replay(root):
    root=Path(root);archive=Path('unified-plain-check.tar.gz');dest=Path('clean_replay');dest.mkdir(exist_ok=False)
    manifest={str(p.relative_to(root)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in root.rglob('*') if p.is_file()}
    with tarfile.open(archive,'w:gz') as z:
        for name in sorted(manifest):z.add(root/name,arcname=name,recursive=False)
    with tarfile.open(archive,'r:gz') as z:
        for m in z:
            path=U.safe(dest,m.name)
            if not m.isfile() or m.name not in manifest:raise ValueError('Unexpected archive entry')
            b=z.extractfile(m).read();e=manifest[m.name];assert len(b)==e['bytes'] and hashlib.sha256(b).hexdigest()==e['sha256'];path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b)
    before=json.loads((root/'ACTUAL_UNIFIED_QA.json').read_text());after=U.audit(dest);assert before['stream_hashes']==after['stream_hashes']
    receipt={'all_payload_files_verified':len(manifest),'all_split_tensor_hashes_equal':True,'from_Google_Drive':False,'source':'same-job clean archive extraction','model_calls':0}
    dump(root/'CLEAN_REPLAY_RECEIPT.json',receipt);return receipt

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--v19',required=True);p.add_argument('--v20',required=True);p.add_argument('--out',required=True);a=p.parse_args()
    report=build(a.v19,a.v20,a.out);replay=clean_replay(a.out)
    print('CC21_UNIFIED_QA '+json.dumps({'report':report,'clean_replay':replay}),flush=True)
