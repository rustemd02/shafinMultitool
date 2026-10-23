"""Read the admitted CameraCoach physical-action dataset, without Blender or ML.
Usage: python selected_reader.py --root /private/selected --verify
Python API: for X,Y,M in batches(root, split='train', batch_size=8): ...
The dataset is a bounded synthetic component, not proof of a useful full policy.
"""
from __future__ import annotations
import argparse,collections,hashlib,json
from pathlib import Path
import cc18_dataset as D
EXPECTED={'train':2184,'validation':392,'test':777}
EXCLUDED={'cc18-topology-0-1','cc18-topology-0-6','cc18-topology-2-5','cc18-topology-6-6'}

def batches(root,split='train',batch_size=8):
    if split not in EXPECTED or batch_size<1:raise ValueError('Invalid split or batch size')
    for path in sorted(Path(root).rglob('inputs.jsonl')):
        component=path.parent;tm={t['record_id']:t for t in D.lines(component/'targets.jsonl')}
        rows=[]
        for r in D.lines(path):
            if r['origin_group'] in EXCLUDED:raise ValueError('Quarantined group in the physical selected corpus')
            if 'bbox_xyxy' in r['observations']['selected_subject']:raise ValueError('Oracle bounding box remains in input record')
            if r['split']==split:rows.append(r)
        for i in range(0,len(rows),batch_size):yield D.load_batch(component,rows[i:i+batch_size],tm)

def verify(root):
    root=Path(root);baseline=D.audit(root,batch_size=8)
    assert baseline['counts']['policy_rows']==3353 and not baseline['dhash_review_candidates']
    assert all(baseline['counts']['split:'+k]==v for k,v in EXPECTED.items())
    scenes=set();groups=collections.defaultdict(set);ids=set()
    for path in sorted(root.rglob('inputs.jsonl')):
        for r in D.lines(path):
            assert r['record_id'] not in ids;ids.add(r['record_id']);scenes.add(r['provenance']['scene_id']);groups[r['split']].add(r['origin_group'])
    assert len(scenes)==479 and sum(map(len,groups.values()))==60
    receipts={}
    for split,expected in EXPECTED.items():
        h=hashlib.sha256();n=0;nb=0;masked_human=0;schema=None
        for X,Y,M in batches(root,split,8):
            n+=len(Y['decision']);nb+=1;masked_human+=int(M['human_utility'].sum())
            for kind,values in [('X',X),('Y',Y),('M',M)]:
                for name,a in sorted(values.items()):
                    h.update(json.dumps([kind,name,str(a.dtype),a.shape],separators=(',',':')).encode());h.update(a.tobytes(order='C'))
            if schema is None:schema={kind:{name:{'dtype':str(a.dtype),'shape':list(a.shape[1:])} for name,a in values.items()} for kind,values in [('X',X),('Y',Y),('M',M)]}
        assert n==expected and masked_human==0
        receipts[split]={'records':n,'actual_batches':nb,'tensor_stream_sha256':h.hexdigest(),'schema':schema}
    return {'schema':'cc19.selected_reader.v1','selected_records':3353,'scene_configurations':479,'origin_groups':60,
        'split_checks':receipts,'source_hash_and_leakage_audit':baseline,'model_calls':0,'human_utility_losses':0,
        'component_data_ready':True,'component_scope':'synthetic framing/visibility/display-tone action selection only',
        'full_cameracoach_training_ready':False}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--verify',action='store_true');p.add_argument('--receipt',type=Path);a=p.parse_args()
    if not a.verify:p.error('--verify is required for the command-line audit')
    result=verify(a.root);text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if a.receipt:a.receipt.write_text(text)
    print(text)
