#!/usr/bin/env python3
"""Run diagnostic experiments on immutable, already exposed CameraCoach data.

No new VLM calls, human annotations, or action-outcome observations are fabricated.
The old quality classifier is diagnostic only and is not an intent model.
"""
from __future__ import annotations
import argparse, collections, hashlib, importlib.util, json, os, platform, sys
from pathlib import Path
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold, StratifiedGroupKFold, StratifiedShuffleSplit, GroupShuffleSplit
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from metrics import classification_metrics, expected_calibration_error, empirical_risk_coverage, action_metrics

CLASSES = ['good', 'mixed', 'bad']
LABEL_PATH = 'shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl'
PILOT_PATH = 'ml/camera_coach/intent_pilot'

def read_jsonl(path):
    return [json.loads(l) for l in Path(path).read_text(encoding='utf-8').splitlines() if l.strip()]

def write(path, obj):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8')

def write_jsonl(path, rows):
    Path(path).write_text(''.join(json.dumps(r, ensure_ascii=False, allow_nan=False)+'\n' for r in rows), encoding='utf-8')

class UnionFind:
    def __init__(self, ids): self.p={x:x for x in ids}
    def find(self,x):
        if self.p[x]!=x:self.p[x]=self.find(self.p[x])
        return self.p[x]
    def join(self,a,b):
        a,b=self.find(a),self.find(b)
        if a!=b:self.p[max(a,b)]=min(a,b)

def families(labels):
    byid={r['record_id']:r for r in labels}; uf=UnionFind(byid); seen={}; links=[]
    for r in labels:
        rid=r['record_id'];parent=r.get('parent_record_id')
        if parent in byid:
            uf.join(rid,parent);links.append({'a':rid,'b':parent,'reason':'explicit_parent'})
        tokens=[f"sha:{r['sha256']}"] if r.get('sha256') else []
        tokens += [f'title:{t}' for t in r.get('eval_tags',[]) if t.startswith('parent_source_')]
        for token in tokens:
            if token in seen:
                uf.join(rid,seen[token]);links.append({'a':rid,'b':seen[token],'reason':token.split(':')[0]})
            else:seen[token]=rid
    groups={rid:uf.find(rid) for rid in byid}
    return groups,links

def coarse_origin(label):
    s=label['source_bucket']
    return {'official_promo_cinematic_preservation':'apple_tv',
            'synthetic_bad_paired_apple_tv_press':'apple_tv',
            'public_iqa_bad_tail':'live_challenge', 'imagegen_bad_candidate':'imagegen',
            'curated_user_inbox':'curated_inbox'}.get(s,s)

def source_pred(train, test, key, y, labels):
    counter=collections.defaultdict(collections.Counter)
    for i in train:
        z=coarse_origin(labels[i]) if key=='origin' else labels[i]['source_bucket']
        counter[z][y[i]]+=1
    fallback=collections.Counter(y[train]).most_common(1)[0][0]
    pred=[]
    for i in test:
        z=coarse_origin(labels[i]) if key=='origin' else labels[i]['source_bucket']
        pred.append(counter[z].most_common(1)[0][0] if counter[z] else fallback)
    return np.array(pred)

