#!/usr/bin/env python3
"""Build an isolated Android preview from explicit offline source/toolchain inputs.

The preview has its own package and generated development key. It never reads
production signing settings, copies owner media or operates a device.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,re,shlex,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[1]
PREVIEW_PACKAGE="org.kinegra.shieldamp.preview"
PRODUCTION_PACKAGE="org.local.tegramilkdrop"
PRODUCTION_CERT="83a4649776860037aea3a7800fa3c3b42742dff0ed680e3b0181b7ab8300f39e"
GODOT_AAR="8375005ada94c72d2a2608cc3c09a24a77cf640cde04126b43365faf6e4775a3"
GODOT_DEBUG_AAR="5028aa8bc8ae2f310dc8816d5682b1c3bc171bb2a8fe5b68456080ae5a8b3450"
DEPENDENCIES={"ArduinoJson":"ARDUINOJSON","IXWebSocket":"IXWEBSOCKET","micro-flac":"MICRO_FLAC","noise-c":"NOISE_C"}
PATHS=("godot","godot_aar","godot_debug_aar","godot_templates","android_template","android_sdk","ndk","jdk","gradle","gradle_user_home","sendspin_checkout")

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(args,env=None,log=None,timeout=600):
    result=subprocess.run([str(x) for x in args],env=env,capture_output=True,text=True,timeout=timeout)
    output=result.stdout+result.stderr
    if log:Path(log).write_text(output)
    if result.returncode or "SCRIPT ERROR" in output or "Parse Error" in output:
        raise RuntimeError(Path(str(args[0])).name+" failed; see build logs")
    return output

def checkout(path,revision):
    actual=run(["git","-C",path,"rev-parse","HEAD"]).strip()
    if actual!=revision or run(["git","-C",path,"status","--porcelain"]).strip():
        raise ValueError("A dependency checkout is dirty or differs from its revision pin")
    return actual

def load_config(path,source):
    path=Path(path).resolve();data=json.loads(path.read_text())
    unknown=set(data)-set(PATHS)-{"dependency_sources","android_build_tools","android_platform"}
    if unknown:raise ValueError("Unknown preview configuration fields: "+", ".join(sorted(unknown)))
    def resolve(value):
        result=Path(os.path.expandvars(str(value))).expanduser()
        return (path.parent/result).resolve() if not result.is_absolute() else result.resolve()
    cfg={key:resolve(data[key]) for key in PATHS}
    cfg["dependency_sources"]={name:resolve(data["dependency_sources"][name]) for name in DEPENDENCIES}
    cfg["android_build_tools"]=str(data.get("android_build_tools","36.1.0"))
    cfg["android_platform"]=str(data.get("android_platform","36"))
    for key in PATHS:
        if not cfg[key].exists():raise ValueError("Missing configured input: "+key)
    if not run([cfg["godot"],"--version"]).startswith("3.6.3."):raise ValueError("Godot 3.6.3 is required")
    if digest(cfg["godot_aar"])!=GODOT_AAR or digest(cfg["godot_debug_aar"])!=GODOT_DEBUG_AAR:
        raise ValueError("Godot 3.6.3 AAR hash mismatch")
    sdk=cfg["android_sdk"];tools=sdk/"build-tools"/cfg["android_build_tools"]
    for name in ["aapt","apksigner","zipalign","dexdump"]:
        if not (tools/name).is_file():raise ValueError("Missing Android build tool: "+name)
    if not (sdk/"platforms"/("android-"+cfg["android_platform"])/"android.jar").is_file():raise ValueError("Missing Android platform jar")
    for name in ["java","javac","keytool"]:
        if not (cfg["jdk"]/"bin"/name).is_file():raise ValueError("Missing JDK tool: "+name)
    if not (cfg["ndk"]/"build/cmake/android.toolchain.cmake").is_file():raise ValueError("Missing NDK CMake toolchain")
    for name in ["android_debug.apk","android_release.apk"]:
        if not (cfg["godot_templates"]/name).is_file():raise ValueError("Missing Godot export template: "+name)
    for name in ["config.gradle","build.gradle","AndroidManifest.xml"]:
        if not (cfg["android_template"]/name).is_file():raise ValueError("Missing Godot custom-build source: "+name)
    lock=json.loads((source/"review/dependencies.lock.json").read_text())
    pins={item["name"]:item["revision"] for item in lock["external"]}
    checkout(cfg["sendspin_checkout"],pins["sendspin-cpp"])
    for name,path in cfg["dependency_sources"].items():checkout(path,pins[name])
    checkout(cfg["dependency_sources"]["micro-flac"]/"lib/micro-ogg-demuxer",pins["micro-ogg-demuxer"])
    return cfg,pins

def stage_template(source,app,cfg):
    target=app/"android/build"
    def ignore(directory,names):
        excluded={name for name in names if name in {"assets",".gradle","build","libs","local.properties","gradle.properties","gradlew","gradlew.bat"}}
        excluded.update(name for name in names if Path(name).suffix in {".so",".apk",".aar",".keystore",".jks"})
        for name in names:
            if name not in excluded and (Path(directory)/name).is_symlink():raise ValueError("Android template sources must not contain symlinks")
        return excluded
    shutil.copytree(cfg["android_template"],target,ignore=ignore)
    (target/".gdignore").write_text("")
    (target/"gradle.properties").write_text("android.enableJetifier=true\nandroid.useAndroidX=true\norg.gradle.jvmargs=-Xmx2048m\nandroid.enableResourceOptimizations=true\nandroid.overridePathCheck=true\n")
    (app/"android/.build_version").write_text("3.6.3.stable\n")
    libs=target/"libs/debug";libs.mkdir(parents=True)
    shutil.copyfile(cfg["godot_debug_aar"],libs/"godot-lib.debug.aar")
    wrapper=target/"gradlew";wrapper.write_text("#!/bin/sh\nexec "+shlex.quote(str(cfg["gradle"]))+' -Duser.home='+shlex.quote(str(app.parent/'java-home'))+' --offline --no-daemon "$@"\n');wrapper.chmod(0o700)
    plugins=app/"android/plugins";plugins.mkdir()
    shutil.copyfile(source/"android_secure_storage/ShieldAmpTokenStore.gdap",plugins/"ShieldAmpTokenStore.gdap")
    return target,plugins

def stage_build_sdk(sdk,output):
    # Godot polls adb while importing/exporting. Provide a build-only SDK view
    # so an export cannot start, kill or contact the owner's real adb server.
    target=output/"android-sdk";target.mkdir()
    for path in sdk.iterdir():
        if path.name!="platform-tools":(target/path.name).symlink_to(path,target_is_directory=path.is_dir())
    platform=target/"platform-tools";platform.mkdir()
    if (sdk/"platform-tools").is_dir():
        for path in (sdk/"platform-tools").iterdir():
            if path.name!="adb":(platform/path.name).symlink_to(path,target_is_directory=path.is_dir())
    adb=platform/"adb"
    adb.write_text('#!/bin/sh\ncase "$1" in\nversion|--version) printf "Android Debug Bridge version 1.0.41\\nShieldAmp build-only stub\\n";;\ndevices) printf "List of devices attached\\n\\n";;\n*) printf "Kinegra Amp source build forbids device operations\\n" >&2; exit 1;;\nesac\n')
    adb.chmod(0o700)
    return target

def export_preset(app,source):
    project=(app/"project.godot").read_text()
    version=re.search(r'^config/version="([^"\n]+)"',project,re.M)
    original=(source/"app/export_presets.cfg").read_text()
    code=re.search(r'^version/code=(\d+)$',original,re.M)
    if not version or not code:raise ValueError("Source version pins are missing")
    version=version[1]+"-preview";code=int(code[1])
    project=re.sub(r'^config/name="[^"\n]+"','config/name="Kinegra Amp Preview"',project,flags=re.M)
    project=re.sub(r'^config/version="[^"\n]+"','config/version="'+version+'"',project,flags=re.M)
    (app/"project.godot").write_text(project)
    preset="""[preset.0]
