"""Regression fixtures, never counted as acquired media or training records."""
import copy,hashlib,io,json,tarfile,tempfile,unittest
from pathlib import Path
import numpy as np
from PIL import Image
import calibration_index as C
import merge_sources as M
import unified_dataset as U

INDEX=None
class MergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.index=copy.deepcopy(INDEX)
        self.sid=next(iter(self.index['records']));entry=self.index['records'][self.sid]
        self.row={'record_id':'fixture_v19','schema':'cameracoach.component.v18.2','origin_group':entry['origin_group'],'split':entry['split'],
          'provenance':{'scene_id':self.sid,'label_authority':'unit_test_fixture'},'observations':{'current_focal_mm':entry['camera']['focal_mm']}}
    def tearDown(self):self.tmp.cleanup()
    def test_index_size(self):self.assertEqual(len(self.index['records']),479)
    def test_orthonormal_all(self):
        for entry in self.index['records'].values():C.validate_camera(entry['camera'])
    def test_selected_split_counts(self):
        from collections import Counter
        self.assertEqual(dict(Counter(r['split'] for r in self.index['records'].values())),{'train':312,'validation':56,'test':111})
    def test_focal_mismatch_rejected(self):
        self.row['observations']['current_focal_mm']+=.01
        with self.assertRaises(ValueError):C.for_row(self.row,self.index)
    def test_group_mismatch_rejected(self):
        self.row['origin_group']='unknown'
        with self.assertRaises(ValueError):C.for_row(self.row,self.index)
    def test_split_mismatch_rejected(self):
        self.row['split']='test'
        with self.assertRaises(ValueError):C.for_row(self.row,self.index)
    def test_unknown_scene_rejected(self):
        self.row['provenance']['scene_id']='cc18-999999'
        with self.assertRaises(ValueError):C.for_row(self.row,self.index)
    def test_archived_camera_comparison(self):
        camera=self.index['records'][self.sid]['camera'];self.assertEqual(C.for_row(self.row,self.index,camera),camera)
    def test_archived_mismatch_rejected(self):
        camera=copy.deepcopy(self.index['records'][self.sid]['camera']);camera['focal_mm']+=.1
        with self.assertRaises(ValueError):C.for_row(self.row,self.index,camera)
    def test_compact_no_scenes_works(self):
        camera,authority=M.camera_for_row(self.row,self.root,self.index,{})
        self.assertEqual(camera,self.index['records'][self.sid]['camera']);self.assertEqual(authority,'pinned_metadata_reconstruction')
    def test_missing_calibration_fails_explicitly(self):
        with self.assertRaisesRegex(ValueError,'Supply --calibration'):M.camera_for_row(self.row,self.root,None,{})
    def test_duplicate_targets_rejected(self):
        p=self.root/'targets.jsonl';U.write_lines(p,[{'record_id':'x'},{'record_id':'x'}])
        with self.assertRaises(ValueError):M.indexed_rows(p)
    def test_unmatched_targets_rejected(self):
        p=self.root/'inputs.jsonl';U.write_lines(p,[{'record_id':'x'}]);U.write_lines(self.root/'targets.jsonl',[{'record_id':'y'}])
        with self.assertRaises(ValueError):M.component_rows(p)
    def test_bad_source_sha_rejected(self):
        p=self.root/'fake_generator.py';p.write_text('print("never execute")')
        with self.assertRaises(ValueError):C.build_index(p)
    def test_copy_media_checksum(self):
        p=self.root/'image.png';Image.new('RGB',(2,2)).save(p)
        with self.assertRaises(ValueError):M.copy_media(self.root,p.name,self.root/'out'/'image.png','0'*64)
    def archive(self,members):
        p=self.root/'data.tar.gz'
        with tarfile.open(p,'w:gz') as z:
            for name,data in members:
                m=tarfile.TarInfo(name);m.size=len(data);z.addfile(m,io.BytesIO(data))
        return p
    def test_archive_valid(self):
        data=b'abc';manifest={'a':{'bytes':3,'sha256':hashlib.sha256(data).hexdigest()}}
        self.assertEqual(M.extract_verified(self.archive([('a',data)]),self.root/'restore',manifest),1)
    def test_archive_missing_rejected(self):
        with self.assertRaises(ValueError):M.extract_verified(self.archive([]),self.root/'restore',{'a':{'bytes':3,'sha256':'x'}})
    def test_archive_duplicate_rejected(self):
        data=b'abc';manifest={'a':{'bytes':3,'sha256':hashlib.sha256(data).hexdigest()}}
        with self.assertRaises(ValueError):M.extract_verified(self.archive([('a',data),('a',data)]),self.root/'restore',manifest)
    def test_archive_escape_rejected(self):
        data=b'abc';manifest={'../a':{'bytes':3,'sha256':hashlib.sha256(data).hexdigest()}}
        with self.assertRaises(ValueError):M.extract_verified(self.archive([('../a',data)]),self.root/'restore',manifest)
    def test_archive_corruption_rejected(self):
        with self.assertRaises(ValueError):M.extract_verified(self.archive([('a',b'abc')]),self.root/'restore',{'a':{'bytes':3,'sha256':'0'*64}})
    def test_native_label_change_rejected(self):
        x={'record_id':'x','observations':{'actions':[{'native_index':0}]},'targets':{'success':[True],'success_known':[True],'decision':'keep','chosen_index':0}}
        e={'record_id':'x','native_target':{'action_success':[False],'loss_masks':{'action_success':[True]},'decision':'keep','target_action_index':0}}
        with self.assertRaises(ValueError):M.assert_native_fidelity([x],[e])

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--index',type=Path,required=True);a=p.parse_args();INDEX=C.load_index(a.index)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MergeTests))
    report={'tests_run':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'unit_fixtures_only':True,'calibration_bases_checked':479,'new_dataset_rows':0,'actual_merged_pixel_corpus_checked':False,'model_calls':0,'render_calls':0}
    Path('CC21_MERGE_FIX_TESTS.json').write_text(json.dumps(report,indent=2)+'\n');print('CC21_MERGE_FIX_TESTS '+json.dumps(report))
    raise SystemExit(0 if result.wasSuccessful() else 1)