def audit_and_classify(store: Path, out: Path):
    labels=read_jsonl(store/LABEL_PATH)
    rows=read_jsonl(store/PILOT_PATH/'dataset/intent-dataset-train.jsonl')+read_jsonl(store/PILOT_PATH/'dataset/intent-dataset-test.jsonl')
    byid={r['record_id']:r for r in labels}
    assert len(byid)==len(labels)==len(rows)==174
    assert set(byid)=={r['record_id'] for r in rows}
    aligned=[byid[r['record_id']] for r in rows]
    assert all(r['label']==l['quality_label'] for r,l in zip(rows,aligned))
    groupmap,links=families(labels)
    groups=np.array([groupmap[r['record_id']] for r in rows])
    split={r['record_id']:r['split'] for r in rows}
    crossed=[dict(l,a_split=split[l['a']],b_split=split[l['b']]) for l in links if split[l['a']]!=split[l['b']]]
    source_counts=collections.defaultdict(collections.Counter)
    for r in labels:source_counts[r['source_bucket']][r['quality_label']]+=1
    group_splits=collections.defaultdict(set)
    for r in rows:group_splits[groupmap[r['record_id']]].add(r['split'])
    audit={
       'rows':len(rows),'label_counts':dict(collections.Counter(r['label'] for r in rows)),
       'source_counts':dict(source_counts),'review_status_counts':dict(collections.Counter(r.get('review_status','missing') for r in labels)),
       'label_source_counts':dict(collections.Counter(r.get('label_source','missing') for r in labels)),
       'human_gold_in_pilot':sum(r.get('provenance',{}).get('human_gold') is True for r in rows),
       'labels_missing_image_sha256':[r['record_id'] for r in labels if not r.get('sha256')],
       'explicit_parent_edges':sum(l['reason']=='explicit_parent' for l in links),
       'known_family_groups':len(set(groups)), 'cross_split_links':crossed,
       'overlapping_known_families':sum(len(v)>1 for v in group_splits.values()),
       'contradictory_action_labels':[r['record_id'] for r in labels if set(r['expected_semantic_actions'])&set(r['forbidden_actions'])],
       'limitations':['This metadata audit is complemented by media_audit.json, which decodes and hashes the actual 174 tracked images when the supplement is available.',
                      'Family closure uses available parent links, exact hashes and title tags; other shared shoots may be unknown.',
                      'source_bucket is a curator-defined sampling stratum and may encode target selection; source-only accuracy is a confounding control, not a deployable competitor.',
                      'These are good/mixed/bad labels, not author-intent or real intervention-outcome labels.']}
    write(out/'data_audit.json',audit)
    write_jsonl(out/'family_assignments.jsonl',[{'record_id':r['record_id'],'family_id':groupmap[r['record_id']],'historical_split':r['split']} for r in rows])
    names=sorted(rows[0]['provenance']['feature_names'])
    assert all(sorted(r['features'])==names for r in rows)
    X=np.array([[r['features'][n] for n in names] for r in rows],float)
    y=np.array([r['label'] for r in rows]); ids=[r['record_id'] for r in rows]
    assert np.isfinite(X).all()
    tr=np.array([i for i,r in enumerate(rows) if r['split']=='train']);te=np.array([i for i,r in enumerate(rows) if r['split']=='test'])
    subsets={'all_27':list(range(len(names))), 'aesthetic_only':[names.index('aesthetic_score')],
       'without_critic':[i for i,n in enumerate(names) if not n.startswith(('severity_','sem_')) and n!='verdict_confidence']}
    def predict(name,tr,te):
        if name=='majority':return np.full(len(te),collections.Counter(y[tr]).most_common(1)[0][0]),None
        if name in ['source_stratum_only','source_origin_only']:
            return source_pred(tr,te,'origin' if name=='source_origin_only' else 'stratum',y,aligned),None
        inds=subsets[name]
        model=make_pipeline(StandardScaler(),LogisticRegression(C=1.0,max_iter=2000,solver='lbfgs',random_state=20261111))
        model.fit(X[tr][:,inds],y[tr])
        return model.predict(X[te][:,inds]),model.predict_proba(X[te][:,inds]).max(axis=1)
    modelnames=['majority','source_origin_only','source_stratum_only','aesthetic_only','without_critic','all_27']
    output=[];details=[]
    for name in modelnames:
        pred,confidence=predict(name,tr,te);m=classification_metrics(y[te],pred,CLASSES)
        m.update({'method':name,'protocol':'historical_122_52','known_family_overlap':len(set(groups[tr])&set(groups[te]))})
        if confidence is not None:m['confidence_diagnostic']=expected_calibration_error(confidence,(pred==y[te]).astype(int))
        output.append(m)
        details.extend({'protocol':'historical_122_52','method':name,'record_id':ids[i],'true':str(y[i]),'pred':str(p),
                        'confidence':float(confidence[k]) if confidence is not None else None} for k,(i,p) in enumerate(zip(te,pred)))
    # Exact historical function with both explicitly documented and default learning rates.
    spec=importlib.util.spec_from_file_location('legacy_pilot',store/PILOT_PATH/'train_intent_pilot.py')
    legacy=importlib.util.module_from_spec(spec);spec.loader.exec_module(legacy)
    yn=np.array([CLASSES.index(v) for v in y]); mu=X[tr].mean(axis=0);sd=X[tr].std(axis=0)+1e-9
    for lr in [.05,.5]:
        W,b=legacy.fit((X[tr]-mu)/sd,yn[tr],1.,800,lr)
        pr=legacy.softmax((X[te]-mu)/sd@W+b);pred=np.array(CLASSES)[pr.argmax(axis=1)]
        m=classification_metrics(y[te],pred,CLASSES);m.update(method=f'legacy_softmax_lr_{lr}',protocol='historical_122_52',hyperparameters={'lam':1,'iters':800,'lr':lr})
        output.append(m)
        details.extend({'protocol':'historical_122_52','method':m['method'],'record_id':ids[i],'true':str(y[i]),'pred':str(p),'confidence':float(pr[k].max())} for k,(i,p) in enumerate(zip(te,pred)))
    # Fixed 20 resplits; compare distributions descriptively, not as independent replications.
    resplits=[];split_manifest=[];resplit_predictions=[]
    for seed in range(20):
        for protocol,splitter in [('stratified',StratifiedShuffleSplit(n_splits=1,test_size=.3,random_state=seed)),
                                  ('known_family_grouped',GroupShuffleSplit(n_splits=1,test_size=.3,random_state=seed))]:
            train,test=next(splitter.split(X,y,groups) if protocol=='known_family_grouped' else splitter.split(X,y))
            overlap=len(set(groups[train])&set(groups[test]))
            if protocol=='known_family_grouped':assert overlap==0
            split_manifest.append({'protocol':protocol,'seed':seed,'train_ids':[ids[i] for i in train],'test_ids':[ids[i] for i in test]})
            for name in modelnames:
                pred,_=predict(name,train,test)
                m=classification_metrics(y[test],pred,CLASSES)
                m.update(protocol=protocol,seed=seed,method=name,train_n=len(train),family_overlap=overlap)
                resplits.append(m)
                resplit_predictions.extend({'protocol':protocol,'seed':seed,'method':name,'record_id':ids[i], 'true':str(y[i]),'pred':str(pr)} for i,pr in zip(test,pred))
    write_jsonl(out/'classification_resplit_predictions.jsonl',resplit_predictions)
    summaries=[]
    for protocol in ['stratified','known_family_grouped']:
        for name in modelnames:
            rr=[r for r in resplits if r['protocol']==protocol and r['method']==name]
            z={'protocol':protocol,'method':name,'repeats':len(rr)}
            for key in ['accuracy','balanced_accuracy','macro_f1']:
                v=np.array([r[key] for r in rr]);z[key]={'mean':float(v.mean()),'std_across_splits':float(v.std(ddof=1)),'min':float(v.min()),'max':float(v.max())}
            summaries.append(z)
    write(out/'classification_fixed_split.json',output)
    write_jsonl(out/'classification_predictions.jsonl',details)
    write(out/'classification_resplits.json',resplits)
    write(out/'classification_resplit_summary.json',summaries)
    write(out/'split_manifest.json',split_manifest)
    write(out/'feature_definition.json',{'names':names,'subsets':{k:[names[i] for i in v] for k,v in subsets.items()},
         'excluded_from_predictors':['curated_problems','curated_technical_defects','target','quality_label','record_id','expected_actions'],
         'interpretation':'All legacy features come from old runtime diagnostics. Source-only controls intentionally use sampling metadata.'})
    return audit,output


