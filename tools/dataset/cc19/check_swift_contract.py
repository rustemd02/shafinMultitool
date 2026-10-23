"""Verify the Swift numeric bridge against the actual frozen dataset loader.
Fixtures are deliberately artificial contract tests, never dataset examples.
No Blender, neural framework, model, weights, or private data are used.
"""
from __future__ import annotations
import copy, hashlib, json, random, shutil, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'cc17'))
import cc18_dataset as D

MAIN=r'''
import Foundation
struct Fixture: Codable { let case_id: String; let request: NumericRequest; let expected_failure: Bool }
struct CaseResult: Codable { let case_id: String; let features: NumericFeatures?; let candidateIDs: [String]?; let rejected: Bool }
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
var results: [CaseResult] = []
for f in fixtures {
    do {
        let result = try CameraActionInputsV1.encode(f.request)
        results.append(CaseResult(case_id: f.case_id, features: result.features, candidateIDs: result.candidateIDs, rejected: false))
    } catch {
        results.append(CaseResult(case_id: f.case_id, features: nil, candidateIDs: nil, rejected: true))
    }
}
let encoded = try JSONEncoder().encode(results)
try encoded.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
'''

def actions():
    base={'id':'keep','translation':[0.,0.,0.],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'exposure_ev':0.,'fill_watts':0.,'key_shift_m':[0.,0.,0.],'duration_s':1.,'cost':0.}
    result=[base]
    for j in range(1,31):
        a=copy.deepcopy(base);a.update(id=f'fixture-{j}',translation=[(j%5-2)*.3,0.,0.],pan_deg=float(j-15),focal_factor=1+j/100.,cost=j/10.)
        result.append(a)
    wait=copy.deepcopy(base);wait.update(id='wait_1s',cost=.15);result.append(wait)
    return result

