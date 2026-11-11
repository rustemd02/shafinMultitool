"""Manufactured unit fixtures only. Never expert opinions or empirical scene outcomes."""
import copy, hashlib, json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from PIL import Image
import pytest
import pilot as p

@pytest.fixture
def example(tmp_path):
    def asset(name,level,t):
        path=tmp_path/name;Image.new('RGB',(8,8),(level,level,level)).save(path)
        return {'path':name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'captured_at':t}
    before=asset('before.png',100,'2026-11-11T10:00:00Z')
    left=asset('after_left.png',90,'2026-11-11T10:00:01Z');right=asset('after_right.png',110,'2026-11-11T10:00:02Z')
    c={'schema':p.SCHEMA,'case_id':'fixture-001','family_id':'family1','split':'development','synthetic':True,
       'brief':{'text':'UNIT TEST: retain the selected object','constraints':['Do not move subject'],'locked_at':'2026-11-11T09:59:00Z'},
       'before':before,'observation_cutoff':'2026-11-11T10:00:00Z',
       'actions':[{'id':'camera_left','dx_m':-.2,'yaw_deg':0.,'description':'Translate left without rotation','available':True},
                  {'id':'camera_right','dx_m':.2,'yaw_deg':0.,'description':'Translate right without rotation','available':True}]}
    outcomes=[{'case_id':c['case_id'],'action_id':a,'after':im,'physical_capture':False,'protocol_deviation':None} for a,im in [('camera_left',left),('camera_right',right)]]
    return c,outcomes,tmp_path


def make_prediction(c,root,decision='camera_left'):
    q=p.request_packet(c,root)
    return {'request_id':q['request_id'],'input_sha256':q['input_sha256'],'decision':decision,
            'reason_code':{'keep':'goal_satisfied','abstain':'insufficient_evidence'}.get(decision,'expected_improvement'),
            'confidence':.8,'model_id':'unit-fixture-not-model','prompt_sha256':'a'*64,'recorded_at':'2026-11-11T10:01:00Z'}


def make_votes(private,choice='after'):
    roster=[{'rater_id':str(i),'kind':'unit_fixture','independence_attested':True} for i in range(3)]
    votes=[{'task_id':t['task_id'],'rater_id':str(i),'choice':t['after_side'] if choice=='after' else choice,
            'recorded_at':'2026-11-11T10:10:00Z'} for t in private for i in range(3)]
    return votes,roster


def test_valid_request_hides_future(example):
    c,o,root=example;p.validate_cases([c],root);q=p.request_packet(c,root)
    assert 'after' not in json.dumps(q) and 'before.png' not in json.dumps(q)
    assert not {'family_id','split','synthetic','source_bucket'}&set(q)
    assert q['input_sha256']==p.digest({k:v for k,v in q.items() if k!='input_sha256'})

@pytest.mark.parametrize('mutate', ['extra','duplicate','split','samebytes_split','future','nan_action','bad_direction','bad_hash','escape'])
def test_case_validation_fails_closed(example,mutate):
    c,o,root=example;cases=[c]
    if mutate=='extra':c['outcome']='beneficial'
    elif mutate=='duplicate':cases.append(copy.deepcopy(c))
    elif mutate in {'split','samebytes_split'}:
        other=copy.deepcopy(c);other['case_id']='second';other['split']='test'
        if mutate=='samebytes_split':other['family_id']='family2'
        cases.append(other)
    elif mutate=='future':c['brief']['locked_at']='2026-11-12T00:00:00Z'
    elif mutate=='nan_action':c['actions'][0]['dx_m']=float('nan')
    elif mutate=='bad_direction':c['actions'][0]['dx_m']=.2
    elif mutate=='bad_hash':c['before']['sha256']='0'*64
    else:c['before']['path']='../outside.png'
    with pytest.raises(ValueError):p.validate_cases(cases,root)

@pytest.mark.parametrize('change',['unknown','confidence','reason','input','unavailable','past'])
def test_prediction_rejected(example,change):
    c,o,root=example;v=make_prediction(c,root)
    if change=='unknown':v['decision']='zoom'
    elif change=='confidence':v['confidence']=float('nan')
    elif change=='reason':v['reason_code']='goal_satisfied'
    elif change=='input':v['input_sha256']='b'*64
    elif change=='unavailable':c['actions'][0]['available']=False;v=make_prediction(c,root)
    else:v['recorded_at']='2026-11-10T00:00:00Z'
    with pytest.raises(ValueError):p.validate_decision(v,c,p.request_packet(c,root))