def visible_action_sets(record_ids, outputs):
    visible={rid:set() for rid in record_ids}
    for row in outputs:
        if row['record_id'] not in visible:
            raise ValueError('Unknown record in visibility projection')
        if row['shown']:
            visible[row['record_id']].update(row['semantic_actions'])
    return [visible[rid] for rid in record_ids]


def replay_and_controls(store:Path,out:Path):
    evalpath=store/'docs/cameraanalysis/eval'; sys.path.insert(0,str(evalpath))
    import semantic_output_schema as ss
    import semantic_label_adapter as sa
    records=sa.load_semantic_label_records(store/LABEL_PATH,images_dir=None)
    cases=sa.normalize_semantic_label_cases(records)
    original=read_jsonl(evalpath/'out_semantic_real_runtime_v2_regen_bad_v1/candidate_outputs.jsonl')
    outputs=[r.get('output',r) for r in original]
    report=ss.score_semantic_candidate_outputs(cases,outputs)
    archived=json.loads((evalpath/'out_semantic_real_runtime_v2_regen_bad_v1/set_metrics.json').read_text())['set_metrics']
    write(out/'historical_replay.json',{'computed':report['set_metrics'],'archived':archived,'exact_equal':report['set_metrics']==archived,
          'scope':'Rescore saved historical outputs, not rerun Swift/iPhone inference.'})
    write_jsonl(out/'historical_replay_cases.jsonl',report['case_results'])
    merged=ss._map_outputs(cases,outputs)
    expected=[set(c['expected_actions']) for c in cases];forbidden=[set(c['forbidden_actions']) for c in cases]
    catalog=sorted(ss.SEMANTIC_ACTION_TYPES)
    controls={}
    def evaluate(name,outs):
        try:
            legacy=ss.score_semantic_candidate_outputs(cases,outs)['set_metrics']
        except Exception as e:
            return {'validation_rejected':True,'error':str(e)[:500]}
        mm=ss._map_outputs(cases,outs)
        visible=visible_action_sets([c['record_id'] for c in cases],outs)
        stored=[set(mm[c['record_id']]['semantic_actions']) for c in cases]
        observed=[True for _ in cases]
        return {'legacy':legacy,'strict_visible':action_metrics(expected,forbidden,visible,observed),
                'strict_stored':action_metrics(expected,forbidden,stored,observed)}
    controls['historical_merged']=evaluate('historical_merged',outputs)
    controls['missing_all_outputs']=evaluate('missing_all_outputs',[])
    base=ss.build_oracle_candidate_outputs(cases)
    # No label text/target is kept in controls; all fields relevant to scores are fixed.
    rng=np.random.default_rng(20261111)
    for name in ['empty_response','always_keep','all_actions','random_one_action','always_change_camera_angle']:
        o=[]
        for row in base:
            r=dict(row); r.update(confidence=.8,future_actions=[],live_tip=None,pause_summary=None,trace_ids=[],source='diagnostic_negative_control')
            if name=='empty_response':r.update(semantic_actions=[],shown=False)
            elif name=='always_keep':r.update(semantic_actions=['keep_current_setup'],shown=True)
            elif name=='all_actions':r.update(semantic_actions=catalog,shown=True)
            elif name=='random_one_action':r.update(semantic_actions=[str(rng.choice(catalog))],shown=True)
            else:r.update(semantic_actions=['change_camera_angle'],shown=True)
            o.append(r)
        controls[name]=evaluate(name,o)
    for mode in ['live','pause']:
        controls[f'historical_{mode}_only']=evaluate(mode,[o for o in outputs if o['mode']==mode])
    # Explicit diagnostic hidden-output check: shown=False but retain all stored action IDs.
    hidden=[dict(o,shown=False) for o in outputs]
    controls['historical_force_hidden']=evaluate('hidden',hidden)
    controls['duplicate_output']=evaluate('duplicate',outputs+[outputs[0]])
    bad=[dict(o) for o in outputs];bad[0]=dict(bad[0],semantic_actions=['unknown_action'])
    controls['unknown_action']=evaluate('unknown',bad)
    write(out/'scorer_controls.json',controls)
    # Later stored runs are rescored separately; they are not new runtime execution.
    lanes=[]
    for lane in ['drift-174','drift-174-calibrated-edge-neutral','drift-174-technical-override']:
        folder=evalpath/'camera-baseline-v0'/lane
        stored=[r.get('output',r) for r in read_jsonl(folder/'scored/candidate_outputs.jsonl')]
        calculated=ss.score_semantic_candidate_outputs(cases,stored)['set_metrics']
        old=json.loads((folder/'scored/set_metrics.json').read_text())['set_metrics']
        manifest=json.loads((folder/'manifest.json').read_text())
        lanes.append({'lane':lane,'captured_at':manifest.get('captured_at'),'scope':manifest.get('claim_scope'),
                      'recomputed':calculated,'archived':old,'exact_equal':calculated==old,
                      'control_metrics':evaluate(lane,stored)})
    write(out/'later_stored_replays.json',lanes)
    conf=np.array([merged[c['record_id']]['confidence'] for c in cases])
    success=np.array([int(r['passed']) for r in report['case_results']])
    hit=np.array([int(r['metrics']['expected_action_hit']) for r in report['case_results']])
    semantic_ok=np.array([int(not [f for f in r['failures'] if f!='confidence_band_mismatch']) for r in report['case_results']])
    cov={'semantic_acceptance_without_confidence_band':empirical_risk_coverage(conf,semantic_ok),
         'target':'compatibility with historical labels, not empirical action utility',
         'confidence_is_not_documented_probability_of_this_event':True,
         'ece_vs_all_criteria':expected_calibration_error(conf,success),
         'ece_vs_action_hit':expected_calibration_error(conf,hit),
         'risk_coverage_all_criteria':empirical_risk_coverage(conf,success),
         'risk_coverage_action_hit':empirical_risk_coverage(conf,hit)}
    write(out/'confidence_diagnostics.json',cov)
    return report['set_metrics'],controls


def main():
    p=argparse.ArgumentParser();p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    audit,cls=audit_and_classify(a.snapshot/'store',a.out)
    replay,controls=replay_and_controls(a.snapshot/'store',a.out)
    print(json.dumps({'audit':{k:audit[k] for k in ['rows','label_counts','known_family_groups','overlapping_known_families']},
                      'fixed_split':[{k:r[k] for k in ['method','accuracy','balanced_accuracy','macro_f1']} for r in cls],
                      'replay':replay,'controls':{k:v.get('legacy',v) for k,v in controls.items()}},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
