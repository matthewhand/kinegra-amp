#!/usr/bin/env python3
"""Muted UI tests using generated silent audio/solid artwork in an isolated app copy."""
import pathlib, tempfile, shutil, subprocess, sys, os, signal, types, time, re
from PIL import Image
root=pathlib.Path(__file__).resolve().parents[2]
def run_fixture(args,env):
    process=subprocess.Popen(args,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
    try:output,_=process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL)
        output,_=process.communicate()
        print(output)
        raise
    return types.SimpleNamespace(returncode=process.returncode,stdout=output)
source=root/"app"
with tempfile.TemporaryDirectory(prefix="shieldamp-presentation-",dir=os.environ.get("SHIELDAMP_TEST_TMPDIR")) as folder:
    work=pathlib.Path(folder)
    def ignore(directory,names):
        path=pathlib.Path(directory)
        if path==source/"assets":return {"music"}&set(names)
        if path==source/".import":return {name for name in names if name.startswith("track_")}
        return set()
    shutil.copytree(source,work,dirs_exist_ok=True,ignore=ignore)
    music=work/"assets/music";art=music/"artwork";art.mkdir(parents=True)
    subprocess.run(["ffmpeg","-nostdin","-loglevel","error","-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-t","2","-c:a","libvorbis",str(music/"track_01.ogg")],check=True)
    for index in range(1,5):
        if index>1:shutil.copyfile(music/"track_01.ogg",music/f"track_{index:02d}.ogg")
        Image.new("RGB",(16,16),(30,80,120)).save(art/f"track_{index:02d}.jpg")
    native=work/"native/bin";native.mkdir(parents=True,exist_ok=True)
    subprocess.run(["cc","-std=c11","-O2","-fPIC","-fvisibility=hidden","-Wall","-Wextra","-Werror","-Wno-unused-function","-I"+str(root/"native"),"-I"+str(root/"native/vendor/godot-headers"),"-shared",*[str(root/"native"/name) for name in ("godot_codec.c","tegra_codec.c","minimp3_impl.c","stb_vorbis_impl.c")],"-o",str(native/"libtegra_godot_x11.so"),"-lm"],check=True)
    env=dict(os.environ,XDG_DATA_HOME=folder,METHEXIS_SOURCE_TEST="1")
    # --editor --quit exits after one iteration, sometimes before generated
    # fixture imports finish. Wait for their actual remapped cache files instead
    # of permitting null audio/artwork to make preload-based tests misleading.
    fixtures=[music/f"track_{i:02d}.ogg" for i in range(1,5)]+[art/f"track_{i:02d}.jpg" for i in range(1,5)]
    def fixtures_imported():
        for fixture in fixtures:
            metadata=pathlib.Path(str(fixture)+".import")
            if not metadata.is_file():return False
            target=re.search(r'^path="res://([^"\n]+)"$',metadata.read_text(),re.MULTILINE)
            if not target:return False
            cached=work/target.group(1)
            if not cached.is_file() or cached.stat().st_size==0:return False
        return True
    with tempfile.TemporaryFile(mode="w+t") as import_log:
        editor=subprocess.Popen(["xvfb-run","-a",sys.argv[1],"--path",folder,"--editor"],env=env,text=True,stdout=import_log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            deadline=time.monotonic()+30
            while editor.poll() is None and not fixtures_imported() and time.monotonic()<deadline:time.sleep(0.1)
            ready=fixtures_imported()
        finally:
            if editor.poll() is None:
                os.killpg(editor.pid,signal.SIGTERM)
                try:editor.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(editor.pid,signal.SIGKILL);editor.wait()
        import_log.seek(0)
        assert ready,"Synthetic fixture import did not finish: "+import_log.read()
    for name in sys.argv[2:] or ["test_presentation_metadata.gd"]:
        result=run_fixture(["xvfb-run","-a",sys.argv[1],"--path",folder,"--no-window","--script","res://tests/"+name],env)
        print(result.stdout)
        assert result.returncode==0 and "SCRIPT ERROR" not in result.stdout,(name,result.returncode)
print("SYNTHETIC_PRESENTATION_UI_PASS")
