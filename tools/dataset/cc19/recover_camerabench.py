"""Native public-author CameraBench supplement for ACaM, strictly test/reference.
No approximate joins, downloads from paywalls, teacher/model calls, or public media.
The conflicting source rights are preserved; commercial-training eligibility is false.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
from urllib.parse import quote
import av
import numpy as np
import imageio_ffmpeg
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'cc17'))
from acquire import SOURCES,source_info,acquire_files,download,digest,write_json
from release_pack import package

ROOT=Path('camerabench_supplement');ROOT.mkdir(exist_ok=True)
SOURCES['cb_video']=('syCen/Videos4CameraBench',None)
SOURCES['cb_annotations']=('syCen/CameraBench',None)
repo,rev,files=source_info('cb_video',ROOT/'video_source')
arepo,arev,afiles=source_info('cb_annotations',ROOT/'annotation_source')
assert not json.loads((ROOT/'video_source/source_info.json').read_text()).get('gated'), 'No access-restriction bypass permitted'
assert not json.loads((ROOT/'annotation_source/source_info.json').read_text()).get('gated')
for key,folder,repository,revision,tree in [('video',ROOT/'video_source',repo,rev,files),('annotations',ROOT/'annotation_source',arepo,arev,afiles)]:
    for f in tree:
        if f['path'].endswith(('README.md','LICENSE','LICENSE.txt','videos_test.jsonl')):
            download(f'https://huggingface.co/datasets/{repository}/resolve/{revision}/'+quote(f['path'],safe='/'),folder/'native'/f['path'],f.get('size'),f.get('lfs',{}).get('oid'))
receipts=acquire_files('acam',ROOT/'acam',lambda f:f['path'].endswith(('.jsonl','.md')))
assert all(r['status']=='downloaded' for r in receipts)
requested=[]
for p in sorted((ROOT/'acam/native').glob('*.jsonl')):
    for i,line in enumerate(p.read_text().splitlines()):
        if not line.strip():continue
        r=json.loads(line)
        if '/camerabench/' in r['image'].lower():requested.append({'record_id':p.stem+':'+str(i),'file':p.name,'row':i,'native':r})
assert requested,'No exact CameraBench references in pinned ACaM source'
native_annotation=ROOT/'annotation_source/native/videos_test.jsonl'
assert native_annotation.is_file()
upstream=collections.defaultdict(list)
for i,line in enumerate(native_annotation.read_text().splitlines()):
    if not line.strip():continue
    r=json.loads(line);name=Path(r.get('video',r.get('path',''))).name
    if name:upstream[name].append({'row':i,'native':r})
by_name=collections.defaultdict(list)
for f in files:
    if f['path'].lower().endswith('.mp4'):by_name[Path(f['path']).name].append(f)
accepted=[];blocked=[]
for r in requested:
    name=Path(r['native']['image']).name;hits=by_name[name];ann=upstream[name]
    if len(hits)!=1 or len(ann)!=1:
        blocked.append({**r,'reason':'requires one exact original basename in both native author sources','file_hits':len(hits),'annotation_hits':len(ann)});continue
    accepted.append({**r,'file_entry':hits[0],'camera_bench_native_annotation':ann[0]})
write_json(ROOT/'JOIN_PREFLIGHT.json',{'requested':len(requested),'exact_joined':len(accepted),'blocked':len(blocked),'video_revision':rev,'annotation_revision':arev,'estimated_native_bytes':sum(r['file_entry']['size'] for r in accepted)})
assert accepted
# Do not expand a corpus with unexpectedly huge or unsupported source objects.
assert sum(r['file_entry']['size'] for r in accepted)<4*1024**3
assert all(0<r['file_entry']['size']<150*1024**2 for r in accepted)
FF=imageio_ffmpeg.get_ffmpeg_exe()

def acquire_one(row):
    f=row['file_entry'];name=Path(f['path']).name;src=ROOT/'native_videos'/name
    rec=download(f'https://huggingface.co/datasets/{repo}/resolve/{rev}/'+quote(f['path'],safe='/'),src,f.get('size'),f.get('lfs',{}).get('oid'))
    pts=[];n=0
    with av.open(str(src)) as c:
        stream=c.streams.video[0]
        meta={'width':stream.width,'height':stream.height,'average_rate':str(stream.average_rate),'time_base':str(stream.time_base),'stream_duration':stream.duration,'codec':stream.codec_context.name}
        for frame in c.decode(video=0):
            assert frame.pts is not None
            pts.append({'pts':int(frame.pts),'time_base':str(frame.time_base),'t_seconds':float(frame.pts*frame.time_base)});n+=1
    assert n>=2 and all(pts[i]['t_seconds']<=pts[i+1]['t_seconds'] for i in range(n-1))
    deltas=[pts[i+1]['t_seconds']-pts[i]['t_seconds'] for i in range(n-1) if pts[i+1]['t_seconds']>pts[i]['t_seconds']]
    assert deltas
    duration=pts[-1]['t_seconds']-pts[0]['t_seconds']+float(np.median(deltas))
    assert 0<duration<600
    dest=ROOT/'media'/(src.stem+'.mp4');dest.parent.mkdir(exist_ok=True)
    cmd=[FF,'-v','error','-threads','1','-i',str(src),'-an','-vf',f'fps={16/duration:.12g}:start_time=0,scale=320:320:force_original_aspect_ratio=decrease:force_divisible_by=2','-frames:v','16','-c:v','libx264','-preset','veryfast','-crf','20','-threads','1','-pix_fmt','yuv420p',str(dest)]
    p=subprocess.run(cmd,capture_output=True,timeout=180)
    if p.returncode:raise RuntimeError('Derivative encoding failed: '+p.stderr.decode(errors='replace')[-300:])
    with av.open(str(dest)) as c:
        decoded=list(c.decode(video=0));assert 2<=len(decoded)<=16
        derivative={'frames':len(decoded),'width':decoded[0].width,'height':decoded[0].height,'decoded_all_frames':True}
    ptspath=ROOT/'native_timestamps'/(src.stem+'.json');write_json(ptspath,pts)
    return {'asset_id':rec['sha256'],'source_file':f['path'],'source_revision':rev,'source_url':rec['url'],
      'native_path':str(src.relative_to(ROOT)),'native_sha256':rec['sha256'],'native_bytes':rec['bytes'],
      'native_video_probe':meta,'native_frames_fully_decoded':n,'native_timestamp_file':str(ptspath.relative_to(ROOT)),
      'path':str(dest.relative_to(ROOT)),'sha256':digest(dest),'bytes':dest.stat().st_size,
      'derivative':derivative,'recipe':'16-frame max320 aspect-preserved H264 CRF20 no audio; original bytes retained separately',
      'source_duration_s_from_pts':duration,'not_sensor_capture_clock':True}

# One actual source sample must pass before bulk acquisition.
first=acquire_one(accepted[0]);media={accepted[0]['record_id']:first}
print('CC19_CB_SAMPLE_PASS '+json.dumps({'record_id':accepted[0]['record_id'],'native_frames':first['native_frames_fully_decoded'],'native_bytes':first['native_bytes']}),flush=True)
with cf.ThreadPoolExecutor(max_workers=4) as pool:
    for i,(row,m) in enumerate(zip(accepted[1:],pool.map(acquire_one,accepted[1:])),1):
        media[row['record_id']]=m
        if i%50==0:print('CC19_CB_ACQUIRED',i+1,len(accepted),flush=True)
records=[]
for row in accepted:
    r=row['native'];m=media[row['record_id']];answer=r.get('correct_answer',r.get('label'));options=r.get('options')
    assert answer in options
    records.append({'schema':'cc17.camera_motion_test.v1','record_id':row['record_id'],'official_split':'test','use':'research_evaluation_reference','source_annotation_file':row['file'],'source_row_index':row['row'],
       'native_annotation':r,'camera_bench_native_annotation':row['camera_bench_native_annotation'],
       'media_asset_id':m['asset_id'],'input':{'video_path':m['path'],'native_video_path':m['native_path'],'question':r['question'],'options':options},
       'target':{'answer':answer,'camera_motion':r.get('camera movement',r.get('camera_motion')),'known':True},'training_eligible':False,
       'join_rule':'unique full basename in pinned ACaM, CameraBench native video annotations, and same-author Videos4CameraBench file tree',
       'rights_scope':'commercial use unresolved: preserve CC-BY metadata, original film-rights caveat, and ACaM NC-SA terms; no redistribution or commercial training authorized',
       'operator_utility':None,'capture_time_user_intent':None})
assert len({r['record_id'] for r in records})==len(records)
for name,rows in [('records.jsonl',records),('media_manifest.jsonl',list(media.values()))]:
    with (ROOT/name).open('w') as f:
        for r in rows:f.write(json.dumps(r,ensure_ascii=False,allow_nan=False)+'\n')
write_json(ROOT/'blocked_rows.json',blocked)
summary={'requested_acam_camera_bench_rows':len(requested),'resolved_rows':len(records),'blocked_rows':len(blocked),'native_videos_retained':len(media),
 'native_bytes':sum(m['native_bytes'] for m in media.values()),'native_frames_fully_decoded':sum(m['native_frames_fully_decoded'] for m in media.values()),
 'derivative_videos_fully_decoded':len(media),'video_repository':repo,'video_revision':rev,'annotation_repository':arepo,'annotation_revision':arev,
 'train_rows':0,'human_utility_labels':0,'model_calls':0,'commercial_training_rights_confirmed':False,
 'base_acam_release':'acam-available-test-v18','merge_rule':'append exact record_ids; keep missing history unchanged; native and derived paths relative to this supplement only'}
write_json(ROOT/'QA.json',summary)
write_json(ROOT/'ENVIRONMENT.json',{'python':sys.version,'av':av.__version__,'numpy':np.__version__,'ffmpeg':subprocess.run([FF,'-version'],capture_output=True,text=True).stdout})
(ROOT/'README_RU.md').write_text('# ACaM: восстановленные оригиналы CameraBench\n\nВыбраны только точные имена файлов, одновременно присутствующие в ACaM, нативных аннотациях CameraBench и отдельном MP4-репозитории того же автора. Никакого сопоставления по сходству изображений.\n\nВ комплекте неизменённые исходные MP4, SHA, покадровые PTS и отдельные компактные производные. Весь исходный и производный видеопоток декодирован. Контейнерные PTS не объявляются часами сенсора.\n\nТолько reference/research-evaluation. CC-BY на карточке автора не снимает ограничения ACaM и права на исходные произведения. Не допускать в коммерческое обучение, не раздавать публично.\n')
(ROOT/'reproduction').mkdir(exist_ok=True);shutil.copyfile(__file__,ROOT/'reproduction/recover_camerabench.py')
print('CC19_CAMERABENCH_SUMMARY '+json.dumps(summary),flush=True)
package(ROOT,'cc19-acam-camerabench-native-supplement')
