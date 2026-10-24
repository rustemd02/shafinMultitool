"""Full HoloAssist native capture-quality cue census, not a new human study.
Original released videos are fetched and hashed; retained excerpts remux the
original encoded video packets without re-encoding. No inferred success labels.
"""
from __future__ import annotations
import collections,concurrent.futures as cf,hashlib,json,shutil,tempfile
from pathlib import Path
import av,numpy as np
from PIL import Image
import holoassist_real as H
from real_common import fetch,jsonl,write_json,digest,finish
import real_dataset as D
ROOT=Path('cc20-holoassist-all-cues');ROOT.mkdir(exist_ok=True)
H.ROOT=ROOT

def exact_excerpt(source,dest,start,end):
    """Retain keyframe context; preserve encoded payloads and record time shift."""
    dest.parent.mkdir(parents=True,exist_ok=True);expected=[];source_pts=[];base=None;tb=None
    with av.open(str(source)) as inp:
        stream=inp.streams.video[0];tb=stream.time_base
        inp.seek(max(0,int(start/tb)),stream=stream,backward=True,any_frame=False)
        with av.open(str(dest),'w',format='mp4') as out:
            target=out.add_stream_from_template(stream)
            for packet in inp.demux(stream):
                if packet.dts is None or packet.pts is None:continue
                t=float(packet.pts*packet.time_base)
                if t>end+1.:break
                if base is None:
                    if not packet.is_keyframe:raise ValueError('Excerpt does not start on an original keyframe')
                    base=packet.dts
                expected.append(hashlib.sha256(bytes(packet)).hexdigest());source_pts.append(t)
                packet.pts-=base;packet.dts-=base;packet.stream=target;out.mux(packet)
    if not expected:raise ValueError('No native packets in excerpt')
    actual=[]
    with av.open(str(dest)) as out:
        for p in out.demux(out.streams.video[0]):
            if p.dts is not None and p.pts is not None:actual.append(hashlib.sha256(bytes(p)).hexdigest())
    if actual!=expected:raise ValueError('Encoded packet payload changed during remux')
    pix=set();decoded=0
    with av.open(str(dest)) as out:
        for f in out.decode(video=0):pix.add(hashlib.sha256(f.to_ndarray(format='rgb24').tobytes()).hexdigest());decoded+=1
    return {'path':str(dest.relative_to(ROOT)),'sha256':digest(dest),'bytes':dest.stat().st_size,'native_video_packet_count':len(expected),'native_encoded_packets_identical':True,
       'original_packet_pts_min_s':min(source_pts),'original_packet_pts_max_s':max(source_pts),'container_timestamp_shift_s':float(base*tb),
       'requested_interval_s':[start,end],'decoded_frames':decoded,'audio_retained':False,'representation':'native video packet remux; keyframe context retained'},pix

