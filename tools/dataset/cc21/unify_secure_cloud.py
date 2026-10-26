"""CameraCoach v21: data-only cloud merge of verified synthetic observations.
Only encrypted payloads leave each worker. No model training or private user media.
"""
from __future__ import annotations
import argparse,json,os,sys,time,shutil,zipfile,hashlib,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/dataset/cc19'))
sys.path.insert(0,str(ROOT/'tools/dataset/cc17'))
sys.path.insert(0,str(ROOT/'tools/dataset/cc20'))
import secure_joint_audit as J

def dump(path,obj):
    Path(path).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')

def temporal(shard):
    recipient=J.wait_artifact('cc19-audit-public-recipient',seconds=420)
    J.download_artifact(recipient,'public.zip')
    with zipfile.ZipFile('public.zip') as z:
        names=[n for n in z.namelist() if n.endswith('audit-public.pem')]
        assert len(names)==1
        Path('audit-public.pem').write_bytes(z.read(names[0]))
    import temporal_factory as T
    old=T.package
    def seal(data_root,label):
        release=old(data_root,label)
        destination=Path('sealed');destination.mkdir(exist_ok=True)
        subprocess.run(['openssl','cms','-encrypt','-binary','-aes-256-cbc','-stream',
            '-in',release['plaintext_name'],'-out',str(destination/'payload.cms'),
            '-outform','DER',str(ROOT/'tools/dataset/cc17/transport_public.pem'),'audit-public.pem'],
            check=True,stdout=subprocess.DEVNULL)
        dump(destination/'REPLAY.json',{'shard':shard,'label':label,
            'plaintext_sha256':release['plaintext_sha256'],'plaintext_bytes':release['plaintext_bytes'],
            'ciphertext_sha256':J.sha(destination/'payload.cms')})
        shutil.copyfile(Path(data_root)/'QA.json',destination/'BUILD_QA.json')
        return release
    T.package=seal
    T.run(shard,4,128)

def restore_temporal(key):
    root=Path('temporal_data');root.mkdir(exist_ok=True)
    receipts=[];finished=set();deadline=time.monotonic()+3000
    while len(finished)!=4 and time.monotonic()<deadline:
        artifacts=J.api(f'/actions/runs/{J.RUN}/artifacts?per_page=100')['artifacts']
        for artifact in artifacts:
            if not artifact['name'].startswith('cc21-unify-temporal-'):continue
            shard=int(artifact['name'].rsplit('-',1)[1])
            if shard in finished:continue
            J.download_artifact(artifact,'download.zip')
            with zipfile.ZipFile('download.zip') as z:
                for name in ['payload.cms','REPLAY.json','BUILD_QA.json']:
                    members=[n for n in z.namelist() if n==name or n.endswith('/'+name)]
                    assert len(members)==1
                    with z.open(members[0]) as r,Path(name).open('wb') as w:shutil.copyfileobj(r,w)
            meta=json.loads(Path('REPLAY.json').read_text())
            assert meta['shard']==shard and J.sha('payload.cms')==meta['ciphertext_sha256']
            subprocess.run(['openssl','cms','-decrypt','-binary','-inform','DER',
                '-in','payload.cms','-inkey',key,'-out','decoded.tar.gz'],check=True,stdout=subprocess.DEVNULL)
            assert J.sha('decoded.tar.gz')==meta['plaintext_sha256']
            stats=J.extract_checked('decoded.tar.gz',root/f'shard_{shard:02d}')
            receipts.append({'shard':shard,'source_artifact':artifact['id'],**stats})
            finished.add(shard)
            for p in ['payload.cms','download.zip','decoded.tar.gz','REPLAY.json','BUILD_QA.json']:Path(p).unlink()
        if len(finished)!=4:time.sleep(10)
    assert len(finished)==4,{'missing_temporal_shards':list(set(range(4))-finished)}
    return root,receipts

def collect(key):
    import release_pack
    saved=release_pack.package
    release_pack.package=lambda root,label:None
    try:J.joint(str(key))
    finally:release_pack.package=saved
    temporal_root,receipts=restore_temporal(str(key))
    import merge_sources as M
    data=Path('cc21-unified-actions')
    report=M.build(Path('joint_data'),temporal_root,data)
    clean=M.clean_replay(data)
    assert report['rows']==4889 and clean['all_split_tensor_hashes_equal']
    import unified_dataset as U
    sha_splits=report['stream_hashes']
    # Package only the owner-encrypted release.
    saved(data,'cc21-unified-actions')
    release=json.loads(Path('delivery/RELEASE.json').read_text())
    assert release['archive_readback_mismatches']==[]
    proof=Path('proof');proof.mkdir(exist_ok=True)
    dump(proof/'UNIFIED_QA.json',report)
    dump(proof/'CLEAN_REPLAY.json',clean)
    dump(proof/'TEMPORAL_RECEIPTS.json',receipts)
    dump(proof/'RELEASE.json',release)
    dump(proof/'ACCEPTANCE_STATUS.json',{
        'component_dataset_ready':True,'rows':report['rows'],
        'splits':{s:report['counts'][s] for s in ['train','validation','test']},
        'verified_tensor_sha256':sha_splits,
        'full_cameracoach_training_ready':False,
        'human_utility_labels':0,'real_iPhone_transfer_verified':False,
        'original_Drive_archives_read_back':False,'training_executed':False,
        'source':'reproduced accepted scene seeds and jointly rebuilt numeric batches'})
    print('CC21_UNIFIED_ACTUAL '+json.dumps({
        'rows':report['rows'],'source_v19':report['counts']['source:v19'],
        'source_v20':report['counts']['source:v20'],
        'batches':report['actual_batches'],'split_hashes':sha_splits,
        'clean_replay':True,'encrypted_delivery_parts':len(release['parts'])}),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['temporal','collect']);p.add_argument('--shard',type=int);p.add_argument('--key');a=p.parse_args()
    if a.mode=='temporal':temporal(a.shard)
    else:collect(a.key)
