#!/usr/bin/env python3
"""Build the documented Godot Android audio fix from official source, no device I/O."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, tarfile

ROOT = Path(__file__).resolve().parents[1]
def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--ndk', type=Path, required=True)
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--scons', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--jobs', type=int, default=4)
    a = p.parse_args()
    if not 1 <= a.jobs <= 8: p.error('jobs must be between 1 and 8')
    record = json.loads((ROOT/'native/godot-opensl-runtime.json').read_text())
    assert digest(a.archive) == record['archive_sha256'], 'Godot source archive differs from public pin'
    patch = ROOT/'native/patches/godot-3.6.3-opensl-shutdown.patch'
    assert digest(patch) == record['patch_sha256'], 'Audio patch differs from reviewed source'
    assert 'Pkg.Revision = '+record['ndk'] in (a.ndk/'source.properties').read_text(), 'Wrong NDK revision'
    version = subprocess.check_output([str(a.scons), '--version'], text=True)
    assert '4.8.1' in version, 'SCons 4.8.1 required'
    out = a.output.resolve()
    out.mkdir(mode=0o700, parents=True, exist_ok=False)
    src = out/'source'; src.mkdir()
    with tarfile.open(a.archive) as archive:
        members = archive.getmembers()
        assert all(not m.issym() and not m.islnk() and not Path(m.name).is_absolute() and '..' not in Path(m.name).parts for m in members)
        archive.extractall(src, filter='data')
    roots = [x for x in src.iterdir() if x.is_dir()]
    assert len(roots) == 1
    src = roots[0]
    sdk = out/'android-sdk'; sdk.mkdir()
    for entry in a.sdk.resolve().iterdir():
        if entry.name != 'ndk': (sdk/entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    (sdk/'ndk').mkdir()
    (sdk/'ndk'/record['ndk']).symlink_to(a.ndk.resolve(), target_is_directory=True)
    env = dict(os.environ, ANDROID_SDK_ROOT=str(sdk), ANDROID_NDK_ROOT=str(a.ndk.resolve()))
    subprocess.run(['patch', '--batch', '-p1', '-i', str(patch)], cwd=src, check=True, stdout=subprocess.DEVNULL)
    flags = [x for x in record['scons_flags'] if not x.startswith('-j')]
    cmd = [str(a.scons), '-j'+str(a.jobs), *flags]
    with (out/'engine-build.log').open('w') as log:
        subprocess.run(cmd, cwd=src, env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
    lib = src/'platform/android/java/lib/libs/release/arm64-v8a/libgodot_android.so'
    assert lib.is_file()
    result = {'kind':'public-source-built-godot-audio-runtime', 'source_archive_sha256':digest(a.archive),
              'patch_sha256':digest(patch), 'ndk':record['ndk'], 'scons':'4.8.1', 'flags':cmd[2:],
              'library':str(lib), 'sha256':digest(lib), 'device_actions':False}
    (out/'audio-engine.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
if __name__ == '__main__': main()