def one(seq,events,official,member,tar_meta):
    vid=seq['video_name'];tar=H.RangeTar(tar_meta['url']);tar.etag=tar_meta['etag'];tar.total=tar_meta['bytes']
    temp=Path(tempfile.mkdtemp(prefix='holo-source-'));source=temp/'source.mp4';records=[];rejected=[]
    try:
        receipt=tar.extract(member,source)
        frames,probe=H.frames_for_events(source,events,ROOT/'frames'/vid)
        for event in events:
            eid=str(event['id']);cut=float(event['start']);end=float(event['end']);fs=frames.get(eid,{})
            prefix=[fs[x] for x in ['prefix_0','prefix_1','prefix_2'] if x in fs]
            after=[fs[x] for x in ['after_0','after_1'] if x in fs]
            try:
                if len(prefix)!=3:raise ValueError('Missing genuine pre-instruction context')
                assert all(x['t_seconds']<cut for x in prefix)
                clip,pixels=exact_excerpt(source,ROOT/'native_excerpts'/vid/(eid+'.mp4'),max(0.,cut-1.2),end+3.2)
                for frame in prefix+after:
                    with Image.open(ROOT/frame['path']) as im:h=hashlib.sha256(np.asarray(im.convert('RGB')).tobytes()).hexdigest()
                    if h not in pixels:raise ValueError('Retained excerpt missing exact observed frame pixels')
                attr=event['attributes'];text=attr.get('Transcription');known=isinstance(text,str) and bool(text.strip()) and 'unintelligible' not in text.lower()
                r={'record_id':'holoassist:'+vid+':'+eid,'task_type':'human_capture_quality_cue_imitation','origin_group':'holoassist-session:'+vid,
                   'participant_group':None,'independent_participant_split_proven':False,'split':{'train':'train','val':'validation'}.get(official,'quarantine'),'source_official_split':official,
                   'observations':{'rgb_history':prefix,'selected_subject':None,'intent':None,'protected_style':None,'constraints':None,'cutoff_s':cut},
                   'targets':{'native_instruction_text':text,'native_purpose':H.purpose(event),'transcription_confidence':attr.get('Transcription Confidence'),'action_proposed':text,
                       'action_performed':None,'goal_achieved':None,'outcome_preferred':None,'comparison_validity':None,'causal_attribution':None,'human_utility':None},
                   'outcome_observations':after,'native_excerpt':clip,'loss_masks':{'native_instruction_text':known and official in ['train','val'],'action_performed':False,'goal_achieved':False,'outcome_preferred':False,'human_utility':False},
                   'provenance':{'dataset':'HoloAssist','annotation_sha256':H.ANNOTATION_SHA,'native_event':event,'source_video':receipt,'source_full_video_retained':False,
                     'native_media':clip['path'],'media_sha256':clip['sha256'],'label_authority':'native_human_instruction','intent_origin':'native-human-conversation-purpose; not cinematic intent','rights':'CDLA-Permissive-2.0',
                     'confounders':['head-mounted camera differs from iPhone','object manipulation may cause image changes','no action/control pair','no independently annotated command success']}}
                records.append(r)
            except Exception as e:rejected.append({'video_name':vid,'event_id':eid,'reason':type(e).__name__+': '+str(e)[:180]})
        return records,{'video_name':vid,'status':'accepted' if not rejected else 'partial','source_video':receipt,'decoded_source_video':probe,'native_events':len(events),'accepted_events':len(records),'rejected_events':rejected,'official_split':official}
    except Exception as e:return [],{'video_name':vid,'status':'blocked','reason':type(e).__name__+': '+str(e)[:220],'native_events':len(events)}
    finally:shutil.rmtree(temp)

