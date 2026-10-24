"""TUM RGB-D measured-camera-motion component, CC BY 4.0.
Downloads only official public sequences. No neural inference or human labels.
Native selected RGB/depth bytes and complete timestamp/pose tables are retained.
"""
from __future__ import annotations
import collections,hashlib,io,json,math,re,shutil,sys,tarfile,urllib.parse
from pathlib import Path
import numpy as np
import requests
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'cc17'))
from acquire import write_json,digest
from release_pack import package
PAGE='https://cvg.cit.tum.de/data/datasets/rgbd-dataset'
SOURCES=[('freiburg1_xyz','train','freiburg1_office'),('freiburg1_rpy','train','freiburg1_office'),('freiburg2_xyz','validation','freiburg2_office'),('freiburg3_sitting_xyz','test','freiburg3_office')]
B=np.array([[1.,0.,0.],[0.,0.,1.],[0.,-1.,0.]])

def request(url):
    r=requests.get(url,timeout=(20,180),headers={'User-Agent':'CameraCoach dataset acquisition/21'});r.raise_for_status();return r

def table(text,numeric=False):
    rows=[line.split() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    return np.asarray(rows,float) if numeric else [(float(r[0]),r[1]) for r in rows]
def qmatrix(q):
    q=np.asarray(q,float);q=q/np.linalg.norm(q);x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
def slerp(a,b,u):
    a=a/np.linalg.norm(a);b=b/np.linalg.norm(b);dot=float(a@b)
    if dot<0:b=-b;dot=-dot
    if dot>.9995:q=a+u*(b-a);return q/np.linalg.norm(q)
    theta=math.acos(np.clip(dot,-1,1));return (math.sin((1-u)*theta)*a+math.sin(u*theta)*b)/math.sin(theta)
def pose_at(gt,t):
    k=int(np.searchsorted(gt[:,0],t))
    if k==0 or k==len(gt):return None
    a,b=gt[k-1],gt[k];gap=b[0]-a[0]
    if gap<=0 or gap>.03:return None
    u=(t-a[0])/gap;T=np.eye(4);T[:3,3]=(1-u)*a[1:4]+u*b[1:4];T[:3,:3]=qmatrix(slerp(a[4:],b[4:],u));return T,[float(a[0]),float(b[0])]
def rotvec(R):
    angle=math.acos(float(np.clip((np.trace(R)-1)/2,-1,1)))
    if angle<1e-9:return np.zeros(3)
    if abs(math.sin(angle))<1e-7:return None
    return angle/(2*math.sin(angle))*np.array([R[2,1]-R[1,2],R[0,2]-R[2,0],R[1,0]-R[0,1]])
def motion(T0,T1):
    relative=np.linalg.inv(T0)@T1;R=B@relative[:3,:3]@B.T;t=B@relative[:3,3];r=rotvec(R)
    if r is None:return None
    assert np.allclose(R.T@R,np.eye(3),atol=1e-6) and np.linalg.det(R)>.999
    return t.tolist()+r.tolist()
def emit(path,rows):
    with path.open('w') as f:
        for row in rows:f.write(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n')

def batches(root,split='train',batch_size=16):
    root=Path(root)
    if split not in ['train','validation','test']:raise ValueError('Invalid split')
    rows=[json.loads(l) for l in (root/'motion_records.jsonl').read_text().splitlines() if json.loads(l)['split']==split]
    for off in range(0,len(rows),batch_size):
        block=rows[off:off+batch_size];images=[];dt=[];targets=[]
        for row in block:
            obs=row['observations'];rgb=[]
            assert set(obs)=={'before_rgb','after_rgb','delta_time_s'}
            for rel in [obs['before_rgb'],obs['after_rgb']]:
                p=(root/rel).resolve();assert p.is_relative_to(root.resolve())
                with Image.open(p) as im:rgb.append(np.asarray(im.convert('RGB').resize((224,224),Image.Resampling.BILINEAR),np.float32).transpose(2,0,1)/255.)
            images.append(np.stack(rgb));dt.append(obs['delta_time_s']);targets.append(row['targets']['measured_camera_motion'])
            assert row['targets']['human_intent'] is None and row['targets']['operator_utility'] is None
        X={'rgb_pair':np.stack(images),'delta_time_s':np.asarray(dt,np.float32)};Y={'measured_camera_motion':np.asarray(targets,np.float32)};M={'measured_camera_motion':np.ones((len(block),6),bool),'human_utility':np.zeros(len(block),bool)}
        assert X['rgb_pair'].shape[1:]==(2,3,224,224)
        for d in [X,Y,M]:
            for a in d.values():assert np.isfinite(a).all()
        yield X,Y,M

def run():
    root=Path('cc21-real-motion');root.mkdir(exist_ok=False);evidence=root/'source_evidence';evidence.mkdir();html=request(PAGE+'/download').text
    for name,url in [('license.html',PAGE),('download.html',PAGE+'/download'),('formats.html',PAGE+'/file_formats')]:
        data=html if name=='download.html' else request(url).text;(evidence/name).write_text(data)
    assert 'CC BY 4.0' in (evidence/'license.html').read_text(),'Dataset license text not confirmed'
    links=[urllib.parse.urljoin(PAGE+'/download',x.replace('&amp;','&')) for x in re.findall(r'href=[\"\']([^\"\']+)[\"\']',html)]
    records=[];receipts=[];frame_manifest=[];summary=[];quarantine=[]
    # Rotation/translation convention regression, not fabricated dataset examples.
    T0=np.eye(4);T1=np.eye(4);T1[:3,3]=[1,2,3];assert np.allclose(motion(T0,T1)[:3],[1,3,-2]);assert np.allclose(motion(T0,T0),np.zeros(6))
    for name,split,group in SOURCES:
        matches=sorted(set(u for u in links if u.endswith('rgbd_dataset_'+name+'.tgz')))
        if len(matches)!=1:raise ValueError('Official download link not uniquely resolved: '+name)
        url=matches[0];archive=Path(name+'.tgz');h=hashlib.sha256();size=0
        with requests.get(url,stream=True,timeout=(20,180)) as response:
            response.raise_for_status();headers={k:response.headers.get(k) for k in ['ETag','Last-Modified','Content-Length']}
            with archive.open('wb') as f:
                for b in response.iter_content(1024*1024):f.write(b);h.update(b);size+=len(b)
        if headers['Content-Length']:assert size==int(headers['Content-Length'])
        source=root/'native'/name;source.mkdir(parents=True)
        with tarfile.open(archive,'r:gz') as z:
            byname={m.name:m for m in z.getmembers() if m.isfile()}
            def text_file(base):
                names=[n for n in byname if n.endswith('/'+base)];assert len(names)==1
                b=z.extractfile(byname[names[0]]).read();(source/base).write_bytes(b);return b.decode()
            rgb=table(text_file('rgb.txt'));depth=table(text_file('depth.txt'));gt=table(text_file('groundtruth.txt'),True)
            assert gt.shape[1]==8 and np.isfinite(gt).all() and np.all(np.diff(gt[:,0])>0)
            depths=np.array([r[0] for r in depth]);chosen=np.linspace(0,len(rgb)-1,min(160,len(rgb)),dtype=int);aligned=[]
            prefix=next(iter(byname)).split('/')[0]
            for k in chosen:
                stamp,path=rgb[k];pose=pose_at(gt,stamp)
                if pose is None:quarantine.append({'source':name,'frame':path,'reason':'pose bracketing gap or outside GT'});continue
                di=int(np.argmin(np.abs(depths-stamp)))
                if abs(depths[di]-stamp)>.02:quarantine.append({'source':name,'frame':path,'reason':'RGB-depth timestamp difference >20ms'});continue
                files={}
                for kind,relative in [('rgb',path),('depth',depth[di][1])]:
                    member=prefix+'/'+relative
                    if member not in byname:raise ValueError('Native timestamp/media mismatch')
                    data=z.extractfile(byname[member]).read();dest=source/relative;dest.parent.mkdir(exist_ok=True);dest.write_bytes(data)
                    with Image.open(io.BytesIO(data)) as im:
                        im.load();assert im.size==(640,480)
                        if kind=='depth':a=np.asarray(im);assert np.issubdtype(a.dtype,np.integer) and a.max()<=65535
                    relative_out=str(dest.relative_to(root));files[kind]=relative_out;frame_manifest.append({'path':relative_out,'native_member':member,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'source_sequence':name,'kind':kind})
                aligned.append({'rgb_timestamp':stamp,'depth_timestamp':float(depths[di]),'files':files,'T_world_camera':pose[0].tolist(),'gt_bracket':pose[1]})
            emit(source/'ALIGNED_SELECTED_FRAMES.jsonl',aligned)
            before_n=len(records)
            for j,a in enumerate(aligned):
                for step in [1,2]:
                    if j+step>=len(aligned):continue
                    b=aligned[j+step];dt=b['rgb_timestamp']-a['rgb_timestamp']
                    if dt<=0 or dt>2.:continue
                    delta=motion(np.asarray(a['T_world_camera']),np.asarray(b['T_world_camera']))
                    if delta is None:continue
                    records.append({'record_id':f'tum:{name}:{j:04d}:{j+step:04d}','origin_group':group,'sequence':name,'split':split,'task_type':'observed_camera_motion_verifier',
                      'observations':{'before_rgb':a['files']['rgb'],'after_rgb':b['files']['rgb'],'delta_time_s':dt},
                      'targets':{'measured_camera_motion':delta,'human_intent':None,'advice_action_performed':None,'goal_achieved':None,'operator_utility':None},
                      'provenance':{'authority':'native optical motion-capture trajectory; linear position + quaternion SLERP to RGB timestamps','frame':'initial camera right_forward_up','translation_units':'m','rotation_units':'rad_axis_angle','gt_timestamps':[a['gt_bracket'],b['gt_bracket']],'license':'CC-BY-4.0','rights_source':PAGE,'not_counterfactual_policy':True,'not_iPhone':True}})
            summary.append({'sequence':name,'split':split,'origin_group':group,'native_rgb_frames':len(rgb),'native_depth_frames':len(depth),'native_gt_poses':len(gt),'selected_aligned_frames':len(aligned),'motion_pairs':len(records)-before_n,'native_duration_s':rgb[-1][0]-rgb[0][0]})
        receipts.append({'sequence':name,'url':url,'archive_bytes':size,'archive_sha256':h.hexdigest(),'headers':headers,'retained':'unaltered selected PNG bytes and complete native timestamp/pose tables; entire original archive not included'})
        print('CC21_REAL_SEQUENCE '+json.dumps(summary[-1]),flush=True)
    emit(root/'motion_records.jsonl',records);emit(root/'SELECTED_MEDIA_MANIFEST.jsonl',frame_manifest);write_json(root/'SOURCE_RECEIPTS.json',receipts);write_json(root/'QUARANTINE.json',quarantine)
    groups=collections.defaultdict(set);pixels=collections.defaultdict(set)
    for r in records:groups[r['split']].add(r['origin_group'])
    assert all(not groups[a]&groups[b] for a,b in [('train','validation'),('train','test'),('validation','test')])
    for item in frame_manifest:
        assert digest(root/item['path'])==item['sha256']
        with Image.open(root/item['path']) as im:im.load()
    streams={};bn=0
    for split in ['train','validation','test']:
        h=hashlib.sha256();n=0;bcount=0
        for X,Y,M in batches(root,split):
            bcount+=1;n+=len(X['delta_time_s'])
            for d in [X,Y,M]:
                for k,v in sorted(d.items()):h.update(k.encode());h.update(str(v.shape).encode());h.update(v.tobytes())
        streams[split]={'rows':n,'batches':bcount,'tensor_sha256':h.hexdigest()};bn+=bcount
    report={'source_sequences':summary,'motion_records':len(records),'source_sessions':len(SOURCES),'conservative_environment_groups':len(set(g for _,_,g in SOURCES)),'native_selected_pngs':len(frame_manifest),'quarantined_rgb_frames':len(quarantine),'actual_batches':bn,'split_streams':streams,'cross_split_environment_overlap':0,'model_calls':0,'new_human_utility_labels':0,'license':'CC-BY-4.0 as stated by source','full_CameraCoach_training_ready':False,'scope':'real observed motion and RGB-D supervision; not operator advice usefulness'}
    write_json(root/'QA.json',report);shutil.copyfile(__file__,root/'tum_motion.py')
    (root/'ATTRIBUTION.md').write_text('# Attribution\nJ. Sturm, N. Engelhard, F. Endres, W. Burgard, D. Cremers. A Benchmark for the Evaluation of RGB-D SLAM Systems. IROS 2012.\nSource: '+PAGE+'\nLicense: Creative Commons Attribution 4.0, https://creativecommons.org/licenses/by/4.0/\nChanges: temporal subset selection, SLERP interpolation, relative transforms, data-only 224x224 RGB batch preprocessing. Native selected PNG/txt bytes preserved.\n')
    (root/'README_RU.md').write_text('# Реальные измеренные движения камеры\nЧетыре опубликованные последовательности TUM RGB-D. Вход verifier — два реальных RGB и dt; target — перемещение и поворот камеры по motion capture. Depth — native supervision, не выдуманная моделью глубина.\n\nНе содержит человеческих намерений, советов CameraCoach и оценок их полезности. Послекадр разрешён только задаче verifier; нельзя подключать этот loader как causal policy. Три группы окружений: весь fr1 train, весь fr2 validation, весь fr3 test. Это не оценка переноса на iPhone.\n')
    print('CC21_REAL_MOTION_QA '+json.dumps(report),flush=True);package(root,'cc21-real-motion')
if __name__=='__main__':run()
