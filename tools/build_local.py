"""Build a local addon ZIP without downloading or modifying any dependencies."""
from pathlib import Path
import argparse,hashlib,json,zipfile
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--local-addon',type=Path);p.add_argument('--verify-only',action='store_true');a=p.parse_args()
m=json.loads((root/'source-manifest.json').read_text());name=m['addon'];blobs={};missing=[]
for f in m['files']:
    rel=Path(f['path'])
    if rel.is_absolute() or '..' in rel.parts:raise SystemExit('Invalid manifest path')
    base=a.local_addon if f['external'] else root/name
    path=base/rel if base else None
    if not path or not path.is_file():missing.append(f['path']);continue
    blob=path.read_bytes()
    if hashlib.sha256(blob).hexdigest()!=f['sha256']:raise SystemExit('File differs from reviewed version: '+f['path'])
    blobs[f['path']]=blob
if missing:
    if a.verify_only and not a.local_addon:
        external={f['path'] for f in m['files'] if f['external']}
        if not set(missing)<=external:raise SystemExit('Missing public source: '+str(missing))
        print(f'Public source verified: {len(blobs)} files; {len(missing)} documented local dependencies.');raise SystemExit(0)
    raise SystemExit('Supply --local-addon pointing to the matching complete addon folder. Missing: '+', '.join(missing))
if a.verify_only:print(f'Complete local build verified: {len(blobs)} files.');raise SystemExit(0)
out=root/'dist';out.mkdir(exist_ok=True);target=out/f'{name}-{m["version"]}-local.zip'
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
    for rel,blob in sorted(blobs.items()):z.writestr(name+'/'+rel,blob)
with zipfile.ZipFile(target) as z:assert z.testzip() is None
print(target)
