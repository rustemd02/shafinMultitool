"""Small data-only helpers for native CC20 acquisitions."""
from __future__ import annotations
import hashlib,io,json,os,shutil,sys,time,zipfile,tarfile,subprocess
from pathlib import Path,PurePosixPath
import requests,numpy as np
from PIL import Image,ImageOps
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'cc17'))
from acquire import digest,write_json
from release_pack import package
UA={'User-Agent':'CameraCoach-native-supervision/20'}

def fetch(url,path,cap=500_000_000):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    for attempt in range(3):
        temp=path.with_name(path.name+'.partial')
        try:
            with requests.get(url,headers=UA,stream=True,timeout=(20,90)) as r:
                if r.status_code==429:
                    time.sleep(min(120,int(r.headers.get('Retry-After','30'))));continue
                r.raise_for_status();n=0;h=hashlib.sha256()
                if int(r.headers.get('Content-Length',0))>cap:raise ValueError('source byte cap')
                with temp.open('wb') as out:
                    for b in r.iter_content(1024*1024):
                        n+=len(b)
                        if n>cap:raise ValueError('source byte cap')
                        out.write(b);h.update(b)
                receipt={'url':url,'bytes':n,'sha256':h.hexdigest(),'etag':r.headers.get('ETag'),'last_modified':r.headers.get('Last-Modified')}
            temp.replace(path);return receipt
        except Exception as e:
            temp.unlink(missing_ok=True)
            if isinstance(e,requests.HTTPError) and e.response.status_code in [401,403,404]:raise
            if attempt==2:raise
            time.sleep(2**attempt)
    raise RuntimeError('rate-limited acquisition; no bypass')

def pin(repo):
    r=requests.get('https://api.github.com/repos/'+repo,headers=UA,timeout=30);r.raise_for_status();branch=r.json()['default_branch']
    r=requests.get('https://api.github.com/repos/'+repo+'/commits/'+branch,headers=UA,timeout=30);r.raise_for_status();return r.json()['sha']

def repository_files(root,repo,revision,files):
    receipts=[]
    for name in files:
        p=root/'source_repository'/name
        r=fetch('https://raw.githubusercontent.com/'+repo+'/'+revision+'/'+name,p);r['path']=str(p.relative_to(root));receipts.append(r)
    write_json(root/'SOURCE_REPOSITORY.json',{'repo':repo,'revision':revision,'files':receipts})
    return receipts

def jsonl(path,rows):
    with Path(path).open('w') as f:
        for row in rows:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')

def safe_member(name):
    p=PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or '\\' in name:raise ValueError('unsafe archive path')
    return p

def image_tensor(image):
    return np.asarray(ImageOps.exif_transpose(image).convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.

def finish(root,label,summary):
    write_json(root/'QA.json',summary)
    rep=root/'reproduction_cc20';rep.mkdir(exist_ok=True)
    for p in HERE.glob('*.py'):shutil.copyfile(p,rep/p.name)
    (rep/'requirements.txt').write_text('numpy==1.26.4\nPillow==11.3.0\nrequests==2.32.5\nav==14.4.0\ngrpcio-tools==1.68.1\n')
    # Fresh plaintext archive roundtrip is byte-verified by package(). Keys remain private.
    print('CC20_QA '+json.dumps(summary,ensure_ascii=False,allow_nan=False),flush=True)
    return package(root,label)
