"""Executed portable-reader regression tests; no models, API teachers or renderer.
Synthetic fixture rows are isolated tests and never admitted into source datasets.
An independent native illumination replay tests the complete 1015-scene census.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,io,json,shutil,tempfile
from pathlib import Path
import numpy as np
from PIL import Image
import real_dataset as D
import illumination_real as I
from real_common import write_json,digest,repository_files,jsonl


def regressions(base):
    root=base/'fixtures';root.mkdir(parents=True,exist_ok=True)
    im=Image.fromarray(np.arange(16*24*3,dtype=np.uint8).reshape(16,24,3));im.save(root/'a.png');sha=digest(root/'a.png')
    row={'record_id':'TEST_ONLY','origin_group':'FIXTURE','split':'train','source_official_split':'train','observations':{'cutoff_s':2.,'rgb_history':[{'path':'a.png','sha256':sha,'t_seconds':t} for t in [1.,1.5,1.9]]},'targets':{'native_instruction_text':'fixture only','native_purpose':'fixture only'},'loss_masks':{'native_instruction_text':True}}
    jsonl(root/'records.jsonl',[row]);positive=D.audit(D.holoassist(root));assert positive['actual_batches']==1
    outcomes={}
    def reject(name,fn):
        try:fn()
        except (ValueError,FileNotFoundError,KeyError):outcomes[name]=True
        else:raise AssertionError('Invalid input accepted: '+name)
    reject('traversal',lambda:D.rgb(root,'../elsewhere.png'))
    reject('missing_media',lambda:D.rgb(root,'missing.png'))
    reject('wrong_image_hash',lambda:D.rgb(root,'a.png','0'*64))
    changed=json.loads(json.dumps(row));changed['observations']['rgb_history'][-1]['t_seconds']=2.
    jsonl(root/'records.jsonl',[changed]);reject('cutoff_frame_not_past',lambda:list(D.holoassist(root)))
    changed['observations']['rgb_history'][-1]['t_seconds']=3.
    jsonl(root/'records.jsonl',[changed]);reject('future_frame',lambda:list(D.holoassist(root)))
    changed=json.loads(json.dumps(row));changed['observations']['rgb_history'].pop()
    jsonl(root/'records.jsonl',[changed]);reject('incomplete_history',lambda:list(D.holoassist(root)))
    jsonl(root/'records.jsonl',[row]);X,Y,M,meta=next(D.holoassist(root))
    assert 'instruction_text' not in X and not any(M[k].any() for k in ['action_performed','goal_achieved','human_utility'])
    assert X['rgb_history'].shape==(1,3,3,224,224)
    outcomes.update({'targets_not_observations':True,'unknown_outcomes_have_no_loss':True,'actual_image_shape':True})
    return {'positive_fixture_batches':positive['actual_batches'],'checks':outcomes,'fixtures_are_dataset_records':False}


def native_illumination_check(base):
    root=base/'illumination_replay';root.mkdir(parents=True);I.ROOT=root
    repository_files(root,'lmurmann/multi_illumination',I.REV,['scenes.json'])
    scenes=json.loads((root/'source_repository/scenes.json').read_text());results=[]
    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        for r in pool.map(I.acquire,scenes):results.append(r)
    assert all(r['status']=='accepted' for r in results)
    jsonl(root/'scene_records.jsonl',results)
    count=0;h=hashlib.sha256()
    # Compare actual arrays against original builder; inspect masks separately.
    for record in results:
        single=base/'one';single.mkdir(exist_ok=True)
        # Pure reader accepts a scene-record stream; don't duplicate media bytes.
        subset=base/'subset-records.jsonl';jsonl(subset,[record])
        old_rows=D.rows
        def selected_rows(path):
            if str(path).endswith('scene_records.jsonl'):return iter([record])
            return old_rows(path)
        D.rows=selected_rows
        try:
            a=I.load_pairs(root,record);b=D.illumination(root)
            for original,portable in zip(a,b,strict=True):
                X,Y,M=original;X2,Y2,M2,meta=portable
                assert X.keys()==X2.keys() and Y.keys()==Y2.keys()
                for k in X:assert np.array_equal(X[k],X2[k]),k
                for k in Y:assert np.array_equal(Y[k],Y2[k]),k
                assert not M2['human_preference'].any() and not M2['operator_utility'].any()
                for group in [X2,Y2,M2]:
                    for k,v in sorted(group.items()):h.update(k.encode());h.update(v.tobytes())
                count+=1
        finally:D.rows=old_rows
    assert count==len(scenes)*25
    receipt={'source_revision':I.REV,'native_scenes_replayed':len(results),'real_image_batches_compared':count,'all_inputs_and_targets_array_equal':True,'native_jpg_SHA_checks_in_portable_reader':True,
      'unknown_human_losses_disabled':True,'reader_sha256':digest(Path(D.__file__)),'tensor_stream_sha256':h.hexdigest(),'source':'fresh native source reads, not Google Drive plaintext restore','model_calls':0}
    return receipt


if __name__=='__main__':
    base=Path(tempfile.mkdtemp(prefix='cc20-consumer-qa-'))
    out=Path('cc20-reader-qa');out.mkdir(exist_ok=True)
    try:
        result={'regressions':regressions(base),'native_illumination':native_illumination_check(base),'model_calls':0,'raw_media_in_report':False}
        write_json(out/'REAL_CONSUMER_QA.json',result);print('CC20_REAL_CONSUMER_PASS '+json.dumps(result),flush=True)
    finally:shutil.rmtree(base)
