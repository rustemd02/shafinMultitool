"""End-to-end regression fixtures. These are NOT acquired dataset observations."""
import argparse,copy,hashlib,json,shutil,tempfile,unittest
from pathlib import Path
from PIL import Image
import calibration_index as C
import merge_sources as M
import unified_dataset as U
INDEX=None

class CompactPipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.base=Path(self.tmp.name);self.v19=self.base/'v19';self.v20=self.base/'v20'
        self.a=self.v19/'compact';self.b=self.v20/'mesh';self.a.mkdir(parents=True);self.b.mkdir(parents=True)
        h19=[];h20=[]
        for root,history,version,color in [(self.a,h19,'v19',30),(self.b,h20,'v20',90)]:
            for i,t in enumerate([-.4,-.2,0.]):
                p=root/f'prefix_{i}.png';Image.new('RGB',(8,6),(color+i,40,60)).save(p);sha=hashlib.sha256(p.read_bytes()).hexdigest()
                history.append({'rgb':p.name,'t_seconds':t,'sha256':sha} if version=='v19' else {'path':p.name,'t_s':t,'sha256':sha})
        sid=next(iter(INDEX['records']));entry=INDEX['records'][sid]
        actions=[{'id':'keep' if i==0 else f'fixture_{i}','translation':[i*.01,0.,0.],'pan_deg':0.,'tilt_deg':0.,'focal_factor':1.,'exposure_ev':0.,'fill_watts':0.,'key_shift_m':[0.,0.,0.],'duration_s':1.,'cost':float(i)} for i in range(31)]
        wait=copy.deepcopy(actions[0]);wait['id']='wait_1s';wait['cost']=.15;actions.append(wait)
        row19={'record_id':'fixture19','schema':'cameracoach.component.v18.2','origin_group':entry['origin_group'],'split':entry['split'],'provenance':{'scene_id':sid,'label_authority':'unit_fixture'},
          'observations':{'history':h19,'rgb':h19[-1]['rgb'],'selected_subject':{'tap_xy':[.3,.4]},'intent':{'id':'context','height_min':.1,'height_max':.23,'visible_min':.65},'protected_style':None,'constraints':{'focal_bounds_mm':[17.,85.]},'current_focal_mm':entry['camera']['focal_mm'],'action_candidates':actions,'candidate_available':[True]*32,'observation_cutoff_s':0.}}
        target19={'record_id':'fixture19','decision':'keep','target_action_index':0,'action_success':[True]+[False]*30+[True],'loss_masks':{'action_success':[True]*32,'decision':True},'human_utility':None}
        row20={'record_id':'fixture-mesh:0:track','origin_group':'fixture_mesh_group','split':'train','provenance':{'label_authority':'unit_fixture'},
          'observations':{'history':h20,'subject_tap_xy':[.3,.4],'intent':{'id':'track','height_min':.1,'height_max':.9,'min_visible':.75,'max_center_shift':.12,'temporal':'all_samples'},
          'candidate_actions':[{'id':f'fixture_{i}','dx_m':i*.01,'yaw_deg':0.,'focal_factor':1.,'cost':float(i)} for i in range(11)],'candidate_available':[True]*11,'observation_cutoff_s':0.}}
        target20={'record_id':row20['record_id'],'decision':'keep','target_action_index':0,'action_success':[True]+[False]*10,'loss_masks':{'action_success':[True]*11,'decision':True},'human_utility':None}
        for root,row,target in [(self.a,row19,target19),(self.b,row20,target20)]:U.write_lines(root/'inputs.jsonl',[row]);U.write_lines(root/'targets.jsonl',[target])
        p=self.b/'after.png';Image.new('RGB',(8,6),(120,80,90)).save(p)
        U.write_lines(self.b/'outcomes.jsonl',[{'origin_group':'fixture_mesh_group','scene_id':'fixture-mesh','split':'train','after_media':[{'path':p.name,'t_s':1.,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}]}])
    def tearDown(self):self.tmp.cleanup()
    def run_collect(self):
        out=self.base/'out';out.mkdir();return out,M.collect(self.v19,self.v20,out,INDEX)
    def test_actual_fixture_image_join_and_mixed_batch(self):
        out,(rows,native,verifier,counts,modes)=self.run_collect()
        self.assertEqual(counts,{'v19':1,'v20':1});self.assertEqual(len(verifier),1);self.assertEqual(modes,{'pinned_metadata_reconstruction':1})
        M.assert_native_fidelity(rows,native);X,Y,masks=U.batch(out,rows)
        self.assertEqual(X['candidate_present'].sum(axis=1).tolist(),[31,11]);self.assertFalse(masks['action_success'][1,11:].any())
        self.assertTrue((out/verifier[0]['after_media'][0]['path']).is_file())
        self.assertFalse(any('after' in h['path'] for r in rows for h in r['observations']['history']))
    def test_duplicate_source_package_rejected(self):
        shutil.copytree(self.a,self.v19/'duplicate')
        with self.assertRaisesRegex(ValueError,'Duplicate source corpus'):self.run_collect()
    def test_corrupt_after_frame_rejected(self):
        (self.b/'after.png').write_bytes(b'not the source image')
        with self.assertRaisesRegex(ValueError,'checksum'):self.run_collect()
    def test_missing_prefix_rejected(self):
        (self.a/'prefix_1.png').unlink()
        with self.assertRaises(FileNotFoundError):self.run_collect()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--index',type=Path,required=True);a=p.parse_args();INDEX=C.load_index(a.index)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CompactPipelineTests))
    report={'tests_run':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'fixture_images_only':True,'production_dataset_records_processed':0,'new_dataset_examples':0,'model_calls':0,'render_calls':0}
    Path('CC21_COMPACT_PIPELINE_TESTS.json').write_text(json.dumps(report,indent=2)+'\n');print('CC21_COMPACT_PIPELINE_TESTS '+json.dumps(report))
    raise SystemExit(0 if result.wasSuccessful() else 1)