def main():
    out=Path('contract_proof');out.mkdir(exist_ok=True)
    loader=ROOT.parent/'cc17/cc18_dataset.py'
    blob=subprocess.check_output(['git','hash-object',str(loader)],text=True).strip()
    assert blob=='d22b3b50db3e385b17c186a57a67f1c3928d1147','Reference loader changed; inspect before updating parity tests'
    fixtures=[];expected={}
    goals=[{'height_min':.42,'height_max':.85,'visible_min':.65}, {'height_min':.10,'height_max':.23,'visible_min':.65},
           {'height_min':.04,'height_max':.9,'visible_min':.92}, {'height_min':.04,'height_max':.9,'visible_max':.1},
           {'height_min':.04,'height_max':.9,'visible_min':.65,'luminance_min':.3,'luminance_max':.65},
           {'height_min':.04,'height_max':.9,'visible_min':.65,'luminance_min':.015,'luminance_max':.13},None]
    with tempfile.TemporaryDirectory() as td:
        temp=Path(td);images=[]
        for k,c in enumerate([(15,61,87),(92,25,77),(44,103,201)]):
            p=temp/f'fixture{k}.png';Image.new('RGB',(256,192),c).save(p);images.append(p.name)
        for gi,g in enumerate(goals):
            for has_tap in [False,True]:
                rid=f'contract-fixture-{gi}-{has_tap}';a=actions();tap=[.27,.63] if has_tap else None
                equipment=[True,False,True,gi%2==0,gi%3==0]
                constraints=dict(zip(['allow_translation','allow_optical_zoom','allow_exposure','fill_light_available','movable_key_light'],equipment));constraints['focal_bounds_mm']=[17.,85.]
                available=[j%4!=2 for j in range(32)];history=[{'rgb':p,'t_seconds':t} for p,t in zip(images,[-.4,-.2,0.])]
                obs={'history':history,'observation_cutoff_s':0.,'rgb':images[-1],'selected_subject':{'tap_xy':tap},'intent':g,
                     'protected_style':'dark_subject_tone' if gi==5 else None,'constraints':constraints,'current_focal_mm':30.,'action_candidates':a,'candidate_available':available}
                target={'human_utility':None,'action_performed':None,'action_success':[False]*32,'target_action_index':None,'decision':'ask' if g is None and has_tap else 'abstain',
                        'loss_masks':{'action_success':[g is not None]*32,'decision':True,'human_utility':False}}
                row={'record_id':rid,'observations':obs};X,Y,M=D.load_batch(temp,[row],{rid:target})
                order=D.candidate_indices(a);random.Random(int(hashlib.sha256(rid.encode()).hexdigest()[:16],16)).shuffle(order)
                request={'selected_tap_xy':tap,'goal':g,'preserve_dark_tone':gi==5,'equipment_constraints':equipment,
                         'focal_px':30.*256/36,'focal_bounds_px':[17.*256/36,85.*256/36],'upright_width':256,'upright_height':192,
                         'history_time_s':[-.4,-.2,0.],'action_candidates':a,'candidate_available':available,'candidate_order':order}
                fixtures.append({'case_id':rid,'request':request,'expected_failure':False})
                expected[rid]={'features':{k:v[0].tolist() for k,v in X.items() if k!='rgb_history'},'ids':[a[j]['id'] for j in order]}
                mutated=copy.deepcopy(target);mutated['decision']='recommend';mutated['action_success']=[True]*32;mutated['target_action_index']=0
                X2,_,_=D.load_batch(temp,[row],{rid:mutated})
                assert all(np.array_equal(X[k],X2[k]) for k in X),'Targets changed model observations'
        base=copy.deepcopy(fixtures[1]['request'])
        invalid=[]
        for label,key,value in [('future_frame','history_time_s',[-.4,0.,.1]),('reversed_history','history_time_s',[-.2,-.4,0.]),
              ('tap_outside','selected_tap_xy',[1.3,.5]),('unknown_style_as_goal','goal',{'silhouette':1.}),
              ('inverted_goal','goal',{'height_min':.8,'height_max':.2}),('missing_optics','focal_px',0.),
              ('wrong_equipment_shape','equipment_constraints',[True]),('duplicate_permutation','candidate_order',[0]*31)]:
            r=copy.deepcopy(base);r[key]=value;invalid.append({'case_id':label,'request':r,'expected_failure':True})
        r=copy.deepcopy(base);r['action_candidates'][-1]['translation']=[.1,0.,0.];invalid.append({'case_id':'nonredundant_wait','request':r,'expected_failure':True})
        r=copy.deepcopy(base);r['action_candidates'][1]['id']='keep';invalid.append({'case_id':'duplicate_action_ids','request':r,'expected_failure':True})
        r=copy.deepcopy(base);r['action_candidates'][1]['translation']=[.1,.2];invalid.append({'case_id':'bad_action_vector','request':r,'expected_failure':True})
        fixtures+=invalid
        (temp/'main.swift').write_text(MAIN);(temp/'fixtures.json').write_text(json.dumps(fixtures,allow_nan=False))
        exe=temp/'contract-check'
        subprocess.run(['swiftc',str(ROOT/'CameraActionInputsV1.swift'),str(temp/'main.swift'),'-o',str(exe)],check=True)
        subprocess.run([str(exe),str(temp/'fixtures.json'),str(temp/'result.json')],check=True)
        results=json.loads((temp/'result.json').read_text());assert len(results)==len(fixtures)
        for fixture,result in zip(fixtures,results):
            assert result['case_id']==fixture['case_id'] and result['rejected']==fixture['expected_failure'],result['case_id']
            if fixture['expected_failure']:continue
            exp=expected[fixture['case_id']];assert set(result['features'])==set(exp['features'])
            assert result['candidateIDs']==exp['ids']
            for k,v in exp['features'].items():
                actual=np.asarray(result['features'][k]);want=np.asarray(v)
                assert actual.shape==want.shape,(k,actual.shape,want.shape)
                assert np.allclose(actual,want,rtol=1e-6,atol=1e-7),(fixture['case_id'],k)
        report={'schema':'cc19.swift_numeric_parity.v1','valid_fixture_cases':len(expected),'invalid_cases_rejected':len(invalid),
             'target_mutation_invariance_cases':len(expected),'candidate_order_and_output_id_mapping_checked':True,
             'frozen_python_loader_git_blob':blob,'swift_source_sha256':hashlib.sha256((ROOT/'CameraActionInputsV1.swift').read_bytes()).hexdigest(),
             'swift_compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),
             'model_calls':0,'dataset_rows_created':0,'fixture_only':True,
             'image_resize_or_Metal_parity':False,'current_app_integrated':False,
             'scope':'actual Swift implementation of non-image action-ranker inputs, checked against dataset NumPy loader; not an app/model/iPhone run'}
        (out/'CONTRACT_QA.json').write_text(json.dumps(report,indent=2)+'\n')
        shutil.copyfile(ROOT/'CameraActionInputsV1.swift',out/'CameraActionInputsV1.swift')
        shutil.copyfile(__file__,out/'check_swift_contract.py')
        print('CC19_CONTRACT_QA '+json.dumps(report))
if __name__=='__main__':main()
