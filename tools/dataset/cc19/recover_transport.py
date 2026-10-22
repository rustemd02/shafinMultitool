"""Recover completed CameraCoach ciphertext; no decryption key or plaintext data.
Verifies official artifact digests, ZIP CRC, each original part and joined envelope.
No new scenes are generated and no model code is imported.
"""
from __future__ import annotations
import argparse,hashlib,json,os,urllib.request,urllib.parse,zipfile,io
from pathlib import Path
BASE='https://api.github.com/repos/rustemd02/shafinMultitool'
RUNS=[39809877540,39812496682]
class StripAuthRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        out=super().redirect_request(req,fp,code,msg,headers,newurl)
        if out and urllib.parse.urlparse(newurl).hostname!='api.github.com':out.remove_header('Authorization')
        return out
OPENER=urllib.request.build_opener(StripAuthRedirect())
def get(path):
    req=urllib.request.Request(BASE+path,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
    with OPENER.open(req,timeout=180) as r:return r.read()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def main(shard):
    label=f'cc18-final-{shard:02d}';root=Path('bundle');root.mkdir(exist_ok=True)
    selected=None
    for run in RUNS:
        jobs=json.loads(get(f'/actions/runs/{run}/jobs?per_page=100'))['jobs']
        for job in jobs:
            if job['name'] not in [f'complete-corpus ({shard})',f'finish ({shard})'] or job['conclusion']!='success':continue
            text=get(f'/actions/jobs/{job["id"]}/logs').decode('utf-8-sig');qa=None;idx=None
            for line in text.splitlines():
                if ' CC18_FINAL_QA ' in line:qa=json.loads(line.split(' CC18_FINAL_QA ',1)[1])
                if ' CC17_ARTIFACT_INDEX ' in line:idx=json.loads(line.split(' CC17_ARTIFACT_INDEX ',1)[1])
            if qa and idx and idx['label']==label:selected=(run,job,qa,idx)
    assert selected is not None,{'missing_shard':shard}
    run,job,qa,idx=selected;release=idx['release'];receipts=[];joined=root/(label+'.tar.gz.cms')
    with joined.open('wb') as out:
        for a,p in zip(idx['artifacts'],release['parts']):
            data=get(f'/actions/artifacts/{a["id"]}/zip')
            assert len(data)==a['size'] and hashlib.sha256(data).hexdigest()==a['digest'],a['name']
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                assert z.testzip() is None
                names=[n for n in z.namelist() if n.endswith('/'+p['name']) or n==p['name']]
                assert len(names)==1,names
                b=z.read(names[0]);assert len(b)==p['bytes'] and hashlib.sha256(b).hexdigest()==p['sha256'],p['name']
                out.write(b)
            receipts.append({'artifact_id':a['id'],'artifact_sha256':a['digest'],'part':p['name'],'part_sha256':p['sha256'],'bytes':len(b),'crc_checked':True})
    h=hashlib.sha256()
    with joined.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    assert joined.stat().st_size==release['encrypted_bytes'] and h.hexdigest()==release['encrypted_sha256']
    write(root/'RELEASE.json',release);write(root/'BUILD_QA.json',qa);write(root/'ORIGINAL_ARTIFACT_INDEX.json',idx)
    receipt={'label':label,'source_run':run,'source_job':job['id'],'source_parts_verified':receipts,'joined_encrypted_bytes':joined.stat().st_size,'joined_encrypted_sha256':h.hexdigest(),'plaintext_decrypted_in_this_run':False,'drive_readback_in_this_run':False,'build_manifest_file_count':release['payload_files_verified'],'build_payload_bytes':release['payload_bytes'],'build_scene_configurations':qa['stats']['scene_configurations']}
    write(root/'TRANSPORT_VERIFICATION.json',receipt)
    print('CC19_BUNDLE '+json.dumps(receipt),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,required=True);a=p.parse_args();main(a.shard)
