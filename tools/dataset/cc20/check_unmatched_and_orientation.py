"""Read-only diagnostics for actual unresolved source issues, no model calls."""
import argparse,collections,concurrent.futures as cf,difflib,hashlib,io,json,subprocess,tempfile,shutil
from pathlib import Path
import av,numpy as np
from PIL import Image
import holoassist_real as H
from real_common import fetch,write_json,repository_files
ROOT=Path('cc20-native-diagnostics');ROOT.mkdir(exist_ok=True)

def missing_holo():
    work=Path(tempfile.mkdtemp(prefix='holo-diagnostic-'))
    try:
        fetch(H.BASE+'data-annotation-trainval-v1_1.json',work/'annotations.json',150_000_000)
        data=json.loads((work/'annotations.json').read_text());tar=H.RangeTar(H.BASE+'video_compress.tar');members=tar.scan();lookup=collections.defaultdict(list)
        videos=[m for m in members if m['name'].lower().endswith(('.mp4','.mov','.avi'))]
        for m in videos:
            for part in Path(m['name']).parts[:-1]:lookup[H.normalized(part)].append(m)
        failures=[]
        for seq in data:
            cues=[e for e in seq['events'] if H.relevant(e)]
            if not cues:continue
            name=seq['video_name'];match=lookup.get(H.normalized(name),[])
            if len(match)!=1:
                near=difflib.get_close_matches(H.normalized(name),list(lookup),n=4,cutoff=.7)
                failures.append({'video_name':name,'native_events':len(cues),'exact_candidates':[m['name'] for m in match],
                    'near_candidates':{k:[m['name'] for m in lookup[k]] for k in near},'annotation_batch':seq.get('batch'),'reason':'not exact unique native media join'})
        report={'unmatched_sessions':failures,'native_video_members':len(videos),'automatic_fuzzy_substitution':False}
        write_json(ROOT/'HOLO_UNMATCHED_DIAGNOSTIC.json',report);print('CC20_UNMATCHED_DIAGNOSTIC '+json.dumps(report),flush=True)
    finally:shutil.rmtree(work)

def objectron_orientation():
    rev='46daaa0aca5b2e704bbc8deb99b0863bc9bf19a7';cats=['bike','book','bottle','camera','cereal_box','chair','cup','laptop','shoe'];work=Path(tempfile.mkdtemp(prefix='objectron-orientation-'));out=[]
    try:
        repository_files(work,'google-research-datasets/Objectron',rev,[f'index/{c}_annotations_train' for c in cats])
        def check(cat):
            ids=(work/f'source_repository/index/{cat}_annotations_train').read_text().splitlines();vid=min(set(ids),key=lambda x:hashlib.sha256(x.encode()).hexdigest());p=work/(cat+'.MOV');r=fetch('https://storage.googleapis.com/objectron/videos/'+vid+'/video.MOV',p,300_000_000)
            with av.open(str(p)) as v:
                stream=v.streams.video[0];f=next(v.decode(stream));pixels=f.to_ndarray(format='rgb24');meta=dict(stream.metadata)
            probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height:stream_tags=rotate:stream_side_data','-of','json',str(p)]))
            # Author's reader invokes ffmpeg without -noautorotate. PNG output
            # supplies its actual width/height instead of a guessed reshape.
            b=subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-frames:v','1','-f','image2pipe','-vcodec','png','-threads','1','-'])
            with Image.open(io.BytesIO(b)) as im:reference=np.asarray(im.convert('RGB'))
            comparisons=[]
            for k in range(4):
                candidate=np.rot90(pixels,k)
                if candidate.shape==reference.shape:
                    d=np.abs(candidate.astype(float)-reference.astype(float));comparisons.append({'quarter_turns_ccw':k,'mean_abs_pixel_difference':float(d.mean()),'max_abs_pixel_difference':float(d.max())})
            best=min(comparisons,key=lambda x:x['mean_abs_pixel_difference']);outrow={'video_id':vid,'source_sha256':r['sha256'],'pyav_shape':list(pixels.shape),'author_ffmpeg_shape':list(reference.shape),'stream_metadata':meta,'ffprobe':probe,'rotation_comparison':comparisons,'best_rotation':best,'raw_orientation_matches_author':best['quarter_turns_ccw']==0 and best['mean_abs_pixel_difference']<=1.}
            p.unlink();return outrow
        with cf.ThreadPoolExecutor(max_workers=3) as pool:out=list(pool.map(check,cats))
        report={'source_revision':rev,'videos_checked':len(out),'all_raw_orientation_matches_author':all(x['raw_orientation_matches_author'] for x in out),'details':out,'scope':'one native training video per category, not every frame or device','model_calls':0}
        write_json(ROOT/'OBJECTRON_ORIENTATION_QA.json',report);print('CC20_ORIENTATION_QA '+json.dumps(report),flush=True)
    finally:shutil.rmtree(work)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('task',choices=['holo','orientation']);a=p.parse_args()
    missing_holo() if a.task=='holo' else objectron_orientation()
