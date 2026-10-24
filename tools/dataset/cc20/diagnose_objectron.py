"""Read-only native-frame clock/projection diagnostic. No model calls."""
import json,struct,sys,subprocess
from pathlib import Path
import numpy as np,requests
from real_common import fetch,repository_files,write_json
ROOT=Path('objectron_clock_probe');ROOT.mkdir(exist_ok=True)
REV='46daaa0aca5b2e704bbc8deb99b0863bc9bf19a7'
files=['objectron/schema/annotation_data.proto','objectron/schema/object.proto','objectron/schema/a_r_capture_metadata.proto','notebooks/Parse Annotations.ipynb','notebooks/objectron-geometry-tutorial.ipynb']
repository_files(ROOT,'google-research-datasets/Objectron',REV,files)
for name in files[3:]:
    nb=json.loads((ROOT/'source_repository'/name).read_text());src=[]
    for cell in nb['cells']:
        text=''.join(cell.get('source',[]))
        if any(k in text for k in ['struct.unpack','frame_annotations','CAP_PROP','point_2d','rotation','timestamp']):src.append(text)
    print('CC20_AUTHOR_READER '+json.dumps({'file':name,'cells':src})[:18000])
schema=ROOT/'source_repository/objectron/schema'
subprocess.run([sys.executable,'-m','grpc_tools.protoc','-I'+str(schema),'--python_out='+str(schema),*map(str,schema.glob('*.proto'))],check=True)
sys.path.insert(0,str(schema));import annotation_data_pb2 as A;import a_r_capture_metadata_pb2 as G
for vid in ['bike/batch-4/11']:
    fetch('https://storage.googleapis.com/objectron/annotations/'+vid+'.pbdata',ROOT/'annotation.pbdata')
    fetch('https://storage.googleapis.com/objectron/videos/'+vid+'/geometry.pbdata',ROOT/'geometry.pbdata')
    seq=A.Sequence();seq.ParseFromString((ROOT/'annotation.pbdata').read_bytes());fs=list(seq.frame_annotations)
    data=(ROOT/'geometry.pbdata').read_bytes();p=0;geo=[]
    while p<len(data):
        n=struct.unpack('<I',data[p:p+4])[0];p+=4;assert 0<n<=len(data)-p
        f=G.ARFrame();f.ParseFromString(data[p:p+n]);geo.append(f);p+=n
    result={'video_id':vid,'annotation_frames':len(fs),'frame_ids_first_last':[fs[0].frame_id,fs[-1].frame_id],
       'annotation_timestamp_populated':sum(any(d.name=='timestamp' for d,v in f.ListFields()) for f in fs),
       'native_annotation_timestamp_unique':sorted(set(f.timestamp for f in fs))[:10],
       'geometry_frames':len(geo),'geometry_first_fields':[d.name for d,v in geo[0].ListFields()],
       'geometry_descriptor_fields':list(G.ARFrame.DESCRIPTOR.fields_by_name),
       'annotation_camera_fields':[d.name for d,v in fs[0].camera.ListFields()]}
    if hasattr(geo[0],'timestamp'):result['geometry_times']=[geo[j].timestamp for j in [0,1,len(geo)-1]]
    if len(geo)==len(fs):result['camera_transforms_max_difference']=max(float(np.max(np.abs(np.array(f.camera.transform)-np.array(g.camera.transform)))) for f,g in zip(fs,geo))
    fa=fs[0];cam=fa.camera;P=np.array(cam.projection_matrix).reshape(4,4);K=np.array(cam.intrinsics).reshape(3,3)
    errors={}
    pts=np.array([[k.point_3d.x,k.point_3d.y,k.point_3d.z,1] for obj in fa.annotations for k in obj.keypoints]);xy=np.array([[k.point_2d.x,k.point_2d.y] for obj in fa.annotations for k in obj.keypoints])
    for trans in [False,True]:
        q=pts@(P if trans else P.T);q=q[:,:2]/q[:,3:4];uv=(q+1)/2
        for swap in [False,True]:
            z=uv[:,::-1] if swap else uv
            for flipx in [False,True]:
                for flipy in [False,True]:
                    zz=z.copy()
                    if flipx:zz[:,0]=1-zz[:,0]
                    if flipy:zz[:,1]=1-zz[:,1]
                    errors[f'Ptranspose={trans};swap={swap};fx={flipx};fy={flipy}']=float(np.max(np.abs(zz-xy)))
    result['projection_errors']=dict(sorted(errors.items(),key=lambda x:x[1])[:4])
    print('CC20_OBJECTRON_CLOCK_DIAGNOSTIC '+json.dumps(result),flush=True)
    write_json(ROOT/'aggregate_diagnostic.json',result)
