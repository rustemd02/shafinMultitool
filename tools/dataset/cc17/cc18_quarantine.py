"""Scene-atomic recovery of a failed CC18 shard.
Checks remain unchanged. A failed scene is excluded in full, including all its
counterfactuals, inputs and targets; native failure details are retained.
No success filtering, label repair or heldout reassignment occurs.
"""
import argparse,ast,collections,copy,json,shutil
from pathlib import Path
import cc18_entry as E
from acquire import write_json,digest
R=E.R
QUARANTINE=[]
# Wrap precisely the per-scene loop, leaving every numeric/ray/tensor assertion
# and the full post-loop corpus audit intact.
tree=ast.parse(Path(R.__file__).read_text())
run=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='run')
loops=[n for n in ast.walk(run) if isinstance(n,ast.For) and isinstance(n.target,ast.Name) and n.target.id=='index']
assert len(loops)==1
loop=loops[0]
before=ast.parse('''
_checkpoint=(len(inputs),len(targets),copy.deepcopy(stats),copy.deepcopy(groups),contrasts,rerenders,copy.deepcopy(exact_pixels),len(image_signatures),fc.tell(),fs.tell(),fv.tell())
''').body
handler=ast.parse('''
except_placeholder=0
''').body
cleanup=ast.parse('''
ni,nt,old_stats,old_groups,old_contrasts,old_rerenders,old_pixels,ns,pc,ps,pv=_checkpoint
del inputs[ni:];del targets[nt:];del image_signatures[ns:]
stats=old_stats;groups=old_groups;contrasts=old_contrasts;rerenders=old_rerenders;exact_pixels=old_pixels
for stream,pos in [(fc,pc),(fs,ps),(fv,pv)]:
    stream.seek(pos);stream.truncate()
shutil.rmtree(root/'media'/f'cc18-{index:06d}',ignore_errors=True)
shutil.rmtree(root/'repro_check',ignore_errors=True)
QUARANTINE.append({'origin_id':f'cc18-{index:06d}','source_index':index,'status':'excluded_entire_scene','reason':str(error),'training_eligible':False,'test_eligible':False,'replacement_generated':False})
print('CC18_QUARANTINE',index,str(error),flush=True)
''').body
loop.body=before+[ast.Try(body=loop.body,handlers=[ast.ExceptHandler(type=ast.Name(id='AssertionError',ctx=ast.Load()),name='error',body=cleanup)],orelse=[],finalbody=[])]
mod=ast.Module(body=[run],type_ignores=[]);ast.fix_missing_locations(mod)
R.__dict__['QUARANTINE']=QUARANTINE
exec(compile(mod,str(Path(__file__))+'::scene_atomic_run','exec'),R.__dict__)
parent_package=R.package

def package_with_quarantine(root,label):
    write_json(root/'QUARANTINE.json',{'rejected_scenes':QUARANTINE,'rule':'exclude every field/view from any scene failing an existing assertion; never weaken GT verification','substitutions':0})
    q=json.loads((root/'QA.json').read_text());q['scene_quarantine_count']=len(QUARANTINE);q['scene_configurations_attempted']=q['stats']['scene_configurations']+len(QUARANTINE);q['quarantine_runner_sha256']=digest(Path(__file__));write_json(root/'QA.json',q)
    parent_package(root,label)
R.package=package_with_quarantine

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',required=True,type=int);p.add_argument('--shards',default=8,type=int);p.add_argument('--count',default=512,type=int);a=p.parse_args()
    R.run(a.shard,a.shards,a.count,'cc18-final')
