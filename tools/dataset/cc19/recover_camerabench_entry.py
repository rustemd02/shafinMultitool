"""Repair only the exact source-directory discriminator from the native ACaM audit.
The historical failing script is preserved. Full unique-basename joins and all
media/rights/size/decoding checks are unchanged.
"""
from pathlib import Path
import hashlib,json,sys
source=Path(__file__).with_name('recover_camerabench.py')
text=source.read_text()
old="if '/camerabench/' in r['image'].lower():requested.append"
new="if str(Path(r['image']).parent)=='real_videos/Camera_Motion_Bench/videos':requested.append"
assert text.count(old)==1,'Review changed upstream acquisition script'
text=text.replace(old,new)
old2="assert requested,'No exact CameraBench references in pinned ACaM source'"
new2="assert len(requested)==454,{'unexpected_native_reference_count':len(requested)}"
assert text.count(old2)==1;text=text.replace(old2,new2)
root=Path('camerabench_supplement/reproduction');root.mkdir(parents=True,exist_ok=True)
(root/'native_prefix_repair.json').write_text(json.dumps({'source_script_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'effective_script_sha256':hashlib.sha256(text.encode()).hexdigest(),'native_prefix':'real_videos/Camera_Motion_Bench/videos','expected_rows':454,'evidence_workflow_run':39812729078,'evidence_job':119943024017,'changes':['exact source-directory discriminator only'],'approximate_media_joins':False},indent=2)+'\n')
(root/'recover_camerabench_entry.py').write_text(Path(__file__).read_text())
sys.path.insert(0,str(source.parent))
exec(compile(text,str(source),'exec'),{'__name__':'__main__','__file__':str(source)})
