"""Restore only the three approved CC20 real-data components, without network.
Requires an existing private user key for CMS; never prints or copies the key.
Does not execute models, training, or code contained in downloaded datasets.
"""
from __future__ import annotations
import argparse,json,sys,zipfile
from pathlib import Path
import restore_dataset as R


def selected(parts_dir,catalog):
    found=R.discover(parts_dir);chosen={}
    for name,component in catalog['components'].items():
        expected=component['release'];label=expected['label']
        if label not in found:chosen[name]={'release':expected,'parts':{}};continue
        item=found[label]
        if item['release']!=expected:raise ValueError('Untrusted or mismatched release manifest: '+label)
        chosen[name]=item
    return chosen


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parts-dir',required=True,type=Path);p.add_argument('--key',type=Path);p.add_argument('--out',type=Path)
    p.add_argument('--catalog',type=Path,default=Path(__file__).with_name('REAL_COMPONENT_CATALOG.json'));p.add_argument('--list',action='store_true');p.add_argument('--component',action='append',choices=['illumination','holoassist','objectron'])
    a=p.parse_args();catalog=json.loads(a.catalog.read_text());items=selected(a.parts_dir,catalog)
    if a.list:
        print(json.dumps([{'component':name,'label':v['release']['label'],'found_parts':len(v['parts']),'expected_parts':len(v['release']['parts']),'missing_parts':R.missing(v)} for name,v in items.items()],indent=2));return
    if not a.key or not a.out:p.error('Restoration requires --key and --out')
    names=a.component or sorted(items)
    for name in names:
        if R.missing(items[name]):raise ValueError('Incomplete approved component '+name+': '+', '.join(R.missing(items[name])))
    for name in names:
        item=items[name];dest=a.out/item['release']['label']
        if dest.exists():
            receipt={'component':name,'existing_payload_rechecked':True,**R.verify_payload(dest,item['release']),'model_calls':0}
        else:receipt={'component':name,**R.restore_one(item,a.key,a.out)}
        print(json.dumps(receipt))

if __name__=='__main__':
    try:main()
    except (ValueError,OSError,RuntimeError,zipfile.BadZipFile) as e:
        print(type(e).__name__+': '+str(e),file=sys.stderr);sys.exit(2)
