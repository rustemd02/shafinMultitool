#!/usr/bin/env python3
"""Additional source-held-out and actual-media checks, not a new coaching benchmark."""
import argparse, collections, hashlib, json
from pathlib import Path
from PIL import Image, ImageOps
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from run_experiment import read_jsonl, write, write_jsonl, CLASSES, LABEL_PATH, PILOT_PATH, coarse_origin
from metrics import classification_metrics


def media_check(store, out):
    labels=read_jsonl(store/LABEL_PATH); base=store/Path(LABEL_PATH).parent
    files=[]; errors=[]; pixels=collections.defaultdict(list); bytes_seen=collections.defaultdict(list)
    for r in labels:
        path=base/r['image_path']; data=path.read_bytes(); sha=hashlib.sha256(data).hexdigest()
        with Image.open(path) as im:
            original_size=im.size; rgb=ImageOps.exif_transpose(im).convert('RGB')
            pixel_sha=hashlib.sha256(str(rgb.size).encode()+b'\0'+rgb.tobytes()).hexdigest()
        if r.get('sha256') and sha!=r['sha256']:errors.append({'id':r['record_id'],'error':'label_byte_hash_mismatch'})
        if 'width' in r and 'height' in r and original_size!=(r['width'],r['height']):errors.append({'id':r['record_id'],'error':'label_dimension_mismatch','actual':original_size,'label':[r['width'],r['height']]})
        row={'record_id':r['record_id'],'bytes':len(data),'sha256_observed':sha,'sha256_label':r.get('sha256'),
             'pixel_sha256':pixel_sha,'width':original_size[0],'height':original_size[1]}
        files.append(row);pixels[pixel_sha].append(r['record_id']);bytes_seen[sha].append(r['record_id'])
    report={'images_decoded':len(files),'hashes_matching_supplied_labels':sum(r['sha256_label']==r['sha256_observed'] for r in files),
            'missing_label_hashes_now_measured_not_written_back':sum(not r['sha256_label'] for r in files),
            'errors':errors,'exact_byte_duplicate_groups':[v for v in bytes_seen.values() if len(v)>1],
            'exact_oriented_rgb_duplicate_groups':[v for v in pixels.values() if len(v)>1],
            'near_duplicate_search':'not performed; nonidentical frames from one shoot may remain dependent',
            'scope':'Decode and hash only; no human judgment or new VLM inference.'}
    write(out/'media_audit.json',report);write_jsonl(out/'media_observed_manifest.jsonl',files)
    return report


def leave_origin_out(store,out):
    labels={r['record_id']:r for r in read_jsonl(store/LABEL_PATH)}
    rows=read_jsonl(store/PILOT_PATH/'dataset/intent-dataset-train.jsonl')+read_jsonl(store/PILOT_PATH/'dataset/intent-dataset-test.jsonl')
    names=sorted(rows[0]['features']); X=np.array([[r['features'][n] for n in names] for r in rows],float)
    y=np.array([r['label'] for r in rows]); origins=np.array([coarse_origin(labels[r['record_id']]) for r in rows])
    subsets={'all_27':list(range(len(names))),'aesthetic_only':[names.index('aesthetic_score')],
             'without_critic':[i for i,n in enumerate(names) if not n.startswith(('severity_','sem_')) and n!='verdict_confidence']}
    reports=[];predictions=[]
    for origin in sorted(set(origins)):
        tr=np.where(origins!=origin)[0];te=np.where(origins==origin)[0]
        # Synthetic derivatives and their Apple source originals are deliberately one origin.
        for method in ['majority',*subsets]:
            if method=='majority':pred=np.full(len(te),collections.Counter(y[tr]).most_common(1)[0][0])
            else:
                cols=subsets[method]; model=make_pipeline(StandardScaler(),LogisticRegression(C=1.,max_iter=2000,solver='lbfgs',random_state=20261111))
                model.fit(X[tr][:,cols],y[tr]);pred=model.predict(X[te][:,cols])
            result=classification_metrics(y[te],pred,CLASSES);result.update(method=method,held_origin=str(origin),train_n=len(tr),test_n=len(te))
            reports.append(result)
            predictions.extend({'held_origin':str(origin),'method':method,'record_id':rows[i]['record_id'],'true':str(y[i]),'pred':str(p)} for i,p in zip(te,pred))
    write(out/'leave_origin_out.json',{'scope':'Exploratory source-domain shift on exposed labels; not a deployment estimate or paired causal leakage estimate','runs':reports})
    write_jsonl(out/'leave_origin_out_predictions.jsonl',predictions)
    return [{k:r[k] for k in ['held_origin','method','n','accuracy','macro_f1']} for r in reports]

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();a.out.mkdir(exist_ok=True,parents=True)
    print(json.dumps({'media':media_check(a.snapshot/'store',a.out),'origin_holdout':leave_origin_out(a.snapshot/'store',a.out)},indent=2))
