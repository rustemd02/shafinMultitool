#!/usr/bin/env python3
"""Offline action-outcome pilot contracts and blind review.

This is research infrastructure, NOT a new recommendation method. No network calls.
Ratings are never generated here. Fixtures must remain explicitly marked synthetic.
"""
from __future__ import annotations
import argparse, base64, hashlib, html, io, json, math, random, re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any
from PIL import Image, ImageOps

ACTIONS = {'camera_left', 'camera_right'}
DECISIONS = ACTIONS | {'keep', 'abstain'}
REASONS = {'goal_satisfied', 'no_feasible_improvement', 'insufficient_evidence', 'expected_improvement'}
SPLITS = {'development', 'calibration', 'test'}
SCHEMA = 'cameracoach.action-outcome-pilot.v1'


def canonical(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()


def digest(obj: Any) -> str:
    return hashlib.sha256(canonical(obj)).hexdigest()


def read_rows(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


def write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b''.join(canonical(r)+b'\n' for r in rows))


def exact_keys(obj, required, optional=()):
    if not isinstance(obj, dict) or set(obj) - (set(required) | set(optional)) or set(required) - set(obj):
        raise ValueError('Missing or unexpected fields: '+str(set(obj) if isinstance(obj,dict) else type(obj)))


def text(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{name} must be a nonempty string')


def timestamp(value):
    text(value,'timestamp')
    stamp=datetime.fromisoformat(value.replace('Z','+00:00'))
    if stamp.tzinfo is None:
        raise ValueError('Timestamp needs timezone')
    return stamp


def finite(value):
    return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)


def asset_path(asset, root: Path) -> Path:
    exact_keys(asset, {'path','sha256','captured_at'})
    text(asset['path'],'path');timestamp(asset['captured_at'])
    if not isinstance(asset['sha256'],str) or not re.fullmatch('[0-9a-f]{64}',asset['sha256']):
        raise ValueError('Invalid SHA-256')
    rel=Path(asset['path'])
    if rel.is_absolute() or '..' in rel.parts:
        raise ValueError('Asset path escapes media root')
    path=(root/rel).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Asset symlink escapes media root')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=asset['sha256']:
        raise ValueError('Asset SHA-256 mismatch')
    return path


def validate_cases(cases: list[dict], media_root: Path) -> dict[str,dict]:
    if not cases:raise ValueError('No cases')
    byid={};family_split={};sha_split={}
    for c in cases:
        exact_keys(c, {'schema','case_id','family_id','split','synthetic','brief','before','actions','observation_cutoff'})
        if c['schema']!=SCHEMA:raise ValueError('Unknown schema')
        for k in ['case_id','family_id']:text(c[k],k)
        if c['case_id'] in byid:raise ValueError('Duplicate case_id')
        if c['split'] not in SPLITS or not isinstance(c['synthetic'],bool):raise ValueError('Invalid split/synthetic flag')
        if family_split.setdefault(c['family_id'],c['split'])!=c['split']:raise ValueError('Family crosses splits')
        exact_keys(c['brief'],{'text','constraints','locked_at'})
        text(c['brief']['text'],'brief.text')
        if not isinstance(c['brief']['constraints'],list) or not all(isinstance(t,str) and t.strip() for t in c['brief']['constraints']):
            raise ValueError('Constraints must be strings')
        cutoff=timestamp(c['observation_cutoff'])
        if timestamp(c['brief']['locked_at'])>cutoff or timestamp(c['before']['captured_at'])>cutoff:
            raise ValueError('Brief or observation is later than cutoff')
        asset_path(c['before'],media_root)
        if sha_split.setdefault(c['before']['sha256'],c['split'])!=c['split']:raise ValueError('Identical before image crosses splits')
        if not isinstance(c['actions'],list) or len(c['actions'])!=2:raise ValueError('Exactly two defined camera actions required')
        action_ids=[]
        for a in c['actions']:
            exact_keys(a,{'id','dx_m','yaw_deg','description','available'})
            if a['id'] not in ACTIONS or not isinstance(a['available'],bool):raise ValueError('Unknown action or availability')
            if not finite(a['dx_m']) or not finite(a['yaw_deg']):raise ValueError('Nonfinite action')
            if (a['id']=='camera_left' and a['dx_m']>=0) or (a['id']=='camera_right' and a['dx_m']<=0):
                raise ValueError('Action direction disagrees with camera-local dx')
            text(a['description'],'action description');action_ids.append(a['id'])
        if set(action_ids)!=ACTIONS:raise ValueError('Duplicated action')
        byid[c['case_id']]=c
    return byid


def image_data_uri(path: Path) -> str:
    # Decode and re-encode to remove filename/EXIF/model identifiers. Preserve dimensions.
    with Image.open(path) as im:
        rgb=ImageOps.exif_transpose(im).convert('RGB'); b=io.BytesIO();rgb.save(b,format='PNG')
    return 'data:image/png;base64,'+base64.b64encode(b.getvalue()).decode()


def request_packet(case: dict, media_root: Path) -> dict:
    """Explicit whitelist: no after image, ratings, source class or prior answers."""
    img=image_data_uri(asset_path(case['before'],media_root))
    packet={'request_id':digest({'case_id':case['case_id']})[:24],
            'image':img,'brief':case['brief']['text'],'constraints':case['brief']['constraints'],
            'actions':case['actions'], 'allowed_decisions':sorted(DECISIONS),
            'instruction':'Choose one available action, keep, or abstain. Do not infer unseen outcomes as facts. Return decision, reason_code, confidence. Confidence is uncalibrated unless evaluated separately.'}
    packet['input_sha256']=digest(packet)
    return packet


def validate_decision(value: dict, case: dict, expected_request: dict) -> dict:
    exact_keys(value,{'request_id','input_sha256','decision','reason_code','confidence','model_id','prompt_sha256','recorded_at'})
    if value['request_id']!=expected_request['request_id'] or value['input_sha256']!=expected_request['input_sha256']:
        raise ValueError('Prediction is not bound to the frozen request')
    decision=value['decision'];reason=value['reason_code']
    if decision not in DECISIONS or reason not in REASONS:raise ValueError('Unknown decision/reason')
    if not finite(value['confidence']) or not 0<=value['confidence']<=1:raise ValueError('Invalid confidence')
    if decision in ACTIONS and not next(a['available'] for a in case['actions'] if a['id']==decision):raise ValueError('Unavailable action')
    allowed={'keep':{'goal_satisfied','no_feasible_improvement'},'abstain':{'insufficient_evidence'}}
    if reason not in allowed.get(decision,{'expected_improvement'}):raise ValueError('Reason inconsistent with decision')
    text(value['model_id'],'model_id');timestamp(value['recorded_at'])
    if not re.fullmatch('[0-9a-f]{64}',value['prompt_sha256']):raise ValueError('Invalid prompt hash')
    if timestamp(value['recorded_at'])<timestamp(case['observation_cutoff']):raise ValueError('Prediction precedes its observations')
    return value


def prepare_review(cases, outcomes, media_root: Path, seed: int):
    byid=validate_cases(cases,media_root); seen=set();tasks=[];private=[];rng=random.Random(seed)
    for o in outcomes:
        exact_keys(o,{'case_id','action_id','after','physical_capture','protocol_deviation'})
        key=(o['case_id'],o['action_id'])
        if key in seen or key[0] not in byid or key[1] not in ACTIONS:raise ValueError('Duplicate/unknown outcome')
        seen.add(key);c=byid[key[0]]
        if not isinstance(o['physical_capture'],bool) or (not c['synthetic'] and not o['physical_capture']):raise ValueError('Real case requires physical capture')
        if o['protocol_deviation'] is not None and not isinstance(o['protocol_deviation'],str):raise ValueError('Invalid protocol deviation')
        if timestamp(o['after']['captured_at'])<timestamp(c['before']['captured_at']):raise ValueError('After precedes before')
        if not next(a['available'] for a in c['actions'] if a['id']==key[1]):raise ValueError('Outcome for unavailable action')
        after=image_data_uri(asset_path(o['after'],media_root));before=image_data_uri(asset_path(c['before'],media_root))
        after_side=rng.choice(['A','B']);tid=digest({'seed':seed,'case_id':key[0],'action_id':key[1]})[:24]
        tasks.append({'task_id':tid,'brief':c['brief']['text'],'constraints':c['brief']['constraints'],
                      'A':after if after_side=='A' else before,'B':after if after_side=='B' else before})
        private.append({'task_id':tid,'case_id':key[0],'family_id':c['family_id'],'action_id':key[1],
                        'after_side':after_side,'synthetic':c['synthetic'],'protocol_deviation':o['protocol_deviation'],
                        'before_sha256':c['before']['sha256'],'after_sha256':o['after']['sha256'],
                        'brief_sha256':digest(c['brief']),'public_task_sha256':digest(tasks[-1])})
    expected={(c['case_id'],a['id']) for c in cases for a in c['actions'] if a['available']}
    if seen!=expected:raise ValueError('Missing action outcomes')
    rng.shuffle(tasks)
    return tasks, private


def review_html(tasks, fixture: bool=False) -> str:
    # No private mapping or model identities. A/B is randomized independently of recommendation.
    payload=json.dumps(tasks,ensure_ascii=False).replace('<','\\u003c')
    banner='ТЕХНИЧЕСКИЙ ПРИМЕР — НЕ ЧЕЛОВЕЧЕСКИЕ ДАННЫЕ' if fixture else 'Независимая оценка вариантов кадра'
    return '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Оценка кадров</title><style>body{font:17px system-ui;margin:24px;max-width:1200px} .pair{display:flex;gap:16px}figure{margin:0;width:50%}img{max-width:100%;max-height:65vh}button,input{font:inherit;padding:9px;margin:6px}#status{margin:14px 0}</style>
<h1>'''+html.escape(banner)+'''</h1><p>Выберите кадр, который лучше соответствует заданию. Не оценивайте красивый текст совета: он не показан. Допустимы равенство и невозможность оценки.</p>
<label>Идентификатор оценщика: <input id="rater" required></label><div id="status"></div><h2 id="brief"></h2><p id="constraints"></p>
<div class="pair"><figure><figcaption>А</figcaption><img id="a"></figure><figure><figcaption>Б</figcaption><img id="b"></figure></div>
<div id="choices"></div><button id="back">Назад</button><button id="next">Далее</button><button id="export">Сохранить ответы JSONL</button>
<p>Ответы хранятся только в этой вкладке до выгрузки. Убедитесь, что файл сохранён перед закрытием.</p><script>
const tasks='''+payload+''';let pos=0;const answers={};const buttons=[['A','Лучше А'],['B','Лучше Б'],['tie','Равны'],['unjudgeable','Невозможно оценить']];
function show(){const t=tasks[pos];document.getElementById('brief').textContent=t.brief;document.getElementById('constraints').textContent=t.constraints.join('; ');document.getElementById('a').src=t.A;document.getElementById('b').src=t.B;document.getElementById('status').textContent=`${pos+1} / ${tasks.length}; ответ: ${answers[t.task_id]?.choice || 'не выбран'}`;}
for(const [key,label] of buttons){const b=document.createElement('button');b.textContent=label;b.onclick=()=>{answers[tasks[pos].task_id]={choice:key,recorded_at:new Date().toISOString()};show()};document.getElementById('choices').appendChild(b);}
document.getElementById('back').onclick=()=>{pos=Math.max(0,pos-1);show()};document.getElementById('next').onclick=()=>{pos=Math.min(tasks.length-1,pos+1);show()};
document.getElementById('export').onclick=()=>{const r=document.getElementById('rater').value.trim();if(!r){alert('Укажите ID оценщика');return}const rows=Object.entries(answers).map(([task_id,a])=>JSON.stringify({task_id,rater_id:r,...a})).join('\\n')+'\\n';const url=URL.createObjectURL(new Blob([rows],{type:'application/x-ndjson'}));const a=document.createElement('a');a.href=url;a.download='ratings.jsonl';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};if(tasks.length)show();</script></html>'''


def aggregate_ratings(private, votes, roster, minimum_raters=3, allow_fixture=False):
    if isinstance(minimum_raters,bool) or not isinstance(minimum_raters,int) or minimum_raters<2:raise ValueError('At least two independent raters required')
    if not private or not votes:raise ValueError('No tasks or no ratings; cannot claim outcome evaluation')
    taskmap={r['task_id']:r for r in private}
    if len(taskmap)!=len(private):raise ValueError('Duplicate task mapping')
    if any(r['synthetic'] for r in private) and not allow_fixture:raise ValueError('Synthetic fixtures are not real evaluation')
    raters={r['rater_id']:r for r in roster}
    if len(raters)!=len(roster):raise ValueError('Duplicate rater')
    for r in roster:
        exact_keys(r,{'rater_id','kind','independence_attested'})
        if r['kind'] not in ({'human','unit_fixture'} if allow_fixture else {'human'}) or r['independence_attested'] is not True:
            raise ValueError('Rater is not independently attested human')
    seen=set();counts=defaultdict(Counter)
    for v in votes:
        exact_keys(v,{'task_id','rater_id','choice','recorded_at'})
        key=(v['task_id'],v['rater_id']);timestamp(v['recorded_at'])
        if key in seen or key[0] not in taskmap or key[1] not in raters:raise ValueError('Duplicate or unknown rating')
        if v['choice'] not in {'A','B','tie','unjudgeable'}:raise ValueError('Unknown rating choice')
        seen.add(key);m=taskmap[key[0]]
        outcome=v['choice'] if v['choice'] in {'tie','unjudgeable'} else ('beneficial' if v['choice']==m['after_side'] else 'harmful')
        counts[key[0]][outcome]+=1
    rows=[]
    for tid,m in taskmap.items():
        tally=counts[tid];n=sum(tally.values());label='unknown'
        # Strong operational agreement rule; lack of majority stays unknown, never "safe".
        if n>=minimum_raters and m['protocol_deviation'] is None:
            for value in ['beneficial','harmful','tie']:
                if tally[value]>n/2:label=value
        rows.append({**m,'votes':dict(tally),'n_raters':n,'outcome':label})
    return {'synthetic_fixture':any(r['synthetic'] for r in private),'n_tasks':len(rows),
            'raw_votes_retained':True,'rule':'strict majority of ALL submitted votes, min raters; deviations/unjudgeable/no majority => unknown',
            'outcomes':rows,'note':'Attestation is an explicit human declaration, not independently authenticated by software.'}


def evaluate_policy(cases, predictions, judged, media_root):
    byid=validate_cases(cases,media_root)
    if judged.get('synthetic_fixture') or any(c['synthetic'] for c in cases):raise ValueError('Fixture judgments/cases cannot produce empirical policy report')
    outcomes={(r['case_id'],r['action_id']):r for r in judged['outcomes']}
    if len(outcomes)!=len(judged['outcomes']):raise ValueError('Duplicate judged outcome')
    for r in judged['outcomes']:
        if r['case_id'] not in byid or r['action_id'] not in ACTIONS or r['outcome'] not in {'beneficial','harmful','tie','unknown'}:
            raise ValueError('Unknown judged case/action/outcome')
        c=byid[r['case_id']]
        if r['before_sha256']!=c['before']['sha256'] or r['brief_sha256']!=digest(c['brief']) or r['family_id']!=c['family_id']:
            raise ValueError('Judgment is not bound to the case')
    if len({(p['model_id'],p['prompt_sha256']) for p in predictions})>1:raise ValueError('Mixed model/prompt versions in one policy run')
    pp={p['request_id']:p for p in predictions}
    if len(pp)!=len(predictions):raise ValueError('Duplicate prediction')
    required={request_packet(c,media_root)['request_id'] for c in cases}
    if set(pp)!=required:raise ValueError('Missing/extra predictions; do not replace missing runs with abstain')
    rows=[]
    for c in cases:
        packet=request_packet(c,media_root);v=validate_decision(pp[packet['request_id']],c,packet);decision=v['decision']
        available=[a['id'] for a in c['actions'] if a['available']]
        results={a:outcomes.get((c['case_id'],a),{}).get('outcome','unknown') for a in available}
        selected=results.get(decision)
        rows.append({'case_id':c['case_id'],'family_id':c['family_id'],'decision':decision,
                     'outcome':selected,'available_benefit':any(z=='beneficial' for z in results.values()),
                     'all_outcomes_judged':all(z!='unknown' for z in results.values())})
    issued=[r for r in rows if r['decision'] in ACTIONS]; n=len(rows);k=len(issued)
    benefit=sum(r['outcome']=='beneficial' for r in issued); harm=sum(r['outcome']=='harmful' for r in issued)
    unknown=sum(r['outcome'] not in {'beneficial','harmful','tie'} for r in issued)
    return {'n_cases':n,'n_families':len({r['family_id'] for r in rows}),'correction_count':k,'correction_coverage':k/n,
            'keep_count':sum(r['decision']=='keep' for r in rows),'abstain_count':sum(r['decision']=='abstain' for r in rows),
            'benefit_per_case':benefit/n,'harm_per_case':harm/n,'unknown_selected':unknown,
            'harm_fraction_bounds_among_corrections':[harm/k,(harm+unknown)/k] if k else None,
            'benefit_among_corrections':benefit/k if k else None,
            'missed_known_improvements':sum(r['available_benefit'] and r['outcome']!='beneficial' for r in rows),
            'rows':rows,'scope':'Observed brief-relative comparisons only, not a rare-risk certificate or full action ranking.'}


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    a=sub.add_parser('requests');a.add_argument('--cases',type=Path,required=True);a.add_argument('--media-root',type=Path,required=True);a.add_argument('--out',type=Path,required=True)
    a=sub.add_parser('review');a.add_argument('--cases',type=Path,required=True);a.add_argument('--outcomes',type=Path,required=True);a.add_argument('--media-root',type=Path,required=True);a.add_argument('--out',type=Path,required=True);a.add_argument('--private-out',type=Path,required=True);a.add_argument('--seed',type=int,default=20261111)
    a=sub.add_parser('aggregate');a.add_argument('--private',type=Path,required=True);a.add_argument('--votes',type=Path,required=True);a.add_argument('--roster',type=Path,required=True);a.add_argument('--out',type=Path,required=True)
    a=sub.add_parser('evaluate');a.add_argument('--cases',type=Path,required=True);a.add_argument('--predictions',type=Path,required=True);a.add_argument('--judgments',type=Path,required=True);a.add_argument('--media-root',type=Path,required=True);a.add_argument('--out',type=Path,required=True)
    args=p.parse_args()
    if args.out.exists():raise SystemExit('Refusing to overwrite output')
    if args.command=='requests':
        cases=read_rows(args.cases);validate_cases(cases,args.media_root);write_rows(args.out,[request_packet(c,args.media_root) for c in cases])
    elif args.command=='review':
        if args.private_out.exists():raise SystemExit('Refusing to overwrite private mapping')
        cases=read_rows(args.cases);tasks,private=prepare_review(cases,read_rows(args.outcomes),args.media_root,args.seed)
        if args.out.resolve()==args.private_out.resolve():raise SystemExit('Public and private outputs must differ')
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(review_html(tasks,any(c['synthetic'] for c in cases)),encoding='utf-8');write_rows(args.private_out,private)
    elif args.command=='aggregate':
        result=aggregate_ratings(read_rows(args.private),read_rows(args.votes),read_rows(args.roster));args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_bytes(canonical(result)+b'\n')
    else:
        result=evaluate_policy(read_rows(args.cases),read_rows(args.predictions),json.loads(args.judgments.read_text()),args.media_root);args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_bytes(canonical(result)+b'\n')

if __name__=='__main__':main()
