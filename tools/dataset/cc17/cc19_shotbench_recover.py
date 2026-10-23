"""Re-run the source-native ACaM join with correct ShotBench TSV decoding.
The author serializes type/path as JSON arrays; plain 'video' equality excluded
all rows. Raw TSV bytes remain untouched and retained in the resulting package.
"""
from pathlib import Path
import hashlib,json
source=Path(__file__).with_name('cc18_shotbench_supplement.py')
text=source.read_text()
old="upstream_paths={Path(r['path']).name for r in upstream if str(r.get('type','')).lower()=='video'}"
new='''def author_cell(value):
    value=str(value).strip()
    if value.startswith('['):
        parsed=json.loads(value)
        if not isinstance(parsed,list) or not all(isinstance(x,str) for x in parsed):
            raise ValueError('Unexpected native TSV array field')
        return parsed
    return [value]
upstream_paths=set()
for record in upstream:
    types=author_cell(record['type']);paths=author_cell(record['path'])
    if len(types)!=len(paths):raise ValueError('Native type/path cardinality mismatch')
    for media_type,media_path in zip(types,paths):
        if media_type.lower()=='video':upstream_paths.add(Path(media_path).name)
write_json(root/'NATIVE_TSV_DECODING.json',{'rule':'JSON decode author type/path arrays; zip aligned entries; exact basename only','native_source_changed':False,'video_basename_count':len(upstream_paths)})'''
assert text.count(old)==1,'source changed; refuse an unverified patch'
text=text.replace(old,new)
# Pin the effective collector itself as part of the released evidence.
needle="(root/'native').mkdir(exist_ok=True);cache="
assert text.count(needle)==1
text=text.replace(needle,"(root/'native').mkdir(exist_ok=True);(root/'native/EFFECTIVE_COLLECTOR.py').write_text(__effective_source__);cache=")
namespace={'__name__':'__main__','__file__':str(source),'__effective_source__':text}
exec(compile(text,str(source),'exec'),namespace)
