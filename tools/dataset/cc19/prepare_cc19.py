"""Private, data-only CameraCoach restoration. No network or model execution.
The compact policy core and full original shards contain the same record IDs:
select ONE policy representation instead of recursively double-counting both.
"""
from __future__ import annotations
import argparse,collections,copy,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
for p in [HERE,HERE.parent/'cc17']:sys.path.insert(0,str(p))
import restore_dataset as R
import cc18_dataset as D
CORE='cc19-policy-core-joint-verified'
FULL=[f'cc18-final-{i:02d}' for i in range(8)]
ACAM=['acam-available-test-v18','cc19-acam-shotbench-native-supplement']

def collect(parts_dirs):
    result={}
    for directory in parts_dirs:
        if not directory.is_dir():raise ValueError('Part directory is unavailable: '+str(directory))
        for label,item in R.discover(directory).items():
            if label not in result:result[label]=item;continue
            if result[label]['release']!=item['release']:raise ValueError('Conflicting manifests: '+label)
            result[label]['parts'].update(item['parts'])
    return result

def selected_labels(component):
    if component=='policy':return [CORE]
    if component=='synthetic-full':return FULL
    if component=='acam-evaluation':return ACAM
    raise ValueError('Unknown component')

def merge_acam(roots,out):
    records=[];seen=set();native={};base=roots[0]
    # Account for every original author annotation independently of the supplied joins.
    for path in sorted((base/'native').glob('*test.jsonl')):
        for i,line in enumerate(path.read_text().splitlines()):
            if line.strip():native[path.stem+':'+str(i)]=json.loads(line)
    if len(native)!=4153:raise ValueError('Expected the frozen 4153 native ACaM annotations')
    counts=collections.Counter()
    for root in roots:
        for row in D.lines(root/'records.jsonl'):
            rid=row['record_id']
            if rid in seen:raise ValueError('Repeated ACaM record ID: '+rid)
            if row.get('training_eligible') is not False or row['official_split']!='test':raise ValueError('Evaluation source attempted to enter training')
            if rid not in native or row['native_annotation']!=native[rid]:raise ValueError('Native annotation mismatch: '+rid)
            path=D.allowed_path(root,row['input']['video_path'])
            if not path.is_file():raise ValueError('Missing evaluated media: '+rid)
            new=copy.deepcopy(row);new['component_root']=str(root.resolve());new['resolved_video_path']=str(path)
            records.append(new);seen.add(rid);counts[root.name]+=1
    missing=sorted(set(native)-seen)
    with (out/'ACAM_EVALUATION_INDEX.jsonl').open('w') as f:
        for row in records:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')
    (out/'ACAM_UNRESOLVED_NATIVE_IDS.json').write_text(json.dumps(missing,indent=2)+'\n')
    summary={'joined_rows':len(records),'complete_native_annotations':len(native),'unresolved_native_rows':len(missing),
      'component_counts':dict(counts),'duplicate_record_ids':0,'native_annotations_verified':len(records),
      'train_rows':0,'operator_utility_labels':0,'model_calls':0,
      'evaluation_scope':'native author targets with documented compact media derivatives; not unchanged full-video leaderboard input'}
    (out/'ACAM_JOIN_RECEIPT.json').write_text(json.dumps(summary,indent=2)+'\n')
    return summary

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parts-dir',action='append',required=True,type=Path)
    p.add_argument('--component',choices=['policy','synthetic-full','acam-evaluation'],default='policy')
    p.add_argument('--key',type=Path);p.add_argument('--out',type=Path);p.add_argument('--list',action='store_true')
    p.add_argument('--catalog',type=Path,default=HERE/'DATASET_CATALOG.json')
    a=p.parse_args();releases=collect(a.parts_dir);wanted=selected_labels(a.component)
    state=[{'label':label,'expected_parts':len(releases[label]['release']['parts']) if label in releases else None,
            'found_parts':len(releases[label]['parts']) if label in releases else 0,
            'missing':R.missing(releases[label]) if label in releases else ['entire component']} for label in wanted]
    if a.list:print(json.dumps(state,indent=2));return
    if not a.key or not a.out:p.error('--key and --out are required for restoration')
    if any(s['missing'] for s in state):raise ValueError('Incomplete selected package: '+json.dumps(state))
    if not a.catalog.is_file():raise ValueError('Pinned DATASET_CATALOG.json is required')
    catalog=json.loads(a.catalog.read_text());pinned={r['release']['label']:r['release'] for r in catalog['components']}
    for label in wanted:
        if label not in pinned or pinned[label]!=releases[label]['release']:raise ValueError('Release differs from pinned delivery catalog: '+label)
    destination=a.out.resolve()/a.component;destination.mkdir(parents=True,exist_ok=True)
    receipts=[];roots=[]
    for label in wanted:
        root=destination/label
        if root.exists():
            checked=R.verify_payload(root,releases[label]['release'])
            receipt={'label':label,'existing_payload_reverified':True,**checked}
        else:receipt=R.restore_one(releases[label],a.key,destination)
        receipts.append(receipt);roots.append(root)
    if a.component in ['policy','synthetic-full']:
        # audit only selected roots: the compact representation is never mixed with full.
        selected_root=roots[0] if a.component=='policy' else destination
        report=D.audit(selected_root)
        (destination/'ACTUAL_CONSUMER_RECEIPT.json').write_text(json.dumps(report,indent=2)+'\n')
        selection={'representation':a.component,'data_roots':[str(r) for r in roots],
            'allowed_training_split':'train','validation_split':'validation','heldout_split':'test',
            'row_counts':report['counts'],'task':'physical goal-conditioned action ranking',
            'human_utility_supervision':False,'full_cameracoach_training_ready':False,
            'remaining_conditions':['resolve any near-duplicate screening candidates before heldout quality claims','independent real-world utility and transfer','image preprocessing on target device','separate permission for model execution']}
        (destination/'TRAINING_SELECTION.json').write_text(json.dumps(selection,indent=2)+'\n')
    else:report=merge_acam(roots,destination)
    (destination/'ACTUAL_RESTORE_RECEIPTS.json').write_text(json.dumps(receipts,indent=2)+'\n')
    print(json.dumps({'component':a.component,'restored_root':str(destination),'receipt':report,'model_calls':0,'TRAINING_READY':False},indent=2))

if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,OSError,KeyError,AssertionError) as exc:
        print(type(exc).__name__+': '+str(exc),file=sys.stderr);sys.exit(2)
