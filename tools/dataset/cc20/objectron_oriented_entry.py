"""Objectron final input-orientation repair, no changed source labels/media.
Uses the original-author FFmpeg decoding convention for independent pixel checks
at first/middle/last frame of every selected native video. Full tensor traversal
uses only the separately shipped NumPy/Pillow/PyAV reader.
"""
from pathlib import Path
import collections,io,json,subprocess
import av,numpy as np
from PIL import Image
import objectron_native_complete as O
import native_reader as R
from real_common import digest,jsonl,write_json


def verify_orientation(root,record):
    path=Path(root)/record['video'];probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height:stream_tags=rotate:stream_side_data','-of','json',str(path)]))
    stream=probe['streams'][0];rotations=[x['rotation'] for x in stream.get('side_data_list',[]) if 'rotation' in x]
    angle=float(rotations[0] if rotations else stream.get('tags',{}).get('rotate',0))
    k=int(round(angle/90))%4
    if abs(angle/90-round(angle/90))>1e-5:raise ValueError('Non-quarter source display rotation needs explicit transform')
    with np.load(Path(root)/record['labels'],allow_pickle=False) as z:n=len(z['capture_time_s'])
    wanted=sorted({0,n//2,n-1});frames={}
    with av.open(str(path)) as inp:
        for i,f in enumerate(inp.decode(video=0)):
            if i in wanted:frames[i]=f.to_ndarray(format='rgb24')
    checks=[]
    for i in wanted:
        encoded=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-vf',f'select=eq(n\\,{i})','-vsync','0','-frames:v','1','-f','image2pipe','-vcodec','png','-threads','1','-'])
        with Image.open(io.BytesIO(encoded)) as im:reference=np.asarray(im.convert('RGB'))
        actual=np.rot90(frames[i],k)
        if actual.shape!=reference.shape or not np.array_equal(actual,reference):
            raise ValueError('Source-author decoder pixels disagree after declared display rotation: '+record['video_id']+' frame '+str(i))
        checks.append({'frame_id':i,'shape':list(actual.shape),'pixel_equality':True})
    record.update(rgb_rotation_quarters_ccw=k,orientation_verified_against_source_decoder=True,
        display_orientation_evidence={'source_rotation_degrees':angle,'ffprobe':probe,'reference_decoder':'FFmpeg default autorotate, as used by pinned author notebook','sampled_frames':checks,'all_sample_pixels_exact':True})


def audited_batches(root,record,task='perception'):
    if record.get('orientation_verified_against_source_decoder') is not True:verify_orientation(root,record)
    return R.video_batches(root,record,task)
O.tensors=audited_batches
old_finish=O.finish


def finish(root,label,summary):
    records=[json.loads(x) for x in (root/'video_records.jsonl').read_text().splitlines()]
    for r in records:
        k=r['rgb_rotation_quarters_ccw']
        for p in r['previews']:
            path=root/p['path']
            with Image.open(path) as im:
                if k:im=im.transpose({1:Image.Transpose.ROTATE_90,2:Image.Transpose.ROTATE_180,3:Image.Transpose.ROTATE_270}[k])
                im.save(path)
            p['sha256']=digest(path);p['representation']='aspect-preserving source-display-oriented preview; native MOV retained'
    jsonl(root/'video_records.jsonl',records)
    summary['portable_reader_sha256']=digest(Path(R.__file__))
    summary['display_orientation_verified_videos']=len(records)
    summary['independent_exact_pixel_checks']=sum(len(r['display_orientation_evidence']['sampled_frames']) for r in records)
    summary['rotation_quarter_counts']=dict(collections.Counter(str(r['rgb_rotation_quarters_ccw']) for r in records))
    summary['legacy_raw_orientation_release']='cc20-objectron-native-aligned is superseded; its numeric source labels are retained, but unrotated image tensors are not admitted'
    write_json(root/'INPUT_ORIENTATION_QA.json',{'videos':[{'video_id':r['video_id'],'video_sha256':r['video_sha256'],'rotation_quarters_ccw':r['rgb_rotation_quarters_ccw'],**r['display_orientation_evidence']} for r in records]})
    text=(root/'DATASET_CARD_RU.md').read_text().replace('Потоковый tensors() в reproduction_cc20/objectron_native_complete.py','Потоковый batches() в reproduction_cc20/native_reader.py')
    text+='\n## Проверка ориентации изображения\n\nNative MOV сохранены без изменений. При декодировании обязательно применяется `rgb_rotation_quarters_ccw`, извлечённый из display matrix MOV. Для КАЖДОГО видео исходные пиксели первого, среднего и последнего кадров после этого поворота точно совпали с авторской конвенцией FFmpeg. Проверены все фактические batches с исправленным portable reader. Новый reader отвергает legacy-записи без верифицированной ориентации, а не использует нулевой поворот по умолчанию. Нормализованные native keypoints уже относятся к display-oriented изображению и повторно не вращаются.\n'
    (root/'DATASET_CARD_RU.md').write_text(text)
    return old_finish(root,'cc20-objectron-native-oriented',summary)
O.finish=finish
if __name__=='__main__':O.main()