name="Android"
platform="Android"
runnable=true
custom_features=""
export_filter="all_resources"
include_filter="assets/original/*.bin,assets/notices/*"
exclude_filter="tests/*,*.md,**/*.md"
export_path="build/KinegraAmp-Preview.apk"
script_export_mode=1
script_encryption_key=""

[preset.0.options]
package/unique_name="{package}"
package/name="Kinegra Amp Preview"
package/signed=false
version/code={code}
version/name="{version}"
custom_build/use_custom_build=true
custom_build/min_sdk=26
custom_build/target_sdk=36
plugins/ShieldAmpTokenStore=true
launcher_icons/main_192x192="res://assets/branding/icon_192.png"
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
permissions/internet=true
package/allow_http=true
screen/immersive_mode=true
""".format(package=PREVIEW_PACKAGE,code=code,version=version)
    (app/"export_presets.cfg").write_text(preset)
    return version,code


def build(source,output,cfg,pins):
    sys.path.insert(0,str(source/"review"))
    from make_fixtures import make_fixtures
    app=make_fixtures(source,output)
    logs=output/"logs";logs.mkdir();state=output/"state"
    build_sdk=stage_build_sdk(cfg["android_sdk"],output)
    env=dict(os.environ,JAVA_HOME=str(cfg["jdk"]),ANDROID_SDK_ROOT=str(build_sdk),ANDROID_NDK_ROOT=str(cfg["ndk"]),GRADLE_USER_HOME=str(cfg["gradle_user_home"]),ANDROID_USER_HOME=str(output/"android-user"),XDG_CONFIG_HOME=str(state/"config"),XDG_DATA_HOME=str(state/"data"),XDG_CACHE_HOME=str(state/"cache"),TMPDIR=str(output/"tmp"),SHIELDAMP_PREVIEW_PASSWORD="android")
    env["PATH"]=str(cfg["jdk"]/"bin")+os.pathsep+env.get("PATH","")
    for path in [state/"config/godot",state/"data/godot/templates",state/"cache",output/"tmp"]:path.mkdir(parents=True,exist_ok=True)
    (state/"data/godot/templates/3.6.3.stable").symlink_to(cfg["godot_templates"],target_is_directory=True)
    _,plugins=stage_template(source,app,cfg)
    version,code=export_preset(app,source)
    native=app/"native/bin";native.mkdir(parents=True,exist_ok=True)
    compiler=cfg["ndk"]/"toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
    run([compiler,"-std=c11","-O2","-fPIC","-fvisibility=hidden","-Wall","-Wextra","-Werror","-Wno-unused-function","-I"+str(source/"native"),"-I"+str(source/"native/vendor/godot-headers"),"-shared",*[source/"native"/n for n in ("godot_codec.c","tegra_codec.c","minimp3_impl.c","stb_vorbis_impl.c")],"-Wl,-z,max-page-size=16384","-Wl,-z,common-page-size=16384","-o",native/"libtegra_godot_arm64.so","-lm"],env,logs/"codec.log")
    cmake=["-DBUILD_EXAMPLES=OFF","-DSENDSPIN_ENABLE_MESSAGE_TRACE=ON","-DSENDSPIN_BUILD_TESTS=OFF","-DSENDSPIN_USE_CCACHE=OFF","-DCMAKE_BUILD_TYPE=Release","-DFETCHCONTENT_FULLY_DISCONNECTED=ON"]
    for name,var in DEPENDENCIES.items():cmake.append("-DFETCHCONTENT_SOURCE_DIR_"+var+"="+str(cfg["dependency_sources"][name]))
    sdk_build=output/"sendspin-build"
    run(["bash",source/"native/build_sendspin_android.sh",cfg["sendspin_checkout"],cfg["ndk"],sdk_build,*cmake],env,logs/"sendspin-sdk.log")
    run(["bash",source/"native/build_sendspin_adapter.sh","android",cfg["sendspin_checkout"],sdk_build/"sdk-patched",sdk_build,native/"libshield_sendspin_arm64.so"],env,logs/"sendspin-adapter.log")
    for name in ("ShieldSendspin.gdns","ShieldSendspin.gdnlib"):shutil.copyfile(source/"native/sendspin_assets"/name,app/"native"/name)
    # This project is Android-only: no desktop binary is needed by its resources.
    for name in ("TegraCodec.gdnlib","ShieldSendspin.gdnlib"):
        path=app/"native"/name;text=path.read_text();text=re.sub(r'(?m)^(?:X11|Server)\.64=.*\n?',"",text);path.write_text(text)
    run([sys.executable,source/"android_secure_storage/build_offline.py","--godot-aar",cfg["godot_aar"],"--android-jar",cfg["android_sdk"]/"platforms"/("android-"+cfg["android_platform"])/"android.jar","--javac",cfg["jdk"]/"bin/javac","--output",plugins/"ShieldAmpTokenStore.aar"],env,logs/"token-plugin.log")
    notices=app/"assets/notices";notices.mkdir()
    for original,name in [(source/"LICENSE","PROJECT-LICENSE.txt"),(source/"docs/THIRD-PARTY-NOTICES.md","THIRD-PARTY-NOTICES.txt"),(source/"native/vendor/STB-LICENSE.txt","STB-LICENSE.txt"),(source/"native/vendor/godot-headers/LICENSE.md","GODOT-HEADERS-LICENSE.txt"),(source/"app/assets/fonts/LICENSE.txt","FONT-LICENSE.txt")]:shutil.copyfile(original,notices/name)
    for original in (source/"review/licenses").glob("*.txt"):shutil.copyfile(original,notices/original.name)
    keys=output/"keys";keys.mkdir();key=keys/"preview.keystore"
    run([cfg["jdk"]/"bin/keytool","-genkeypair","-noprompt","-keystore",key,"-alias","androiddebugkey","-keyalg","RSA","-keysize","2048","-validity","3650","-dname","CN=Kinegra Amp Preview,O=Development","-storepass:env","SHIELDAMP_PREVIEW_PASSWORD","-keypass:env","SHIELDAMP_PREVIEW_PASSWORD"],env,logs/"preview-key.log")
    settings=state/"config/godot/editor_settings-3.tres"
    settings.write_text('[gd_resource type="EditorSettings" format=2]\n\n[resource]\n'+"\n".join("export/android/"+name+" = "+json.dumps(str(value)) for name,value in [("android_sdk_path",build_sdk),("debug_keystore",key),("debug_keystore_user","androiddebugkey"),("debug_keystore_pass","android")])+"\n");settings.chmod(0o600)
    wrapper=["xvfb-run","-a"] if not os.environ.get("DISPLAY") else []
    if wrapper and shutil.which("xvfb-run") is None:raise ValueError("DISPLAY or xvfb-run is required")
    base=output/"base.apk"
    run([*wrapper,cfg["godot"],"--path",app,"--editor","--quit"],env,logs/"import.log")
    run([*wrapper,cfg["godot"],"--path",app,"--export-debug","Android",base],env,logs/"export.log")
    spec=importlib.util.spec_from_file_location("production_checks",source/"packaging/android_checks.py");checks=importlib.util.module_from_spec(spec);spec.loader.exec_module(checks)
    tools=cfg["android_sdk"]/"build-tools"/cfg["android_build_tools"]
    checks.validate_token_export_config((app/"export_presets.cfg").read_text());checks.validate_sendspin_min_sdk((app/"export_presets.cfg").read_text())
    native_hash=checks.validate_sendspin_source(app);checks.validate_token_plugin_apk(base,tools,env);checks.validate_sendspin_apk(base,native_hash)
    raw=output/"tv-unsigned.apk";aligned=output/"tv-aligned.apk"
    run([sys.executable,source/"packaging/patch_android_tv_manifest.py","--input",base,"--output",raw,"--icon",app/"assets/branding/icon_192.png","--banner",app/"assets/branding/tv_banner_320x180.png"],env,logs/"tv-manifest.log")
    run([tools/"zipalign","-f","-p","4",raw,aligned],env,logs/"align.log")
    apk=output/("KinegraAmp-"+version+".apk")
    run([tools/"apksigner","sign","--ks",key,"--ks-key-alias","androiddebugkey","--ks-pass","env:SHIELDAMP_PREVIEW_PASSWORD","--key-pass","env:SHIELDAMP_PREVIEW_PASSWORD","--out",apk,aligned],env,logs/"sign.log")
    certs=run([tools/"apksigner","verify","--print-certs",apk],env,logs/"signature.log")
    certificate=re.search(r"Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})",certs)
    if not certificate or certificate[1]==PRODUCTION_CERT:raise RuntimeError("Preview must not use the production signer")
    run([tools/"zipalign","-c","-p","4",apk],env)
    checks.validate_token_plugin_apk(apk,tools,env);checks.validate_sendspin_apk(apk,native_hash)
    badging=run([tools/"aapt","dump","badging",apk],env)
    if "name='"+PREVIEW_PACKAGE+"'" not in badging or "sdkVersion:'26'" not in badging or "leanback-launchable-activity:" not in badging or "banner=''" in badging:
        raise RuntimeError("Preview package, minimum SDK or TV launcher differs from its contract")
    import zipfile
    with zipfile.ZipFile(apk) as archive:
        names=archive.namelist()
        if any(name.startswith("lib/") and not name.startswith("lib/arm64-v8a/") for name in names):raise RuntimeError("Non-ARM64 library leaked into preview APK")
        if any("_x11.so" in name for name in names):raise RuntimeError("Host library leaked into preview APK")
        entry="lib/arm64-v8a/libtegra_godot_arm64.so"
        if names.count(entry)!=1 or hashlib.sha256(archive.read(entry)).hexdigest()!=digest(native/"libtegra_godot_arm64.so"):raise RuntimeError("Preview codec differs from compiled source artifact")
    for name,path in cfg["dependency_sources"].items():checkout(path,pins[name])
    record={"kind":"isolated-android-development-preview","package":PREVIEW_PACKAGE,"version":version,"code":code,"sha256":digest(apk),"certificate_sha256":certificate[1],"production_package_untouched":True,"production_signing_settings_read":False,"private_media_copied":False,"native_sendspin_sha256":native_hash,"codec_sha256":digest(native/"libtegra_godot_arm64.so"),"token_plugin_sha256":digest(plugins/"ShieldAmpTokenStore.aar"),"godot_release_aar_sha256":GODOT_AAR,"godot_debug_aar_sha256":GODOT_DEBUG_AAR,"external_source_revisions":{name:pins[name] for name in ["sendspin-cpp",*DEPENDENCIES,"micro-ogg-demuxer"]},"device_actions":False,"gradle_offline":True,"runtime_notice_scope":"Local development artifact; verify exact linked-runtime notices before redistribution"}
    (output/"preview-build.json").write_text(json.dumps(record,indent=2)+"\n")
    print("ANDROID_PREVIEW_APK="+str(apk));print("PREVIEW_PACKAGE="+PREVIEW_PACKAGE);print("APK_SHA256="+record["sha256"])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config",type=Path,required=True)
    parser.add_argument("--source",type=Path,default=ROOT)
    parser.add_argument("--output",type=Path)
    parser.add_argument("--check-inputs",action="store_true")
    args=parser.parse_args()
    try:
        source=args.source.resolve();cfg,pins=load_config(args.config,source)
        if args.check_inputs:print("ANDROID_PREVIEW_INPUTS_VERIFIED");return
        if args.output is None:parser.error("--output is required for a build")
        build(source,args.output.resolve(),cfg,pins)
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError) as error:parser.exit(1,str(error)+"\n")
if __name__=="__main__":main()
