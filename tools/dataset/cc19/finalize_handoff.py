"""Build the handoff using the verified cc17-upload index envelope format.
Parts contain RELEASE.json; INDEX artifacts contain ARTIFACT_INDEX.json with a
nested release object. No manifest contents, hashes, or validation are changed.
"""
from pathlib import Path
source=Path(__file__).with_name('build_delivery_handoff.py')
text=source.read_text()
old="meta,data,z=artifact(aid);release=json.loads(z.read('RELEASE.json'));assert release['label']==label"
new="meta,data,z=artifact(aid);release=json.loads(z.read('ARTIFACT_INDEX.json'))['release'];assert release['label']==label"
assert text.count(old)==1,'Builder source changed; inspect before patching'
effective=text.replace(old,new)
namespace={'__name__':'__main__','__file__':str(source)}
exec(compile(effective,str(source),'exec'),namespace)
# The actual executable builder is retained, not merely an unpatched source path.
out=Path('cc19_handoff')
(out/'EFFECTIVE_HANDOFF_BUILDER.py').write_text(effective)
import hashlib,json
manifest=json.loads((out/'HANDOFF_MANIFEST.json').read_text())
p=out/'EFFECTIVE_HANDOFF_BUILDER.py'
manifest['files'].append({'path':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'HANDOFF_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