def main():
    r=fetch(H.BASE+'data-annotation-trainval-v1_1.json',ROOT/'native/annotations.json',150_000_000);assert r['sha256']==H.ANNOTATION_SHA
    fetch('https://holoassist.github.io/data_links/README.md',ROOT/'rights/SOURCE_README.md',500_000)
    fetch('https://cdla.dev/permissive-2-0/',ROOT/'rights/CDLA-Permissive-2.0.html',500_000)
    fetch('https://holoassist.github.io/label_files/data-splits-v1_2.zip',ROOT/'native/splits.zip',5_000_000)
    sm,si=H.split_map(ROOT/'native/splits.zip');native=json.loads((ROOT/'native/annotations.json').read_text());selection=[];all_events=[]
    for seq in native:
        es=[e for e in seq['events'] if H.relevant(e)]
        if es:
            official=sm.get(H.normalized(seq['video_name']),'unresolved');selection.append((seq,es,official))
            all_events.extend({'video_name':seq['video_name'],'official_split':official,'native_event':e} for e in es)
    jsonl(ROOT/'ALL_NATIVE_CAPTURE_QUALITY_CUES.jsonl',all_events)
    write_json(ROOT/'PREDECLARED_SELECTION.json',{'all_matching_sessions':len(selection),'all_matching_events':len(all_events),'purpose_filter':'native video quality conversation category','selection_depends_on_outcomes':False,'retain':'all native encoded excerpt packets around every cue; not all unrelated session footage'})
    tar=H.RangeTar(H.BASE+'video_compress.tar');members=tar.scan();meta={'url':tar.url,'etag':tar.etag,'bytes':tar.total};write_json(ROOT/'NATIVE_VIDEO_TAR_INDEX.json',{**meta,'members':members})
    lookup=collections.defaultdict(list)
    for m in members:
        if m['name'].lower().endswith('.mp4'):
            for part in Path(m['name']).parts[:-1]:lookup[H.normalized(part)].append(m)
    jobs=[];trials=[]
    for seq,es,official in selection:
        matches=lookup.get(H.normalized(seq['video_name']),[])
        if len(matches)!=1:trials.append({'video_name':seq['video_name'],'status':'blocked','native_events':len(es),'reason':'nonunique native video join: '+str(len(matches))})
        else:jobs.append((seq,es,official,matches[0],meta))
    print('CC20_HOLO_ALL_SELECTION '+json.dumps({'sessions':len(selection),'events':len(all_events),'exact_video_joins':len(jobs),'native_source_bytes':sum(j[3]['size'] for j in jobs)}),flush=True)
    assert sum(j[3]['size'] for j in jobs)<50_000_000_000,'Unexpected source transfer total'
    # Verify excerpt semantics before expanding the immutable source event census.
    records,trial=one(*jobs[0]);trials.append(trial);assert records,trial
    all_records=list(records)
    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        for rs,t in pool.map(lambda x:one(*x),jobs[1:]):
            all_records.extend(rs);trials.append(t)
            if len(trials)%20==0:print('CC20_HOLO_ALL_PROGRESS '+json.dumps({'sessions':len(trials),'video_backed_events':len(all_records)}),flush=True)
    all_records.sort(key=lambda r:r['record_id']);jsonl(ROOT/'records.jsonl',all_records);jsonl(ROOT/'SOURCE_TRIALS.jsonl',trials)
    audit=D.audit(D.holoassist(ROOT));write_json(ROOT/'PORTABLE_READER_QA.json',audit)
    groups=collections.defaultdict(set)
    for r in all_records:groups[r['split']].add(r['origin_group'])
    assert not groups['train']&groups['validation']
    event_ids={r['record_id'] for r in all_records};assert len(event_ids)==len(all_records)
    rejected=sum(t.get('native_events',0)-t.get('accepted_events',0) for t in trials)
    q={'task':'human_capture_quality_cue_imitation','native_annotation_sessions':len(native),'native_quality_cue_sessions':len(selection),'native_quality_cues':len(all_events),
       'video_backed_records':len(all_records),'rejected_events':rejected,'all_native_events_accounted_for':len(all_records)+rejected==len(all_events),'source_video_sessions_recovered':sum(t['status']!='blocked' for t in trials),
       'splits':dict(collections.Counter(r['split'] for r in all_records)),'known_text_target_records':sum(r['loss_masks']['native_instruction_text'] for r in all_records),
       'native_encoded_excerpts':len(all_records),'exact_frame_and_packet_checks':True,'source_full_video_bytes_read':sum(t.get('source_video',{}).get('size',0) for t in trials),
       'source_full_videos_retained':False,'actual_portable_batches':audit['actual_batches'],'tensor_stream_sha256':audit['tensor_and_text_stream_sha256'],
       'cross_split_session_overlap':0,'participant_independence':'not established; official split retained, no new hidden-test claim','test_records':0,'new_human_responses':0,'human_utility_labels':0,'model_calls':0,'full_cameracoach_training_ready':False}
    (ROOT/'DATASET_CARD_RU.md').write_text('# Все native-команды HoloAssist по качеству видео\n\nДля каждого события сохраняются исходная человеческая реплика, категория, времена, три действительно прошлых RGB, отдельные послекадры и MP4-фрагмент с исходными кодированными video packets. Перекодирования видео нет; контейнер и его отсчёт времени изменены, keyframe-контекст сохранён. Проверены идентичность payload каждого пакета и совпадение пикселей наблюдений с декодированным фрагментом.\n\nПолные видео каждой сессии скачаны и захешированы, но вне нужных эпизодов не включены в этот компактный комплект. URL, TAR ETag/offset/size и SHA исходника сохранены. Старый 20-сессионный пакет пересекается с этим и не является независимым набором.\n\nSplit взят у авторов; три сессии без установленного split остаются quarantine. Независимость повторных участников не доказана. Это imitation человеческих команд, НЕ новые ответы респондентов и НЕ проверенная полезность CameraCoach. Исполнение, причинность и успех неизвестны/null и не участвуют в loss.\n\nИсточник: Wang et al., HoloAssist, ICCV 2023; CDLA-Permissive-2.0, текст лицензии и source README включены.\n')
    finish(ROOT,'cc20-holoassist-all-cues',q)
if __name__=='__main__':main()
