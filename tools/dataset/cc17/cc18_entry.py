"""Canonical procedural-render encoding and the CC18 data-only runner.
Blender PNG metadata embeds variable render time; decoded pixels are unchanged.
The original byte-hash reproducibility assertion remains enabled.
"""
import argparse
from pathlib import Path
from PIL import Image
import cc18_run as R
from acquire import digest
raw_render=R.C.state_render

def canonical_render(*args,**kwargs):
    state,pixels=raw_render(*args,**kwargs)
    path=Path(state['rgb_path'])
    Image.fromarray(pixels,mode='RGB').save(path,format='PNG',compress_level=6)
    state['rgb_sha256']=digest(path)
    state['encoding']='canonical lossless RGB PNG without variable Blender metadata'
    return state,pixels

R.C.state_render=canonical_render
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--shard',type=int,default=0);p.add_argument('--shards',type=int,default=8);p.add_argument('--count',type=int,default=512);p.add_argument('--label-prefix',default='cc18-final');a=p.parse_args()
    R.run(a.shard,a.shards,a.count,a.label_prefix)
