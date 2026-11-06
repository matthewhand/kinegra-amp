#!/usr/bin/env python3
"""Stage experimental GDNative resources into an isolated copied Godot app.
Never edits the active source tree and never signs, deploys or installs.
"""
from pathlib import Path
import argparse,hashlib,shutil,tempfile
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('copied_app',type=Path)
p.add_argument('android_so',type=Path)
p.add_argument('host_so',type=Path)
a=p.parse_args()
app=a.copied_app.resolve()
# Do not mutate a live checkout; experimental exports belong under system tmp.
tmp=Path(tempfile.gettempdir()).resolve()
if not app.is_dir() or app==root/'app' or tmp not in app.parents or not (app/'project.godot').is_file():
    raise SystemExit('requires an isolated Godot project copy under temp')
target=app/'native'
for name in ('ShieldSendspin.gdnlib','ShieldSendspin.gdns','bin/libshield_sendspin_arm64.so','bin/libshield_sendspin_x11.so'):
    if (target/name).exists(): raise SystemExit('refusing to replace '+name)
for src in (a.android_so,a.host_so):
    if not src.is_file() or src.stat().st_size<1000: raise SystemExit('native library missing')
(target/'bin').mkdir(parents=True,exist_ok=True)
for name in ('ShieldSendspin.gdnlib','ShieldSendspin.gdns'):
    shutil.copyfile(root/'native/sendspin_assets'/name,target/name)
for src,name in ((a.android_so,'libshield_sendspin_arm64.so'),(a.host_so,'libshield_sendspin_x11.so')):
    dest=target/'bin'/name
    shutil.copyfile(src,dest)
    print(name,hashlib.sha256(dest.read_bytes()).hexdigest())
print('EXPERIMENTAL_FIXTURE_STAGED_NO_DEVICE_ACTIONS')
