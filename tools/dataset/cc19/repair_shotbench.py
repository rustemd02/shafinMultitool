"""Repair native TSV parsing; never infer correspondence from visual similarity.
The historical acquisition script is retained. All recovered records stay test-only.
"""
from pathlib import Path
import hashlib,sys,shutil
source=Path('tools/dataset/cc17/cc18_shotbench_supplement.py')
text=source.read_text()
old="upstream_paths={Path(r['path']).name for r in upstream if str(r.get('type','')).lower()=='video'}"
assert text.count(old)==1,'Historical native parser changed; review required'
new='''import ast

def native_list(value):
    if isinstance(value,list):result=value
    elif isinstance(value,str):
        stripped=value.strip()
        if stripped.startswith('['):
            try:result=json.loads(stripped)
            except json.JSONDecodeError:result=ast.literal_eval(stripped)
        else:result=[stripped]
    else:raise TypeError('Native field is neither string nor list')
    if not isinstance(result,list) or not all(isinstance(v,str) for v in result):raise ValueError('Non-string native list')
    return result

upstream_paths=set()
for record in upstream:
    types=native_list(record['type']);paths=native_list(record['path'])
    if len(types)!=len(paths):raise ValueError('Native type/path arity mismatch')
    for typ,path in zip(types,paths):
        if typ.lower()=='video':upstream_paths.add(Path(path).name)
print('CC19_SHOTBENCH_NATIVE_PARSE',len(upstream_paths),flush=True)
'''
text=text.replace(old,new)
old2="key,row=item;src=Path(row['local_source']);dest=root/'media'/(key+'.mp4')"
new2="""key,row=item;src=Path(row['local_source']);dest=root/'media'/(key+'.mp4')
    native_dest=root/'native_selected_videos'/(key+src.suffix)
    native_dest.parent.mkdir(exist_ok=True);shutil.copyfile(src,native_dest)
    assert digest(native_dest)==key
    row={**row,'native_path':str(native_dest.relative_to(root))}
"""
assert text.count(old2)==1;text=text.replace(old2,new2)
text=text.replace("package(root,'cc18-acam-shotbench-supplement')","package(root,'cc19-acam-shotbench-native-supplement')")
root=Path('shotbench_supplement/reproduction');root.mkdir(parents=True,exist_ok=True)
shutil.copyfile(__file__,root/'repair_shotbench.py')
(root/'repair_provenance.json').write_text(__import__('json').dumps({'historical_script':str(source),'historical_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'effective_sha256':hashlib.sha256(text.encode()).hexdigest(),'changes':['parse list-valued type/path fields','retain selected native video bytes','new release label'],'train_rows':0},indent=2))
sys.path.insert(0,str(source.parent.resolve()))
exec(compile(text,str(source),mode='exec'),{'__name__':'__main__','__file__':str(source)})
