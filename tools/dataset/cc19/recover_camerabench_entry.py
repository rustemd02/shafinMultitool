"""Verified native names and a bounded rational derivative video timebase.
Historical source bytes/PTS remain unchanged; derived sampling is documented.
Unique full-basename joins and all source/hash/decoding checks stay enabled.
"""
from pathlib import Path
import hashlib,json,sys
source=Path(__file__).with_name('recover_camerabench.py')
text=source.read_text()
old="if '/camerabench/' in r['image'].lower():requested.append"
new="if str(Path(r['image']).parent)=='real_videos/Camera_Motion_Bench/videos':requested.append"
assert text.count(old)==1;text=text.replace(old,new)
old="assert requested,'No exact CameraBench references in pinned ACaM source'"
assert text.count(old)==1;text=text.replace(old,"assert len(requested)==454,{'unexpected_native_reference_count':len(requested)}")
assert text.count('videos_test.jsonl')==2;text=text.replace('videos_test.jsonl','test.jsonl')
assert text.count('import av\n')==1;text=text.replace('import av\n','import av\nfrom fractions import Fraction\n')
assert text.count('{16/duration:.12g}')==1
text=text.replace('{16/duration:.12g}','{Fraction(16/duration).limit_denominator(1000)}')
text=text.replace("[FF,'-v','error','-threads','1','-i',str(src),'-an'", "[FF,'-v','error','-threads','1','-i',str(src),'-map','0:v:0','-an'")
text=text.replace("'source_duration_s_from_pts':duration,'not_sensor_capture_clock':True", "'source_duration_s_from_pts':duration,'derivative_sampling_fps_rational':str(Fraction(16/duration).limit_denominator(1000)),'not_sensor_capture_clock':True")
root=Path('camerabench_supplement/reproduction');root.mkdir(parents=True,exist_ok=True)
(root/'native_prefix_repair.json').write_text(json.dumps({'source_script_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'effective_script_sha256':hashlib.sha256(text.encode()).hexdigest(),'native_prefix':'real_videos/Camera_Motion_Bench/videos','expected_rows':454,'annotation_file':'test.jsonl','evidence_workflow_run':39812729078,'evidence_job':119943024017,'changes':['verified source-directory and annotation filename','bounded rational derivative FPS denominator<=1000','explicit first-video-stream mapping'],'native_pixels_and_PTS_modified':False,'approximate_media_joins':False},indent=2)+'\n')
(root/'recover_camerabench_entry.py').write_text(Path(__file__).read_text())
sys.path.insert(0,str(source.parent))
exec(compile(text,str(source),'exec'),{'__name__':'__main__','__file__':str(source)})
