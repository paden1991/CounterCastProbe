"""Build a complete, redistributable Forever release from reviewed source."""
from pathlib import Path
import hashlib,json,os,re,zipfile
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'source-manifest.json').read_text());name=m['addon'];version=m['version']
if any(f['external'] for f in m['files']):
    raise SystemExit('Public release blocked: local-only dependencies remain. See LOCAL_DEPENDENCIES.md.')
tag=os.environ.get('GITHUB_REF_NAME','v'+version)
if tag!='v'+version:raise SystemExit('Tag does not match the reviewed manifest version')
blobs={}
for f in m['files']:
    rel=Path(f['path'])
    if rel.is_absolute() or '..' in rel.parts:raise SystemExit('Invalid manifest path')
    blob=(root/name/rel).read_bytes()
    if hashlib.sha256(blob).hexdigest()!=f['sha256']:raise SystemExit('Source hash changed: '+f['path'])
    blobs[f['path']]=blob
toc=blobs[name+'.toc'].decode('utf8')
assert re.search(r'^## Interface:\s*16001\s*$',toc,re.M),'Incorrect Forever interface'
assert re.search(r'^## Version:\s*'+re.escape(version)+r'\s*$',toc,re.M),'Version mismatch'
for line in toc.splitlines():
    if line.strip() and not line.startswith('#'):assert line.strip().replace('\\','/') in blobs,line
out=root/'dist';out.mkdir(exist_ok=True)
filename=f'{name}-{version}-forever.zip';target=out/filename
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
    for rel,blob in sorted(blobs.items()):
        info=zipfile.ZipInfo(name+'/'+rel,(2026,11,2,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,blob)
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    assert {p.split('/')[0] for p in z.namelist()}=={name}
    assert z.read(name+'/'+name+'.toc')==blobs[name+'.toc']
    assert all(z.read(name+'/'+p)==b for p,b in blobs.items())
metadata={'releases':[{'name':version,'filename':filename,'nolib':False,'metadata':[{'flavor':'forever','interface':16001}]}]}
(out/'release.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf8')
(out/'SHA256SUMS.txt').write_text(hashlib.sha256(target.read_bytes()).hexdigest()+'  '+filename+'\n',encoding='utf8')
print(json.dumps({'archive':filename,'files':len(blobs),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'interface':16001}))
