"""Restore delivered CameraCoach components in a PRIVATE cloud environment.
Python 3.10+ standard library and OpenSSL only. No network, models or training.
The owner's private key is read by OpenSSL only and is never printed/copied.
Usage: python restore_dataset.py --parts-dir /private/parts --list
       python restore_dataset.py --parts-dir /private/parts --key /private/key.pem --out /private/restored --all
"""
from __future__ import annotations
import argparse,hashlib,json,re,shutil,subprocess,sys,tarfile,tempfile,zipfile
from pathlib import Path,PurePosixPath
from typing import Any

CHUNK=8*1024*1024

def sha(path:Path)->str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(CHUNK),b''):h.update(block)
    return h.hexdigest()

def safe_relative(name:str)->Path:
    p=PurePosixPath(name)
    if not name or '\\' in name or p.is_absolute() or '..' in p.parts or ':' in name:
        raise ValueError('Unsafe archive member path')
    return Path(*p.parts)

def discover(folder:Path)->dict[str,dict[str,Any]]:
    releases={}
    for path in sorted(folder.rglob('*.zip')):
        with zipfile.ZipFile(path) as z:
            if 'RELEASE.json' not in z.namelist():continue
            release=json.loads(z.read('RELEASE.json'));label=release['label']
            if not re.fullmatch(r'[A-Za-z0-9_-]+',label):raise ValueError('Invalid release label')
            item=releases.setdefault(label,{'release':release,'parts':{}})
            if item['release']!=release:raise ValueError('Conflicting manifests for '+label)
            names=set(z.namelist())
            for part in release['parts']:
                safe_relative(part['name'])
                if part['name'] in names:
                    info=z.getinfo(part['name'])
                    if info.file_size!=part['bytes']:raise ValueError('Incorrect part size: '+part['name'])
                    item['parts'].setdefault(part['name'],(path,part['name']))
    return releases

def missing(item:dict)->list[str]:
    return [p['name'] for p in item['release']['parts'] if p['name'] not in item['parts']]

def verify_payload(root:Path,release:dict)->dict:
    manifest=json.loads((root/'PAYLOAD_MANIFEST.json').read_text());entries=manifest['files']
    if manifest['label']!=release['label']:raise ValueError('Payload label mismatch')
    names=[e['path'] for e in entries]
    if len(set(names))!=len(names):raise ValueError('Duplicate payload entries')
    expected=set(names)|{'PAYLOAD_MANIFEST.json'}
    actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
    if expected!=actual:raise ValueError('Unexpected or missing payload files')
    for entry in entries:
        path=root/safe_relative(entry['path'])
        if path.is_symlink() or path.stat().st_size!=entry['size'] or sha(path)!=entry['sha256']:
            raise ValueError('Payload integrity failure: '+entry['path'])
    size=sum(e['size'] for e in entries)
    if len(entries)!=release['payload_files_verified'] or size!=release['payload_bytes']:
        raise ValueError('Payload totals mismatch')
    return {'verified_files':len(entries),'verified_payload_bytes':size,'payload_hash_mismatches':0}

def restore_one(item:dict,key:Path,out:Path)->dict:
    release=item['release'];label=release['label'];absent=missing(item)
    if absent:raise ValueError('Missing parts for '+label+': '+', '.join(absent))
    if not key.is_file():raise ValueError('Private key file is unavailable')
    if not shutil.which('openssl'):raise ValueError('OpenSSL is required')
    out.mkdir(parents=True,exist_ok=True);dest=out/label
    if dest.exists():raise FileExistsError('Refusing to overwrite '+str(dest))
    with tempfile.TemporaryDirectory(prefix='cc-restore-',dir=out) as td:
        temp=Path(td);cipher=temp/'payload.cms';plain=temp/'payload.tar.gz'
        total=0;full=hashlib.sha256()
        with cipher.open('wb') as f:
            for part in release['parts']:
                path,name=item['parts'][part['name']];h=hashlib.sha256();count=0
                with zipfile.ZipFile(path) as z,z.open(name) as stream:
                    for block in iter(lambda:stream.read(CHUNK),b''):
                        f.write(block);h.update(block);full.update(block);count+=len(block);total+=len(block)
                if count!=part['bytes'] or h.hexdigest()!=part['sha256']:raise ValueError('Part integrity failure: '+part['name'])
        if total!=release['encrypted_bytes'] or full.hexdigest()!=release['encrypted_sha256']:
            raise ValueError('Encrypted payload integrity failure')
        result=subprocess.run(['openssl','cms','-decrypt','-binary','-inform','DER','-in',str(cipher),'-inkey',str(key),'-out',str(plain)],capture_output=True)
        if result.returncode:raise RuntimeError('CMS decryption failed; check the matching private key and OpenSSL installation')
        if plain.stat().st_size!=release['plaintext_bytes'] or sha(plain)!=release['plaintext_sha256']:
            raise ValueError('Plaintext archive integrity failure')
        pending=temp/'verified';pending.mkdir();seen=set();extracted=0
        with tarfile.open(plain,'r:gz') as archive:
            for m in archive:
                rel=safe_relative(m.name)
                if str(rel) in seen:raise ValueError('Duplicate tar member')
                seen.add(str(rel))
                if not m.isfile():raise ValueError('Only regular files are accepted in this release')
                extracted+=m.size
                # Manifest itself adds modest JSON overhead to declared payload size.
                if extracted>release['payload_bytes']+64*1024*1024:raise ValueError('Unexpected expanded archive size')
                target=pending/rel;target.parent.mkdir(parents=True,exist_ok=True)
                with archive.extractfile(m) as src,target.open('xb') as dst:shutil.copyfileobj(src,dst,CHUNK)
        verified=verify_payload(pending,release)
        pending.rename(dest)
    receipt={'schema':'cc18.restore_receipt.v1','label':label,'source':'private supplied part files','encrypted_sha256':release['encrypted_sha256'],
       'plaintext_sha256':release['plaintext_sha256'],'all_parts_verified':True,'all_zip_crcs_checked':True,'cms_decrypted':True,
       'safe_extraction':True,**verified,'model_calls':0,'human_utility_validated':False}
    (out/(label+'.RESTORE_RECEIPT.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parts-dir',required=True,type=Path);p.add_argument('--key',type=Path);p.add_argument('--out',type=Path)
    p.add_argument('--list',action='store_true');p.add_argument('--all',action='store_true');p.add_argument('--label',action='append',default=[]);a=p.parse_args()
    releases=discover(a.parts_dir)
    if not releases:raise ValueError('No outer part ZIPs with RELEASE.json were found')
    if a.list:
        print(json.dumps([{'label':k,'found_parts':len(v['parts']),'expected_parts':len(v['release']['parts']),'missing_parts':missing(v)} for k,v in sorted(releases.items())],indent=2));return
    if not a.key or not a.out or not(a.all or a.label):p.error('Restoration needs --key, --out and --all or --label')
    labels=sorted(releases) if a.all else a.label
    for label in labels:
        if label not in releases:raise ValueError('Unknown release: '+label)
        if missing(releases[label]):raise ValueError('Incomplete release '+label+': '+', '.join(missing(releases[label])))
    for label in labels:print(json.dumps(restore_one(releases[label],a.key,a.out)))

if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,OSError,zipfile.BadZipFile,tarfile.TarError) as e:
        print(type(e).__name__+': '+str(e),file=sys.stderr);sys.exit(2)
