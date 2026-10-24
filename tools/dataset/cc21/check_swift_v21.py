"""Actual Swift compilation and numeric parity, using unit fixtures only.
No model framework, weights, app process, camera, or private media is loaded.
"""
import copy,hashlib,json,random,shutil,subprocess,tempfile
from pathlib import Path
import numpy as np
from PIL import Image
import unified_dataset as U
HERE=Path(__file__).resolve().parent
MAIN='''import Foundation
struct Fixture: Codable { let id: String; let request: CC21Request; let expected_rejection: Bool }
struct Result: Codable { let id: String; let rejected: Bool; let encoded: CC21Encoded? }
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let cases = try JSONDecoder().decode([Fixture].self, from: input)
var results: [Result] = []
for f in cases {
 do { let value = try CameraActionInputsV21.encode(f.request); results.append(Result(id:f.id, rejected:false, encoded:value)) }
 catch { results.append(Result(id:f.id, rejected:true, encoded:nil)) }
}
try JSONEncoder().encode(results).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
'''

def run():
    proof=Path('cc21-swift-proof');proof.mkdir(exist_ok=True);cases=[];expected={}
    with tempfile.TemporaryDirectory() as td:
        root=Path(td);history=[]
        for j,t in enumerate([-.4,-.2,0.]):
            p=root/f'prefix_{j}.png';Image.new('RGB',(256,192),(30+j,60,90)).save(p)
            history.append({'path':p.name,'time_s':t,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
        for source,n in [('v19',31),('v20',11)]:
            if source=='v19':goals=[None,{'height_min':.1,'height_max':.25,'visible_min':.7},{'height_min':.35,'height_max':.8,'visible_max':.1},{'height_min':.04,'height_max':.9,'visible_min':.7,'luminance_min':.015,'luminance_max':.13}]
            else:goals=[None,{'height_min':.05,'height_max':.8,'min_visible':.75,'max_center_shift':.12,'temporal':'all_samples'},{'height_min':.05,'height_max':.8,'max_visible':.12,'max_center_shift':1.,'temporal':'endpoint'}]
            for gi,g in enumerate(goals):
                for tap in [None,[.27,.63]]:
                    rid=f'fixture:{source}:{gi}:{tap is not None}';acts=[]
                    for j in range(n):
                        params=[(j%5-2)*.2,0.,0.,0.,0.,j/50.,1.+j/100.,0.,0.,0.,0.,0.,1.,j/10.,float(source=='v20')]
                        acts.append({'parameters':params,'available':j%4!=2,'native_index':j})
                    o={'history':history,'tap_xy':tap,'goal':U.goal_constraints(g,source),'goal_known':g is not None,'preserve_dark_tone':source=='v19' and gi==3,'optics':[34/36.,17/36.,85/36.] if source=='v19' else [34/36.,0.,0.],'optics_known':[True,True,True] if source=='v19' else [True,False,False],'actions':acts,'observation_cutoff_s':0.}
                    target={'decision':'ask' if g is None else 'abstain','chosen_index':None,'success':[False]*n,'success_known':[bool(g)]*n,'decision_known':True,'human_utility':None}
                    row={'schema':U.SCHEMA,'record_id':rid,'observations':o,'targets':target};X,_,_=U.batch(root,[row])
                    order=list(range(n));random.Random(int(hashlib.sha256(rid.encode()).hexdigest()[:16],16)).shuffle(order)
                    cases.append({'id':rid,'request':{'observations':o,'candidate_order':order},'expected_rejection':False})
                    expected[rid]={'features':{k:v[0].tolist() for k,v in X.items() if k!='rgb_history'},'indices':[acts[j]['native_index'] for j in order]+[None]*(31-n)}
        base=copy.deepcopy(cases[1]['request'])
        def invalid(name,mutate):
            x=copy.deepcopy(base);mutate(x);cases.append({'id':name,'request':x,'expected_rejection':True})
        invalid('future',lambda x:x['observations']['history'][-1].update(time_s=.1))
        invalid('tap',lambda x:x['observations'].update(tap_xy=[1.1,.5]))
        invalid('duplicate_permutation',lambda x:x.update(candidate_order=[0]*len(x['candidate_order'])))
        invalid('bad_action_shape',lambda x:x['observations']['actions'][0].update(parameters=[0.]*14))
        invalid('negative_focal',lambda x:x['observations']['actions'][0]['parameters'].__setitem__(6,-1.))
        invalid('unknown_motion_profile',lambda x:x['observations']['actions'][0]['parameters'].__setitem__(14,7.))
        invalid('duplicate_action_identity',lambda x:x['observations']['actions'][1].update(native_index=0))
        invalid('unknown_metric',lambda x:x['observations'].update(goal_known=True,goal=[{'metric':'fake_metric','minimum':.2,'maximum':None,'scope':'endpoint'}]))
        invalid('unknown_scope',lambda x:x['observations'].update(goal_known=True,goal=[{'metric':'visible_pixel_fraction','minimum':.2,'maximum':None,'scope':'continuous_unmeasured'}]))
        invalid('inverted_goal',lambda x:x['observations'].update(goal_known=True,goal=[{'metric':'visible_pixel_fraction','minimum':.8,'maximum':.2,'scope':'endpoint'}]))
        (root/'fixtures.json').write_text(json.dumps(cases,allow_nan=False));(root/'main.swift').write_text(MAIN)
        subprocess.run(['swiftc',str(HERE/'CameraActionInputsV21.swift'),str(root/'main.swift'),'-o',str(root/'check')],check=True)
        subprocess.run([str(root/'check'),str(root/'fixtures.json'),str(root/'result.json')],check=True)
        results=json.loads((root/'result.json').read_text());assert len(results)==len(cases)
        for c,r in zip(cases,results):
            assert c['id']==r['id'] and c['expected_rejection']==r['rejected'],c['id']
            if c['expected_rejection']:continue
            wanted=expected[c['id']];value=r['encoded'];assert value['output_native_indices']==wanted['indices'];assert set(value['features'])==set(wanted['features'])
            for k,v in wanted['features'].items():
                actual=np.asarray(value['features'][k]);ref=np.asarray(v);assert actual.shape==ref.shape,(c['id'],k,actual.shape,ref.shape)
                assert np.allclose(actual,ref,atol=1e-7,rtol=1e-6),(c['id'],k)
        report={'valid_fixture_cases':len(expected),'invalid_cases_rejected':len(cases)-len(expected),'candidate_output_identity_and_padding_verified':True,'typed_visibility_metric_and_time_scope_parity':True,
          'python_source_sha256':hashlib.sha256((HERE/'unified_dataset.py').read_bytes()).hexdigest(),'swift_source_sha256':hashlib.sha256((HERE/'CameraActionInputsV21.swift').read_bytes()).hexdigest(),
          'compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'fixture_only':True,'new_dataset_rows':0,'model_calls':0,'iPhone_image_preprocessing_parity':False,'current_app_integration':False}
        (proof/'SWIFT_PARITY_QA.json').write_text(json.dumps(report,indent=2));shutil.copyfile(HERE/'CameraActionInputsV21.swift',proof/'CameraActionInputsV21.swift');shutil.copyfile(__file__,proof/'check_swift_v21.py')
        print('CC21_SWIFT_PARITY '+json.dumps(report),flush=True)
if __name__=='__main__':run()
