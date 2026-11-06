#!/usr/bin/env python3
"""Validate the selected source distribution; no device/service operations."""
from pathlib import Path
import hashlib,json,re,os,ast,subprocess
ROOT=Path(__file__).resolve().parents[1]
manifest=ROOT/'tools/SOURCE-MANIFEST.json'
record=json.loads(manifest.read_text())
ignored={'.git','build','releases','.state','.import','.godot','__pycache__'}
actual={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and not any(x in ignored for x in p.relative_to(ROOT).parts)}
assert actual==set(record['files'])|{'tools/SOURCE-MANIFEST.json'},'Unexpected or missing source file'
for name,entry in record['files'].items():
 p=ROOT/name
 assert not p.is_symlink() and hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256'],name
 if os.name!='nt':assert bool(p.stat().st_mode & 0o111)==(entry['mode']=='100755'),('File mode',name)
 assert not name.lower().endswith(('.apk','.aar','.so','.a','.jks','.keystore','.p12','.pem')),name
 assert not (name.startswith('app/assets/music/') and name!='app/assets/music/README.md'),name
 data=p.read_bytes()
 for pattern in [rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'github_pat_[A-Za-z0-9_]{25,}',rb'gh[pousr]_[A-Za-z0-9]{25,}']:
  assert not re.search(pattern,data),('Credential signature',name)
 try:text=data.decode('utf-8')
 except UnicodeError:continue
 assert not re.search(r'/(?:home|mnt)/[^/\s]+/|\b10\.0\.0\.\d{1,3}\b|\bRF8[A-Z0-9]{8}\b|\b(?:[0-9A-F]{2}:){5}[0-9A-F]{2}\b',text),('Private installation reference',name)
 if name.endswith('.py'):ast.parse(text,filename=name)
 if name.endswith('.sh'):subprocess.run(['bash','-n',str(p)],check=True)
 if name.startswith('app/') and name.endswith(('.gd','.tscn','.gdns','.gdnlib')):
  for resource in re.findall(r'res://([^"\s\x27]+)',text):
   if any(c in resource for c in ['%','*']):continue
   if (ROOT/'app'/resource).exists():continue
   if resource.startswith(('assets/music/','tests/fixtures/','native/bin/')):continue
   if resource in ['native/ShieldSendspin.gdns','native/ShieldSendspin.gdnlib']:continue
   if name=='app/tests/test_kinegra_amp_branding.gd' and resource=='scripts/DeviceAcceptance.gd':continue # explicit negative-absence assertion
   raise AssertionError(('Missing source resource',name,resource))
lock=json.loads((ROOT/'tools/dependencies.lock.json').read_text())
for dependency in lock['external']:
 p=ROOT/'tools/licenses'/(dependency['name']+'-LICENSE.txt')
 assert hashlib.sha256(p.read_bytes()).hexdigest()==dependency['license_sha256'],dependency['name']
for item in lock['verified_vendored_source']['verified_upstream_blobs']:
 assert hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()==item['sha256'],item['path']
print('SOURCE_INTEGRITY_PASS files='+str(len(record['files']))+' external_notices='+str(len(lock['external'])))
