"""Recover only ACaM ShotBench rows from the authors' native ShotBench archive.
All examples remain evaluation-only. No substring/fuzzy/video-similarity joins.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,csv,hashlib,json,subprocess,tarfile,shutil
from pathlib import Path
import requests
from acquire import acquire_files,digest,write_json
from release_pack import package
REV='1a34a402c4626488572aa1a2b559e2e221e37adc'
BASE='https://huggingface.co/datasets/Vchitect/ShotBench/resolve/'+REV+'/'
ARCHIVE_SHA='1e9537821a314a9910f0b14d5e8a06e0adeaa4dae5827291d72c4e9b835c5054'
root=Path('shotbench_supplement');root.mkdir(exist_ok=True);(root/'native').mkdir(exist_ok=True);cache=Path('shotbench_native_cache');cache.mkdir(exist_ok=True)
for name in ['README.md','test.tsv','videos.tar']:
    p=(cache/name) if name.endswith('.tar') else (root/'native'/name)
    with requests.get(BASE+name,stream=True,timeout=(20,120)) as response:
        response.raise_for_status()
        with p.open('wb') as f:
            for block in response.iter_content(8*1024*1024):f.write(block)
    if name=='videos.tar':assert digest(p)==ARCHIVE_SHA
acquire_files('acam',root/'acam',lambda f:f['path'].endswith('.jsonl'))
acam=[]
for p in (root/'acam/native').glob('*.jsonl'):
    for i,line in enumerate(p.read_text().splitlines()):
        if not line.strip():continue
        r=json.loads(line)
        if '/ShotBench/' in r['image']:acam.append({'annotation_file':p.name,'row_index':i,'native':r})
with (root/'native/test.tsv').open() as f:upstream=list(csv.DictReader(f,delimiter='\t'))
assert upstream
upstream_paths={Path(r['path']).name for r in upstream if str(r.get('type','')).lower()=='video'}
# Detect exact full basenames appearing in both benchmark annotation sets.
required={Path(r['native']['image']).name for r in acam}
by_name=collections.defaultdict(list);all_members=[]
with tarfile.open(cache/'videos.tar','r:') as tar:
    for member in tar:
        if not member.isfile():continue
        if member.name.startswith('/') or '..' in Path(member.name).parts:raise ValueError('Unsafe source member')
        if not member.name.lower().endswith(('.mp4','.mov','.avi','.mkv','.webm')):continue
        name=Path(member.name).name;source=tar.extractfile(member);h=hashlib.sha256();n=0
        dest=cache/(hashlib.sha256(member.name.encode()).hexdigest()+Path(name).suffix) if name in required else None
        f=dest.open('wb') if dest else None
        try:
            for block in iter(lambda:source.read(1024*1024),b''):
                h.update(block);n+=len(block)
                if f:f.write(block)
        finally:
            source.close()
            if f:f.close()
        assert n==member.size
        row={'native_member':member.name,'native_sha256':h.hexdigest(),'native_bytes':n,'source_revision':REV}
        all_members.append(row)
        if dest:row['local_source']=str(dest);by_name[name].append(row)
valid=[];blocked=[]
for row in acam:
    name=Path(row['native']['image']).name;candidates=by_name.get(name,[])
    if len(candidates)!=1 or name not in upstream_paths:
        blocked.append({**row,'reason':'not one exact native filename present in BOTH author benchmarks','native_candidates':len(candidates),'in_upstream_test':name in upstream_paths});continue
    valid.append({**row,'asset':candidates[0]})
assert valid,{'upstream_columns':list(upstream[0]),'upstream_type_values':sorted({r.get('type','') for r in upstream}),'requested':len(acam),'blocked':len(blocked)}
assets={v['asset']['native_sha256']:v['asset'] for v in valid};(root/'media').mkdir(exist_ok=True)
def work(item):
    key,row=item;src=Path(row['local_source']);dest=root/'media'/(key+'.mp4')
    r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',str(src)],capture_output=True,text=True,timeout=30)
    assert r.returncode==0;p=json.loads(r.stdout);duration=float(p['format']['duration']);assert duration>0
    q=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(src),'-an','-vf',f'fps={16/duration:.12g}:start_time=0,scale=320:320:force_original_aspect_ratio=decrease:force_divisible_by=2','-frames:v','16','-c:v','libx264','-preset','veryfast','-crf','20','-threads','1','-pix_fmt','yuv420p','-movflags','+faststart',str(dest)],capture_output=True,timeout=180);assert q.returncode==0
    p=subprocess.run(['ffprobe','-v','error','-count_frames','-select_streams','v:0','-show_entries','stream=nb_read_frames,width,height','-of','json',str(dest)],capture_output=True,text=True,timeout=30);probe=json.loads(p.stdout);assert p.returncode==0 and 2<=int(probe['streams'][0]['nb_read_frames'])<=16
    p=subprocess.run(['ffmpeg','-v','error','-threads','1','-i',str(dest),'-f','null','-'],capture_output=True,timeout=60);assert p.returncode==0
    return key,{k:v for k,v in row.items() if k!='local_source'}|{'path':str(dest.relative_to(root)),'sha256':digest(dest),'bytes':dest.stat().st_size,'source_duration_s':duration,'derivative_probe':probe,'all_derivative_frames_decoded':True,'recipe':'16/source_duration fps; max320; H264 CRF20; no audio'}
with cf.ThreadPoolExecutor(max_workers=6) as ex:media=dict(ex.map(work,assets.items()))
records=[]
for v in valid:
    r=v['native'];m=media[v['asset']['native_sha256']];answer=r.get('correct_answer',r.get('label'));opts=r.get('options');assert answer in opts
    records.append({'schema':'cc17.camera_motion_test.v1','record_id':Path(v['annotation_file']).stem+':'+str(v['row_index']),'official_split':'test','use':'evaluation_only','source_annotation_file':v['annotation_file'],'source_row_index':v['row_index'],'native_annotation':r,
       'media_asset_id':v['asset']['native_sha256'],'input':{'video_path':m['path'],'question':r['question'],'options':opts},'target':{'answer':answer,'camera_motion':r.get('camera movement',r.get('camera_motion')),'known':True},'training_eligible':False,
       'join_rule':'exact unique full basename shared by ACaM ShotBench reference, ShotBench author test.tsv and author videos.tar; no fuzzy matching',
       'rights_scope':'evaluation research only; ACaM CC-BY-NC-SA-4.0, ShotBench card Apache-2.0 does not establish underlying film commercial rights','operator_utility':None,'capture_time_user_intent':None})
for name,rows in [('records.jsonl',records),('media_manifest.jsonl',list(media.values())),('native_archive_members.jsonl',all_members)]:
    with (root/name).open('w') as f:
        for r in rows:f.write(json.dumps(r,ensure_ascii=False,allow_nan=False)+'\n')
write_json(root/'blocked_rows.json',blocked)
q={'requested_acam_shotbench_rows':len(acam),'resolved_rows':len(records),'blocked_rows':len(blocked),'resolved_unique_videos':len(media),'native_archive_video_members_read':len(all_members),'native_archive_sha256':ARCHIVE_SHA,'source_revision':REV,'full_derivative_decodes':len(media),'train_rows':0,'human_operator_utility_labels':0,'model_calls':0,
   'duplicate_record_ids':len(records)-len({r['record_id'] for r in records}),'base_acam_release':'acam-available-test-v18','merge_rule':'append these distinct record_ids to base records; remove corresponding IDs from effective quarantine; preserve original quarantine file historically'}
write_json(root/'QA.json',q);write_json(root/'SOURCE_RECEIPT.json',{'url':BASE+'videos.tar','sha256':ARCHIVE_SHA,'bytes':(cache/'videos.tar').stat().st_size,'raw_archive_in_release':False})
(root/'README_RU.md').write_text('# Дополнение ACaM из официального ShotBench\n\nТолько evaluation. Native-видео реально получены из pinned videos.tar и сопоставлены по уникальному полному имени, присутствующему в двух авторских наборах аннотаций.\n\nAppend records.jsonl к acam-available-test-v18 по record_id; исходный blocked_original_media.json не переписывать, применить дополнение к эффективному списку. Относительные video_path относятся к корню именно этого дополнения.\n\nПроизводные до16 кадров, max320, CRF20, без аудио. Это не неизменённый официальный full-video benchmark. Movie rights и право коммерческого обучения не подтверждены. Не использовать для обучения CameraCoach.\n')
shutil.rmtree(cache);print('CC18_SHOTBENCH_SUMMARY '+json.dumps(q),flush=True);package(root,'cc18-acam-shotbench-supplement')
