"""CC20 data-only source preflight. Original source bytes stay encrypted.
No model imports, no fabricated historical goals, no participant recruitment.
"""
from __future__ import annotations
import concurrent.futures as cf, collections, hashlib, json, re, sys, traceback
from pathlib import Path
from urllib.parse import urljoin, urlparse
import requests
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'cc17'))
from acquire import download,digest,write_json
from release_pack import package
ROOT=Path('cc20-source-preflight');ROOT.mkdir(exist_ok=True)

def get(url,path,cap=160_000_000):
    p=ROOT/path;p.parent.mkdir(parents=True,exist_ok=True)
    with requests.get(url,stream=True,timeout=(20,90)) as r:
        r.raise_for_status();n=0
        if int(r.headers.get('Content-Length',0))>cap:raise ValueError('preflight byte cap')
        with p.open('wb') as f:
            for b in r.iter_content(1024*1024):
                n+=len(b)
                if n>cap:raise ValueError('preflight byte cap')
                f.write(b)
    return p

def repo(owner):
    d=requests.get('https://api.github.com/repos/'+owner,timeout=30);d.raise_for_status();branch=d.json()['default_branch']
    r=requests.get('https://api.github.com/repos/'+owner+'/commits/'+branch,timeout=30);r.raise_for_status()
    rev=r.json()['sha'];return 'https://raw.githubusercontent.com/'+owner+'/'+rev+'/',rev

def shape(value,depth=0):
    if depth>2:return type(value).__name__
    if isinstance(value,dict):return {k:shape(v,depth+1) for k,v in list(value.items())[:20]}
    if isinstance(value,list):return {'length':len(value),'first':shape(value[0],depth+1) if value else None}
    return type(value).__name__

def objectron():
    base,rev=repo('google-research-datasets/Objectron');out={'revision':rev}
    for name in ['LICENSE','README.md','objectron/schema/annotation_data.proto','objectron/schema/object.proto','objectron/schema/a_r_capture_metadata.proto','notebooks/Parse Annotation Data.ipynb']:
        try:get(base+name,'objectron/repository/'+name)
        except Exception as e:out.setdefault('optional_errors',[]).append({'file':name,'error':str(e)[:180]})
    index=get(base+'index/cup_annotations_train','objectron/cup_annotations_train').read_text().splitlines()
    vid=next(x for x in index if x.strip());out['sample_id']=vid
    for name,url in [('annotation.pbdata','https://storage.googleapis.com/objectron/annotations/'+vid+'.pbdata'),('geometry.pbdata','https://storage.googleapis.com/objectron/videos/'+vid+'/geometry.pbdata'),('video.MOV','https://storage.googleapis.com/objectron/videos/'+vid+'/video.MOV')]:
        p=get(url,'objectron/sample/'+name);out[name]={'bytes':p.stat().st_size,'sha256':digest(p)}
    import subprocess
    out['video_probe']=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=index,codec_type,width,height,nb_frames,duration:format=duration','-of','json',str(ROOT/'objectron/sample/video.MOV')]))
    schema=ROOT/'objectron/repository/objectron/schema'
    subprocess.run([sys.executable,'-m','grpc_tools.protoc','-I'+str(schema),'--python_out='+str(schema),*map(str,schema.glob('*.proto'))],check=True)
    sys.path.insert(0,str(schema));import annotation_data_pb2 as A
    s=A.Sequence();s.ParseFromString((ROOT/'objectron/sample/annotation.pbdata').read_bytes())
    out['sequence_frames']=len(s.frame_annotations);out['objects']=len(s.objects)
    f=s.frame_annotations[0];out['first_frame']={'frame_id':f.frame_id,'timestamp':f.timestamp,'annotation_count':len(f.annotations),'camera_fields':[x.name for x,v in f.camera.ListFields()],'keypoint_counts':[len(x.keypoints) for x in f.annotations],'resolution':[f.camera.image_resolution_width,f.camera.image_resolution_height]}
    return out

def illumination():
    base,rev=repo('lmurmann/multi_illumination');out={'revision':rev}
    for name in ['multilum.py','scenes.json','README.md','LICENSE']:
        try:get(base+name,'illumination/'+name)
        except Exception as e:out.setdefault('errors',[]).append({'file':name,'error':str(e)[:150]})
    page=get('https://projects.csail.mit.edu/illumination/','illumination/project.html')
    scenes=json.loads((ROOT/'illumination/scenes.json').read_text());out.update(scenes=len(scenes),first_scenes=scenes[:2],buildings=dict(collections.Counter(x['building'] for x in scenes)),room_types=dict(collections.Counter(x['room_type'] for x in scenes)))
    code=(ROOT/'illumination/multilum.py').read_text();out['download_code']=code[code.find('def download_scene'):code.find('def download_scene')+3000]
    out['url_code']=[line.strip() for line in code.splitlines() if any(s in line for s in ['.zip','BASE_URL','materials_','mip%d','mip{'])][-30:]
    out['page_links']=re.findall(r'href=[\"\']([^\"\']+)',page.read_text())
    return out

def holoassist():
    base='https://holoassist.github.io/';page=get(base,'holoassist/project.html').read_text()
    links=[(urljoin(base,u),re.sub('<[^>]+>','',t).strip()) for u,t in re.findall(r'<a[^>]*href=[\"\']([^\"\']+)[\"\'][^>]*>(.*?)</a>',page,re.S)]
    chosen=[(u,t) for u,t in links if any(x in t.lower() for x in ['label','split','readme','compressed video','head pose'])]
    out={'source_links':chosen,'files':[]}
    for i,(url,title) in enumerate(chosen):
        try:
            p=get(url,'holoassist/link_'+str(i)+Path(urlparse(url).path).suffix)
            info={'url':url,'title':title,'bytes':p.stat().st_size,'sha256':digest(p)}
            if p.suffix=='.json':value=json.loads(p.read_text());info['shape']=shape(value)
            elif p.stat().st_size<1_000_000:
                text=p.read_text();urls=re.findall(r'https?://[^\s<>\"\)]+',text)
                info['linked_urls_count']=len(urls);info['first_urls']=urls[:3]
                if 'label' in title.lower():
                    for j,child in enumerate(urls[:8]):
                        q=get(child,'holoassist/labels/'+str(j)+'_'+Path(urlparse(child).path).name)
                        info.setdefault('labels',[]).append({'name':q.name,'bytes':q.stat().st_size})
                        try:
                            value=json.loads(q.read_text());info['labels'][-1]['shape']=shape(value)
                            if isinstance(value,dict):info['labels'][-1]['top_keys']=list(value)[:30]
                        except (ValueError,UnicodeError):pass
            out['files'].append(info)
        except Exception as e:out['files'].append({'url':url,'error':str(e)[:250]})
    return out

if __name__=='__main__':
    results={}
    with cf.ThreadPoolExecutor(max_workers=3) as pool:
        jobs={pool.submit(fn):name for name,fn in [('objectron',objectron),('illumination',illumination),('holoassist',holoassist)]}
        for f in cf.as_completed(jobs):
            name=jobs[f]
            try:results[name]=f.result()
            except Exception as e:results[name]={'error':str(e),'trace':traceback.format_exc()[-1800:]}
            print('CC20_SOURCE_PROBE '+json.dumps({name:results[name]},ensure_ascii=False),flush=True)
    write_json(ROOT/'SOURCE_PROBE.json',results)
    repro=ROOT/'reproduction_cc20';repro.mkdir(exist_ok=True)
    import shutil
    shutil.copyfile(__file__,repro/Path(__file__).name)
    package(ROOT,'cc20-source-preflight')
