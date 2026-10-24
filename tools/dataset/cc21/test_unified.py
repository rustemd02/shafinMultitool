"""Unit fixtures only: not observations or additional dataset examples."""
import copy,hashlib,json,math,tempfile,unittest
from pathlib import Path
import numpy as np
from PIL import Image
import unified_dataset as U

class ContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        histories=[]
        for i,t in enumerate([-.4,-.2,0.]):
            p=self.root/f'prefix_{i}.png';Image.new('RGB',(256,192),(30+i,60,90)).save(p)
            histories.append({'path':p.name,'time_s':t,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
        self.row={'schema':U.SCHEMA,'record_id':'fixture','origin_group':'fixture','split':'train','observations':{'history':histories,'tap_xy':[.3,.4],'goal':[],'goal_known':False,'preserve_dark_tone':False,'optics':[1.,0.,0.],'optics_known':[True,False,False],
          'actions':[{'parameters':[0.,0.,0.,0.,0.,0.,1.,0.,0.,0.,0.,0.,1.,0.,0.],'available':True,'native_index':j} for j in range(11)],'observation_cutoff_s':0.},
          'targets':{'decision':'ask','chosen_index':None,'success':[False]*11,'success_known':[False]*11,'decision_known':True,'human_utility':None},'provenance':{'native_source':'unit_fixture'}}
    def tearDown(self):self.tmp.cleanup()
    def test_shapes(self):
        X,Y,M=U.batch(self.root,[self.row]);self.assertEqual(X['rgb_history'].shape,(1,3,3,224,224));self.assertEqual(X['candidate_params'].shape,(1,31,15))
    def test_padding_masked(self):
        X,Y,M=U.batch(self.root,[self.row]);self.assertEqual(int(X['candidate_present'].sum()),11);self.assertFalse(M['action_success'].any())
    def test_no_human_utility(self):
        self.assertFalse(U.batch(self.root,[self.row])[2]['human_utility'].any())
    def test_false_human_claim_rejected(self):
        r=copy.deepcopy(self.row);r['targets']['human_utility']=True
        with self.assertRaises(ValueError):U.batch(self.root,[r])
    def test_future_time_rejected(self):
        r=copy.deepcopy(self.row);r['observations']['history'][-1]['time_s']=.1
        with self.assertRaises(ValueError):U.batch(self.root,[r])
    def test_unknown_input_rejected(self):
        r=copy.deepcopy(self.row);r['observations']['depth_oracle']=123
        with self.assertRaises(ValueError):U.batch(self.root,[r])
    def test_path_escape_rejected(self):
        with self.assertRaises(ValueError):U.safe(self.root,'../outside')
    def test_unknown_tap_mask(self):
        r=copy.deepcopy(self.row);r['observations']['tap_xy']=None;X,_,_=U.batch(self.root,[r]);self.assertFalse(X['selected_tap_known'][0]);self.assertTrue(np.all(X['selected_tap_xy']==0))
    def test_invalid_tap_rejected(self):
        r=copy.deepcopy(self.row);r['observations']['tap_xy']=[1.2,.3]
        with self.assertRaises(ValueError):U.batch(self.root,[r])
    def test_target_mutation_invariant(self):
        r=copy.deepcopy(self.row);r['targets']['decision']='abstain';r['targets']['success']=[True]*11
        x0=U.batch(self.root,[self.row])[0];x1=U.batch(self.root,[r])[0]
        self.assertTrue(all(np.array_equal(x0[k],x1[k]) for k in x0))
    def test_variable_candidate_sets(self):
        r=copy.deepcopy(self.row);r['record_id']='31';r['observations']['actions']*=3;r['observations']['actions']=r['observations']['actions'][:31];r['targets']['success']=[False]*31;r['targets']['success_known']=[False]*31
        X,Y,M=U.batch(self.root,[self.row,r]);self.assertEqual(X['candidate_present'].sum(axis=1).tolist(),[11,31])
    def test_visibility_metrics_not_equated(self):
        g1=U.goal_constraints({'height_min':.1,'height_max':.8,'visible_min':.75},'v19');g2=U.goal_constraints({'height_min':.1,'height_max':.8,'min_visible':.75,'max_center_shift':.12,'temporal':'all_samples'},'v20')
        self.assertIn('visible_pixel_fraction',{g['metric'] for g in g1});self.assertNotIn('visible_pixel_fraction',{g['metric'] for g in g2});self.assertIn('visible_surface_sample_fraction',{g['metric'] for g in g2})
    def test_temporal_scope_preserved(self):
        goals=U.goal_constraints({'height_min':.1,'height_max':.8,'min_visible':.75,'max_center_shift':.12,'temporal':'all_samples'},'v20');self.assertTrue(all(g['scope']=='all_five_samples' for g in goals))
    def test_missing_goal_empty(self):self.assertEqual(U.goal_constraints(None,'v19'),[])
    def test_rotation_identity(self):self.assertTrue(np.allclose(U.rotation_vector(np.eye(3)),0))
    def test_rotation_orientation(self):
        R=U.axis_rotation([0,0,1],math.pi/4);self.assertTrue(np.allclose(U.rotation_vector(R),[0,0,math.pi/4]))
    def test_v20_rotation_units(self):
        p=U.canonical_action_v20({'dx_m':.4,'yaw_deg':25.,'focal_factor':1.,'cost':1.});self.assertAlmostEqual(p[5],math.radians(25.));self.assertEqual(p[14],1.)
    def test_v19_light_frame_conversion(self):
        t=.25;cam={'right':[1,0,0],'forward':[0,math.cos(t),-math.sin(t)],'up':[0,math.sin(t),math.cos(t)]};a={'translation':[0,0,0],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'exposure_ev':0.,'fill_watts':0.,'key_shift_m':[0,1,0],'duration_s':1.,'cost':0.}
        p=U.canonical_action_v19(a,cam);self.assertTrue(np.allclose(p[9:12],[0,math.cos(t),math.sin(t)]));self.assertEqual(p[14],0.)
    def test_nonfinite_rejected(self):
        r=copy.deepcopy(self.row);r['observations']['actions'][0]['parameters'][0]=float('nan')
        with self.assertRaises(ValueError):U.batch(self.root,[r])
    def test_unknown_goal_bound_mask(self):
        r=copy.deepcopy(self.row);r['observations']['goal_known']=True;r['observations']['goal']=[{'metric':'visible_pixel_fraction','minimum':.7,'maximum':None,'scope':'endpoint'}]
        X,_,_=U.batch(self.root,[r]);m=U.METRICS.index('visible_pixel_fraction');self.assertEqual(X['goal_bounds_known'][0,m].tolist(),[True,False])

if __name__=='__main__':
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests);result=unittest.TextTestRunner(verbosity=2).run(suite)
    report={'tests_run':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'unit_fixtures_only':True,'new_dataset_examples':0,'model_calls':0}
    Path('CC21_UNIT_TESTS.json').write_text(json.dumps(report,indent=2));print('CC21_CONTRACT_TESTS '+json.dumps(report))
    raise SystemExit(0 if result.wasSuccessful() else 1)
