"""Finish the selected physical-action corpus, not a full CameraCoach claim.
Runs the frozen accepted simulator in isolated workers, validates actual selected
pixels/batches, and packages the filtered corpus for a same-session Drive readback.
The owner's private key is never required, read, printed, or transmitted.
"""
from __future__ import annotations
import argparse,copy,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE));sys.path.insert(0,str(HERE.parent/'cc17'))
import secure_joint_audit as J

def selected_package(root,label):
    root=Path(root).resolve()
    import selection_v19 as S
    import cc18_dataset as D
    from release_pack import package as original_package
    selected_receipt=S.audit_selection(root,batch_size=8)
    assert selected_receipt['counts']['policy_rows']==3353
    dest=Path('../selected_core').resolve();dest.mkdir(exist_ok=False)
    selected_scene_ids=set();record_ids=set()
    for component in sorted(root.iterdir()):
        if not component.is_dir() or not (component/'inputs.jsonl').is_file():continue
        out=dest/component.name;out.mkdir()
        rows=[r for r in D.lines(component/'inputs.jsonl') if S.eligible(r)]
        ids={r['record_id'] for r in rows};scenes={r['provenance']['scene_id'] for r in rows}
        assert not record_ids & ids;record_ids.update(ids);selected_scene_ids.update(scenes)
        # Do not leave an oracle bounding box in the online observation record.
        for r in rows:
            subject=r['observations']['selected_subject']
            r['observations']['selected_subject']={'tap_xy':subject['tap_xy'],'initialization':'simulator_visible_tap; noisy real initialization not evaluated'}
        targets=[r for r in D.lines(component/'targets.jsonl') if r['record_id'] in ids]
        signatures=[r for r in D.lines(component/'image_signatures.jsonl') if r['origin_id'] in scenes]
        for name,items in [('inputs.jsonl',rows),('targets.jsonl',targets),('image_signatures.jsonl',signatures)]:
            with (out/name).open('w') as f:
                for r in items:f.write(json.dumps(r,ensure_ascii=False,allow_nan=False)+'\n')
        for name in ['actions.json','goals.json','split_definition.json']:shutil.copyfile(component/name,out/name)
        media={h['rgb'] for r in rows for h in r['observations']['history']}
        for name in media:
            source=D.allowed_path(component,name);target=out/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    assert len(record_ids)==3353 and len(selected_scene_ids)==479
    standalone=D.audit(dest,batch_size=8)
    assert standalone['counts']['policy_rows']==3353 and not standalone['dhash_review_candidates']
    assert {k:standalone['counts'][k] for k in S.EXPECTED_COUNTS}==S.EXPECTED_COUNTS
    # Actual final numeric schema from actual admitted rows, not a handwritten shape.
    component=next(p.parent for p in sorted(dest.rglob('inputs.jsonl')))
    rows=list(D.lines(component/'inputs.jsonl'))[:2];tm={t['record_id']:t for t in D.lines(component/'targets.jsonl')}
    X,Y,M=D.load_batch(component,rows,tm)
    import numpy as np
    changed=copy.deepcopy(tm)
    for r in rows:
        t=changed[r['record_id']];t['decision']='ask';t['target_action_index']=None;t['action_success']=[not v for v in t['action_success']]
    X2,_,_=D.load_batch(component,rows,changed)
    assert X.keys()==X2.keys() and all(np.array_equal(X[k],X2[k]) for k in X)
    schema={group:{k:{'dtype':str(v.dtype),'shape_per_example':list(v.shape[1:])} for k,v in arrays.items()} for group,arrays in [('inputs',X),('targets',Y),('loss_masks',M)]}
    receipt={'schema':'cc19.actual_selected_data.v1','source_run':os.environ.get('GITHUB_RUN_ID'),
      'frozen_generator_commit':J.FROZEN,'source_filtered_consumer':selected_receipt,'standalone_selected_consumer':standalone,
      'selected_scenes':479,'selected_policy_rows':3353,'selected_past_rgb_files':1437,
      'input_target_mutation_invariance':True,'oracle_bounding_box_removed_from_records':True,
      'actual_tensor_schema':schema,'model_calls':0,'new_human_responses':0,
      'component_scope':'measurable synthetic physical-action selection only',
      'full_cameracoach_training_ready':False,'original_DoD_not_redefined':True,
      'unclosed_product_gates':['independent real-world usefulness','real-world transfer','current iPhone pixel preprocessing parity','separately authorized model smoke'],
      'readback_from_Drive':'PENDING_SAME_SESSION'}
    J.dump(dest/'SELECTED_ACTUAL_QA.json',receipt);J.dump(dest/'INPUT_TARGET_SCHEMA.json',schema)
    J.dump(dest/'EXCLUSION_POLICY.json',{'source_rows':3577,'excluded_rows':224,'excluded_groups':sorted(S.EXCLUDED_GROUPS),'reason':'conservative quarantine of all groups involved in cross-split image-hash screening; not a claim of visual identity'})
    shutil.copyfile('tools/dataset/cc17/cc18_dataset.py',dest/'cc18_dataset.py')
    shutil.copyfile(HERE/'selected_reader.py',dest/'selected_reader.py')
    (dest/'README_RU.md').write_text('# CameraCoach: выбранный корпус физических действий\n\nФактически собранный и полностью прочитанный корпус: 3353 задания, 479 конфигураций, 1437 прошлых RGB. Train 2184, validation 392, test 777. Используется 31 различимое действие.\n\nЗапуск проверки: `python selected_reader.py --root . --verify`. Получение batch: `from selected_reader import batches; X,Y,M=next(batches(root, split="train"))`. Нужны NumPy 1.26.4 и Pillow 11.3.0, Blender не нужен.\n\nX не содержит targets, геометрию, послекадры или идеальный bbox. Перемещения заданы в локальных осях исходной камеры. Метки — вычисленные физические цели симулятора, не оценки искусства и не человеческая полезность.\n\nЭто готовый к чтению датасет одного ограниченного ML-компонента. Он не закрывает весь исходный DoD CameraCoach: реальные операторы, перенос и device/model tests остаются отдельными незавершёнными проверками.\n')
    # Use the existing checked archive writer, then add an ephemeral recipient.
    # The ephemeral private key remains only in this job and is removed at exit.
    import release_pack
    saved=release_pack.package;release_pack.package=ORIGINAL_PACKAGE
    try:info=ORIGINAL_PACKAGE(dest,'cc19-policy-selected-verified')
    finally:release_pack.package=saved
    cipher=Path('cc19-policy-selected-verified.tar.gz.cms')
    subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream','-in',info['plaintext_name'],'-out',str(cipher),'-outform','DER','tools/dataset/cc17/transport_public.pem','../audit-public.pem'],check=True,stdout=subprocess.DEVNULL)
    delivery=Path('delivery');parts=[]
    for p in delivery.glob('cc19-policy-selected-verified.p*'):p.unlink()
    with cipher.open('rb') as f:
        for i in range(100):
            b=f.read(90*1024*1024)
            if not b:break
            p=delivery/f'cc19-policy-selected-verified.p{i:03d}';p.write_bytes(b)
            parts.append({'name':p.name,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
    info.update(encrypted_bytes=cipher.stat().st_size,encrypted_sha256=J.sha(cipher),parts=parts,readback_recipient='owner certificate plus same-job ephemeral certificate; no private key in delivery')
    J.dump(delivery/'RELEASE.json',info)
    Path('../proof').mkdir(exist_ok=True);J.dump('../proof/SELECTED_ACTUAL_QA.json',receipt)
    print('CC19_SELECTED_ACTUAL '+json.dumps({k:receipt[k] for k in ['selected_scenes','selected_policy_rows','selected_past_rgb_files','input_target_mutation_invariance','model_calls','full_cameracoach_training_ready']}),flush=True)
    return info

ORIGINAL_PACKAGE=None
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['worker','joint']);p.add_argument('--shard',type=int);p.add_argument('--key');a=p.parse_args()
    if a.mode=='worker':J.worker(a.shard)
    else:
        sys.path.insert(0,str(Path('frozen/tools/dataset/cc17').resolve()))
        import release_pack
        ORIGINAL_PACKAGE=release_pack.package
        release_pack.package=selected_package
        J.joint(a.key)
        # Expose only ciphertext release files to the artifact uploader.
        shutil.copytree('frozen/delivery','delivery',dirs_exist_ok=True)
