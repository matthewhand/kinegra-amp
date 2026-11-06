#!/usr/bin/env python3
"""Build/import an isolated Linux host preview from source. No device actions."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,signal,time
import PIL
from make_fixtures import make_fixtures

ROOT=Path(__file__).resolve().parents[1]
SOURCES=("godot_codec.c","tegra_codec.c","minimp3_impl.c","stb_vorbis_impl.c")

def run(args,env,log=None):
    result=subprocess.run([str(x) for x in args],env=env,capture_output=True,text=True,timeout=120)
    text=result.stdout+result.stderr
    if log:log.write_text(text)
    if result.returncode or "SCRIPT ERROR" in text or "Parse Error" in text or re.search(r"(?m)^ERROR:",text) or re.search(r"(?m)^(?:\S*_FAIL_|FAIL[: ])",text):
        raise RuntimeError(Path(str(args[0])).name+" failed; see preview logs")
    return text

def fixture_assets(app):
    """Every importable input in the fresh copy, including all generated media."""
    app=Path(app)
    generated=[app/"assets/music"/("track_%02d.ogg"%i) for i in range(1,5)]
    generated += [app/"assets/music/artwork"/("track_%02d.jpg"%i) for i in range(1,5)]
    if any(not path.is_file() for path in generated):
        raise RuntimeError("Generated fixture media is incomplete")
    # Godot 3 loads DynamicFontData .ttf/.otf directly; those do not get .import.
    suffixes={".ogg",".mp3",".png",".jpg",".jpeg",".svg"}
    return sorted(path for path in (app/"assets").rglob("*") if path.is_file() and path.suffix.lower() in suffixes)

def imports_ready(app,assets):
    app=Path(app).resolve()
    for asset in assets:
        metadata=Path(str(asset)+".import")
        if not metadata.is_file() or metadata.stat().st_size>65536:return False
        text=metadata.read_text()
        remaps=re.findall(r'(?m)^path(?:\.[A-Za-z0-9_]+)?="res://([^"\n]+)"$',text)
        if not remaps:return False
        for name in remaps:
            target=(app/name).resolve()
            if not name.startswith(".import/") or not target.is_relative_to(app/".import") or not target.is_file() or target.stat().st_size<1:return False
    return bool(assets)

def import_assets(base,env,app,log,timeout=30,assets=None):
    # Godot 3.6.3 --help says --quit exits after the FIRST iteration. Its scan
    # thread can still be starting then. Keep the real editor alive until every
    # fresh input has both a remap and its nonempty generated resource cache.
    assets=fixture_assets(app) if assets is None else assets
    deadline=time.monotonic()+timeout
    ready=False
    premature=False
    with Path(log).open("w") as output:
        process=subprocess.Popen([*base,"--editor"],env=env,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            while time.monotonic()<deadline:
                if imports_ready(app,assets):
                    ready=True
                    break
                if process.poll() is not None:
                    premature=True
                    break
                time.sleep(0.05)
        finally:
            if process.poll() is None:
                if os.name=="posix":os.killpg(process.pid,signal.SIGTERM)
                else:process.terminate()
                try:process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    if os.name=="posix":os.killpg(process.pid,signal.SIGKILL)
                    else:process.kill()
                    process.wait(timeout=3)
    text=Path(log).read_text()
    if not ready or "SCRIPT ERROR" in text or "Parse Error" in text or re.search(r"(?m)^ERROR:",text):
        reason="editor exited before imports completed" if premature else "fixture imports did not complete within the bound"
        raise RuntimeError(reason+"; see preview import log")
    return text

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",type=Path,default=os.environ.get("GODOT_BIN"),required=not bool(os.environ.get("GODOT_BIN")))
    parser.add_argument("--source",type=Path,default=ROOT)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--cc",default=os.environ.get("CC","cc"))
    parser.add_argument("--test",action="append",default=[],help="GDScript test relative to app, e.g. tests/test_transport_controls.gd")
    parser.add_argument("--run",action="store_true",help="Open the preview silently after building")
    parser.add_argument("--music-free",action="store_true",help="Keep empty production song/cover arrays; generated files remain test inputs only")
    args=parser.parse_args();source=args.source.resolve();output=args.output.resolve();godot=args.godot.resolve()
    if not godot.is_file():parser.error("Godot executable is missing")
    version=run([godot,"--version"],os.environ).strip()
    if not version.startswith("3.6.3."):parser.error("Godot 3.6.3 is required")
    for tool in [args.cc,"ffmpeg"]:
        if shutil.which(tool) is None:parser.error("Required tool is missing: "+tool)
    for test in args.test:
        if not re.fullmatch(r"tests/[A-Za-z0-9_]+\.gd",test) or not (source/"app"/test).is_file():parser.error("Unknown app test")
    try:
        app=make_fixtures(source,output,bundled_samples=not args.music_free)
        logs=output/"logs";logs.mkdir();native=app/"native/bin";native.mkdir(parents=True,exist_ok=True)
        env=dict(os.environ,METHEXIS_SOURCE_TEST="1",XDG_DATA_HOME=str(output/"user-data"),XDG_CONFIG_HOME=str(output/"config"),XDG_CACHE_HOME=str(output/"cache"))
        for name in ["user-data","config","cache"]:(output/name).mkdir()
        binary=native/"libtegra_godot_x11.so"
        run([args.cc,"-std=c11","-O2","-fPIC","-fvisibility=hidden","-Wall","-Wextra","-Werror","-Wno-unused-function","-I"+str(source/"native"),"-I"+str(source/"native/vendor/godot-headers"),"-shared",*[source/"native"/name for name in SOURCES],"-o",binary,"-lm"],env,logs/"codec.log")
        wrapper=[]
        if not os.environ.get("DISPLAY"):
            if not shutil.which("xvfb-run"):raise RuntimeError("DISPLAY or xvfb-run is required")
            wrapper=["xvfb-run","-a"]
        base=[*wrapper,godot,"--path",app,"--audio-driver","Dummy"]
        import_assets(base,env,app,logs/"import.log")
        for test in args.test:
            # App settings written by one suite must not become another suite's
            # supposed cold-start state.
            test_state=output/"test-state"/Path(test).stem
            test_env=dict(env)
            for key,folder in [("XDG_DATA_HOME","data"),("XDG_CONFIG_HOME","config"),("XDG_CACHE_HOME","cache")]:
                directory=test_state/folder;directory.mkdir(parents=True,exist_ok=False)
                test_env[key]=str(directory)
            run([*base,"--script","res://"+test],test_env,logs/(Path(test).stem+".log"))
        record={"kind":"synthetic-host-preview","godot":version,"pillow":PIL.__version__,"ffmpeg":run(["ffmpeg","-version"],env).splitlines()[0],"compiler":run([args.cc,"--version"],env).splitlines()[0],"host_codec_sha256":hashlib.sha256(binary.read_bytes()).hexdigest(),"tests":args.test,"private_media_copied":False,"device_actions":False,"audio_driver":"Dummy","bundled_fixture_samples":not args.music_free,"isolated_state_per_test":True}
        (output/"preview-build.json").write_text(json.dumps(record,indent=2)+"\n")
        print("HOST_PREVIEW_READY="+str(app));print("HOST_PREVIEW_TESTS="+str(len(args.test)))
        if args.run:subprocess.run([*base],env=env,check=True)
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:parser.exit(1,str(error)+"\n")
if __name__=="__main__":main()
