"""Human-authored capture-quality commands, not invented operator utility.
Select on native purpose annotations before observing outcomes. Published video
members are recovered using ordinary validated HTTP ranges from the public TAR.
A command is an observed speech event; execution and success remain UNKNOWN.
"""
from __future__ import annotations
import argparse,collections,hashlib,io,json,math,re,tarfile,time,zipfile
from pathlib import Path
import av,numpy as np,requests
from PIL import Image
from real_common import fetch,jsonl,write_json,digest,image_tensor,finish,safe_member
BASE='https://hl2data.z5.web.core.windows.net/holoassist-data-release/'
ROOT=Path('cc20-holoassist-capture-cues');ROOT.mkdir(exist_ok=True)
ANNOTATION_SHA='cc7898b49958a62fe021ae2ffa53a709c3fd6f45fd3f893960b8aac6d13dfe9c'

class RangeTar:
    def __init__(self,url):
        self.url=url;self.s=requests.Session();self.etag=None;self.total=None;self.cache=b'';self.start=-1;self.requests=0;self.bytes=0
    def read(self,offset,count):
        if self.start<=offset and offset+count<=self.start+len(self.cache):return self.cache[offset-self.start:offset-self.start+count]
        end=offset+max(count,4096)-1
        if self.total is not None:end=min(end,self.total-1)
        headers={'Range':f'bytes={offset}-{end}','Accept-Encoding':'identity'}
        if self.etag:headers['If-Match']=self.etag
        for retry in range(3):
            with self.s.get(self.url,headers=headers,stream=True,timeout=(20,90)) as r:
                if r.status_code==429:time.sleep(min(120,int(r.headers.get('Retry-After','30'))));continue
                r.raise_for_status()
                if r.status_code!=206:raise ValueError('Server does not support exact byte ranges; no full TAR download')
                cr=r.headers.get('Content-Range','');m=re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)',cr);assert m and int(m[1])==offset
                n=int(m[2])-offset+1
                if n>max(count,4096):raise ValueError('Oversized range')
                b=r.raw.read(n+1);assert len(b)==n
                e=r.headers.get('ETag')
                if self.etag and e!=self.etag:raise ValueError('Source TAR changed')
                self.etag=e;self.total=int(m[3]);self.start=offset;self.cache=b;self.requests+=1;self.bytes+=len(b)
                return b[:count]
        raise RuntimeError('Rate limited range request')
    def scan(self):
        pos=0;pending={};longname=None;members=[]
        for iteration in range(30000):
            b=self.read(pos,512)
            if b==b'\0'*512:break
            t=tarfile.TarInfo.frombuf(b,'utf-8','surrogateescape');data=pos+512
            if t.type in [tarfile.XHDTYPE,tarfile.XGLTYPE]:
                raw=self.read(data,t.size);off=0;attrs={}
                while off<len(raw):
                    space=raw.find(b' ',off);n=int(raw[off:space]);entry=raw[space+1:off+n-1].decode('utf-8');k,v=entry.split('=',1);attrs[k]=v;off+=n
                pending.update(attrs)
            elif t.type==tarfile.GNUTYPE_LONGNAME:longname=self.read(data,t.size).rstrip(b'\0').decode('utf-8')
            else:
                name=pending.get('path',longname or t.name);size=int(pending.get('size',t.size));safe_member(name)
                if t.isfile():members.append({'name':name,'offset':data,'size':size})
                pending={};longname=None
            pos=data+((t.size+511)//512)*512
            if iteration%250==0:print('CC20_HOLO_INDEX_PROGRESS '+json.dumps({'headers':iteration,'files':len(members)}),flush=True)
            if self.total is not None and pos>=self.total:break
        else:raise RuntimeError('TAR index header budget exhausted')
        return members
    def extract(self,member,path):
        path.parent.mkdir(parents=True,exist_ok=True);h=hashlib.sha256()
        with path.open('wb') as f:
            for rel in range(0,member['size'],4*1024*1024):
                b=self.read(member['offset']+rel,min(4*1024*1024,member['size']-rel));f.write(b);h.update(b)
        assert path.stat().st_size==member['size']
        return {'tar_url':self.url,'tar_etag':self.etag,**member,'sha256':h.hexdigest()}

def normalized(s):return re.sub(r'[^a-z0-9]','',str(s).lower())
def purpose(event):return str(event.get('attributes',{}).get('Conversation Purpose',''))
def relevant(event):return 'video' in purpose(event).lower() and 'quality' in purpose(event).lower()

def split_map(path):
    result={};inventory=[]
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        for n in z.namelist():
            safe_member(n)
            if n.endswith('/') or '__MACOSX' in n:continue
            low=Path(n).name.lower();part=next((x for x in ['train','val','test'] if x in low),None)
            if part is None:continue
            content=z.read(n).decode('utf-8-sig');lines=[x.strip() for x in content.splitlines() if x.strip()]
            inventory.append({'file':n,'lines':len(lines),'split':part})
            for line in lines:
                key=normalized(line)
                if key in result and result[key]!=part:raise ValueError('Conflicting official source splits')
                result[key]=part
    return result,inventory

def frames_for_events(path,events,outdir):
    requests_at=[]
    for e in events:
        start,end=float(e['start']),float(e['end'])
        for role,t in [('prefix_0',start-1.0),('prefix_1',start-.5),('prefix_2',start-.05),('after_0',end+1.),('after_1',end+3.)]:
            if t>=0:requests_at.append((t,str(e['id']),role))
    requests_at.sort();out={};k=0;last=-math.inf;decoded=0
    with av.open(str(path)) as v:
        stream=v.streams.video[0];audio=bool(v.streams.audio);rate=str(stream.average_rate)
        previous=None
        for frame in v.decode(stream):
            if frame.pts is None:raise ValueError('Missing native PTS')
            t=float(frame.pts*frame.time_base)
            if t<last:raise ValueError('Non-monotonic video presentation time')
            last=t;decoded+=1
            while k<len(requests_at) and requests_at[k][0]<=t:
                wanted,eid,role=requests_at[k];chosen=previous if role.startswith('prefix') else frame
                if chosen is not None:
                    actual=float(chosen.pts*chosen.time_base)
                    if role.startswith('prefix') and actual>wanted:raise ValueError('Future frame in prefix')
                    p=outdir/eid/(role+'.png');p.parent.mkdir(parents=True,exist_ok=True);im=chosen.to_image();im.save(p)
                    out.setdefault(eid,{})[role]={'path':str(p.relative_to(ROOT)),'pts':int(chosen.pts),'time_base':str(chosen.time_base),'t_seconds':actual,'requested_s':wanted,'sha256':digest(p)}
                k+=1
            previous=frame
    return out,{'decoded_frames':decoded,'last_pts_s':last,'has_audio':audio,'average_rate':rate,'all_frames_decoded':True,'unresolved_requested_frames':len(requests_at)-k}

def main(limit):
    receipt=fetch(BASE+'data-annotation-trainval-v1_1.json',ROOT/'native/annotations.json',150_000_000);assert receipt['sha256']==ANNOTATION_SHA
    fetch('https://holoassist.github.io/data_links/README.md',ROOT/'rights/SOURCE_README.md',500_000)
    fetch('https://cdla.dev/permissive-2-0/',ROOT/'rights/CDLA-Permissive-2.0.html',500_000)
    fetch('https://holoassist.github.io/label_files/data-splits-v1_2.zip',ROOT/'native/splits.zip',5_000_000)
    native=json.loads((ROOT/'native/annotations.json').read_text());sm,si=split_map(ROOT/'native/splits.zip')
    sessions=[];all_cues=[];purposes=collections.Counter()
    for seq in native:
        es=[e for e in seq['events'] if relevant(e)]
        for e in seq['events']:
            if purpose(e):purposes[purpose(e)]+=1
        if not es:continue
        vid=seq['video_name'];official=sm.get(normalized(vid),'unresolved')
        sessions.append((seq,es,official))
        for e in es:all_cues.append({'video_name':vid,'official_split':official,'native_event':e,'source_annotation_sha256':ANNOTATION_SHA})
    jsonl(ROOT/'ALL_NATIVE_CAPTURE_QUALITY_CUES.jsonl',all_cues);write_json(ROOT/'OFFICIAL_SPLIT_INVENTORY.json',si)
    write_json(ROOT/'NATIVE_PURPOSE_COUNTS.json',dict(purposes))
    print('CC20_HOLO_CENSUS '+json.dumps({'native_sessions':len(native),'quality_cue_sessions':len(sessions),'quality_cues':len(all_cues),'purpose_values':[p for p in purposes if 'video' in p.lower()],'session_splits':dict(collections.Counter(x[2] for x in sessions))}),flush=True)
    assert all_cues,'No native camera-quality events; do not invent them'
    # Round robin by task, deterministic hash rank; outcome pixels not observed.
    buckets=collections.defaultdict(list)
    for entry in sessions:buckets[str(entry[0]['taskType'])].append(entry)
    for b in buckets.values():b.sort(key=lambda x:hashlib.sha256(x[0]['video_name'].encode()).hexdigest())
    selected=[]
    while len(selected)<min(limit,len(sessions)):
        for key in sorted(buckets):
            if buckets[key] and len(selected)<limit:selected.append(buckets[key].pop(0))
    write_json(ROOT/'PREDECLARED_SELECTION.json',{'session_ids':[x[0]['video_name'] for x in selected],'selection':'native-purpose filter; round-robin taskType and SHA256(video_name), before video outcomes','max_sessions':limit,'budget_bytes':2_000_000_000,'historical_human_utility':None})
    tar=RangeTar(BASE+'video_compress.tar');members=tar.scan();write_json(ROOT/'NATIVE_VIDEO_TAR_INDEX.json',{'url':tar.url,'etag':tar.etag,'bytes':tar.total,'members':members})
    lookup=collections.defaultdict(list)
    for m in members:
        for part in Path(m['name']).parts[:-1]:lookup[normalized(part)].append(m)
    records=[];trials=[];totalbytes=0;stats=collections.Counter()
    for seq,events,official in selected:
        vid=seq['video_name'];matches=[m for m in lookup.get(normalized(vid),[]) if m['name'].lower().endswith('.mp4')]
        try:
            if len(matches)!=1:raise ValueError('Exact native session/video member join not unique: '+str(len(matches)))
            m=matches[0]
            if totalbytes+m['size']>2_000_000_000:raise ValueError('Predeclared native-media transfer budget')
            path=ROOT/'native/videos'/(vid+'.mp4');r=tar.extract(m,path);totalbytes+=m['size']
            frames,probe=frames_for_events(path,events,ROOT/'frames'/vid);stats['decoded_native_frames']+=probe['decoded_frames'];stats['accepted_sessions']+=1
            trials.append({'video_name':vid,'status':'accepted','native_media':r,'probe':probe,'official_split':official})
            for event in events:
                eframes=frames.get(str(event['id']),{});prefix=[eframes[k] for k in ['prefix_0','prefix_1','prefix_2'] if k in eframes]
                after=[eframes[k] for k in ['after_0','after_1'] if k in eframes]
                if len(prefix)!=3:stats['events_without_complete_prefix']+=1;continue
                start=float(event['start']);assert all(x['t_seconds']<start for x in prefix)
                attr=event['attributes'];text=attr.get('Transcription');confidence=attr.get('Transcription Confidence')
                known=isinstance(text,str) and bool(text.strip()) and 'unintelligible' not in text.lower()
                record={'record_id':'holoassist:'+vid+':'+str(event['id']),'task_type':'human_capture_quality_cue_imitation','origin_group':'holoassist-session:'+vid,
                  'participant_group':None,'independent_participant_split_proven':False,'split':'development','source_official_split':official,
                  'observations':{'rgb_history':prefix,'selected_subject':None,'intent':None,'protected_style':None,'constraints':None,'cutoff_s':start},
                  'targets':{'native_instruction_text':text,'native_purpose':purpose(event),'transcription_confidence':confidence,'action_proposed':text,'action_performed':None,'goal_achieved':None,'outcome_preferred':None,'comparison_validity':None,'causal_attribution':None,'human_utility':None},
                  'outcome_observations':after,'loss_masks':{'native_instruction_text':known,'action_performed':False,'goal_achieved':False,'outcome_preferred':False,'human_utility':False},
                  'provenance':{'dataset':'HoloAssist','annotation_sha256':ANNOTATION_SHA,'native_event':event,'native_media':str(path.relative_to(ROOT)),'media_sha256':r['sha256'],'intent_origin':'native-human-conversation-purpose; not cinematic intent','label_authority':'native_human_instruction','rights':'CDLA-Permissive-2.0','confounders':['head-mounted camera differs from iPhone','manipulation may move the target','no comparison/control','instruction compliance not independently annotated']}}
                records.append(record);stats['events_with_after_observations']+=bool(after)
        except Exception as e:trials.append({'video_name':vid,'status':'blocked','error':type(e).__name__+': '+str(e)[:250]})
    jsonl(ROOT/'records.jsonl',records);jsonl(ROOT/'SOURCE_TRIALS.jsonl',trials)
    # Actual prefix-only tensor traversal. Target text does not enter observations.
    h=hashlib.sha256();count=0
    for row in records:
        X=np.stack([image_tensor(Image.open(ROOT/f['path'])) for f in row['observations']['rgb_history']])[None]
        assert X.shape==(1,3,3,224,224) and np.isfinite(X).all();h.update(X.tobytes());count+=1
        assert not any(row['loss_masks'][k] for k in ['action_performed','goal_achieved','outcome_preferred','human_utility'])
    summary={'task':'human_capture_quality_cue_imitation','native_annotation_sessions':len(native),'native_quality_cues':len(all_cues),'native_quality_cue_sessions':len(sessions),'selected_sessions':len(selected),
      **dict(stats),'video_backed_prefix_records':len(records),'actual_numpy_batches':count,'tensor_stream_sha256':h.hexdigest(),'native_video_bytes':totalbytes,'tar_members_indexed':len(members),'range_requests':tar.requests,'range_bytes':tar.bytes,
      'native_annotation_sha256':ANNOTATION_SHA,'unknown_execution_and_utility_masked':True,'new_human_responses':0,'model_calls':0,'rights':'CDLA-Permissive-2.0','training_scope':'source-instructor imitation only; NOT independent CameraCoach utility','full_cameracoach_training_ready':False,'participant_overlap_unknown':True}
    (ROOT/'DATASET_CARD_RU.md').write_text('# HoloAssist — реальные команды по качеству видео\n\nСохранены исходная полная разметка, все native cue events, оригинальные опубликованные compressed MP4 выбранных сессий, их позиции в неизменённом TAR, прошлые кадры и отдельные послекадры. Команда и её purpose размечены людьми в первоисточнике. Это не голос новой независимой экспертизы CameraCoach.\n\nНеизвестны: исполнение команды, достижение цели, полезность и художественное предпочтение. Они null и исключены из loss. Нарратив всей сессии и будущая реплика не попадают в online input. Нет выдуманных bbox или выбранного пользователем субъекта.\n\nВсе записи development, пока не установлены связи повторных участников. Официальный split сохранён отдельно. Источник: Wang et al., HoloAssist, ICCV 2023. Данные CDLA-Permissive-2.0, полный текст лицензии сохранён.\n')
    finish(ROOT,'cc20-holoassist-capture-cues',summary)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sessions',type=int,default=24);a=p.parse_args();main(a.sessions)
