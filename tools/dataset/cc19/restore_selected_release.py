"""Restore and exhaustively read the final SELECTED CameraCoach component.
Private cloud use only; no network, models, credentials upload, or key output.
Requires the release catalog delivered beside this script, NumPy and Pillow.
"""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
import restore_dataset as R
import selected_reader as S
LABEL='cc19-policy-selected-verified'

def find_selected(folders,catalog):
    expected=catalog['selected_policy']['release']
    if expected['label']!=LABEL:raise ValueError('Incorrect trusted release label')
    merged={'release':expected,'parts':{}}
    for folder in folders:
        for label,item in R.discover(folder).items():
            if label!=LABEL:continue
            if item['release']!=expected:raise ValueError('Release differs from the separately pinned catalog')
            for name,location in item['parts'].items():merged['parts'].setdefault(name,location)
    return merged

def restore_and_check(folders,key,out,catalog):
    item=find_selected(folders,catalog)
    if R.missing(item):raise ValueError('Incomplete selected release: '+', '.join(R.missing(item)))
    out.mkdir(parents=True,exist_ok=True);dest=out/LABEL
    if dest.exists():
        # Strict read/verify, never overwrite previous files silently.
        restored={'existing_destination_reverified':True,**R.verify_payload(dest,item['release'])}
    else:restored=R.restore_one(item,key,out)
    reader=S.verify(dest)
    expected=catalog['expected_tensor_streams']
    for split,ref in expected.items():
        actual=reader['split_checks'][split]
        if actual['records']!=ref['records'] or actual['tensor_stream_sha256']!=ref['tensor_stream_sha256']:
            raise ValueError('Actual numeric batch stream differs for '+split)
    receipt={'schema':'cc19.private_restore_and_batch.v1','release':LABEL,'restore':restored,'reader':reader,
      'all_reference_tensor_hashes_match':True,'source':'files explicitly supplied by the caller; receipt does not independently identify Google Drive transport',
      'model_calls':0,'owner_key_printed_or_uploaded':False,'full_cameracoach_training_ready':False}
    (out/'SELECTED_RESTORE_AND_BATCH_RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    return receipt

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parts-dir',action='append',type=Path,required=True)
    p.add_argument('--catalog',type=Path,default=Path(__file__).with_name('FINAL_RELEASE_CATALOG.json'))
    p.add_argument('--key',type=Path);p.add_argument('--out',type=Path);p.add_argument('--list',action='store_true');a=p.parse_args()
    catalog=json.loads(a.catalog.read_text());item=find_selected(a.parts_dir,catalog)
    if a.list:
        print(json.dumps({'label':LABEL,'expected_parts':len(item['release']['parts']),'found_parts':len(item['parts']),'missing_parts':R.missing(item),'selected_policy_rows':3353,'training_split_rows':2184},indent=2));return
    if not a.key or not a.out:p.error('--key and --out required for restoration')
    result=restore_and_check(a.parts_dir,a.key,a.out,catalog)
    print(json.dumps({'label':LABEL,'rows_checked':result['reader']['selected_records'],'all_batch_hashes_match':True,'component_scope':result['reader']['component_scope'],'full_cameracoach_training_ready':False},ensure_ascii=False))
if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,OSError) as e:
        print(type(e).__name__+': '+str(e),file=sys.stderr);sys.exit(2)