def test_blind_packet_no_mapping(example):
    c,o,root=example;tasks,private=p.prepare_review([c],o,root,42);page=p.review_html(tasks,True)
    assert 'after_side' not in page and 'camera_left' not in page and 'fixture-001' not in page
    assert 'ТЕХНИЧЕСКИЙ ПРИМЕР' in page
    assert p.prepare_review([c],o,root,42)==(tasks,private)


def test_missing_outcome_rejected(example):
    c,o,root=example
    with pytest.raises(ValueError):p.prepare_review([c],o[:1],root,42)


def test_duplicate_outcome_rejected(example):
    c,o,root=example
    with pytest.raises(ValueError):p.prepare_review([c],o+[o[0]],root,42)


def test_aggregate_all_votes_and_fixture_guard(example):
    c,o,root=example;tasks,private=p.prepare_review([c],o,root,42);votes,roster=make_votes(private)
    with pytest.raises(ValueError):p.aggregate_ratings(private,votes,roster)
    r=p.aggregate_ratings(private,votes,roster,allow_fixture=True)
    assert r['synthetic_fixture'] and all(z['outcome']=='beneficial' and z['n_raters']==3 for z in r['outcomes'])

@pytest.mark.parametrize('case',['no_votes','duplicate','unknown_rater','insufficient','unjudgeable','protocol_deviation'])
def test_rating_edge_cases(example,case):
    c,o,root=example;_,private=p.prepare_review([c],o,root,42);votes,roster=make_votes(private)
    if case=='no_votes':votes=[]
    elif case=='duplicate':votes.append(votes[0])
    elif case=='unknown_rater':votes[0]['rater_id']='not-present'
    elif case=='insufficient':votes=[v for v in votes if v['rater_id']!='2']
    elif case=='unjudgeable':votes,roster=make_votes(private,'unjudgeable')
    else:
        for t in private:t['protocol_deviation']='Subject moved'
    if case in ['no_votes','duplicate','unknown_rater']:
        with pytest.raises(ValueError):p.aggregate_ratings(private,votes,roster,allow_fixture=True)
    else:
        r=p.aggregate_ratings(private,votes,roster,allow_fixture=True)
        assert all(z['outcome']=='unknown' for z in r['outcomes'])


def test_synthetic_policy_cannot_be_reported_real(example):
    c,o,root=example;_,private=p.prepare_review([c],o,root,42);v,roster=make_votes(private);judged=p.aggregate_ratings(private,v,roster,allow_fixture=True)
    with pytest.raises(ValueError):p.evaluate_policy([c],[make_prediction(c,root)],judged,root)

@pytest.mark.parametrize('decision',['camera_left','keep','abstain'])
def test_policy_arithmetic_on_manufactured_fixture(example,decision):
    # Pure arithmetic test: this local simulation is never exported as a study result.
    c,o,root=example;c['synthetic']=False
    for outcome in o:outcome['physical_capture']=True
    _,private=p.prepare_review([c],o,root,42);votes,roster=make_votes(private)
    for r in roster:r['kind']='human'
    judged=p.aggregate_ratings(private,votes,roster);res=p.evaluate_policy([c],[make_prediction(c,root,decision)],judged,root)
    if decision=='camera_left':assert res['benefit_per_case']==1 and res['correction_coverage']==1
    else:assert res['correction_coverage']==0 and res['harm_fraction_bounds_among_corrections'] is None and res['missed_known_improvements']==1


def test_missing_prediction_not_abstain(example):
    c,o,root=example;c['synthetic']=False
    with pytest.raises(ValueError):p.evaluate_policy([c],[],{'synthetic_fixture':False,'outcomes':[]},root)

def test_machine_schema_agrees_with_valid_fixture(example):
    from jsonschema import Draft202012Validator, FormatChecker
    c,o,root=example
    schema=json.loads((Path(__file__).resolve().parents[1]/'protocol/case.schema.json').read_text())
    validator=Draft202012Validator(schema,format_checker=FormatChecker());validator.validate(c)
    c['future_result']='leaked'
    with pytest.raises(Exception):validator.validate(c)
