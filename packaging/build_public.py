#!/usr/bin/env python3
"""Build a music-free, unsigned Android release from explicit public inputs.

No signing keys, owner media, production settings or device operations are used.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, io, json, os, re, shutil, signal, subprocess, sys, tarfile, tempfile, zipfile
import build_preview as preview
import android_checks as checks
from release_gates import validate_release_manifest, validate_native_alignment, resolve_banner_resource

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'org.local.tegramilkdrop'
def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(args, env, log, timeout=600):
    process = subprocess.Popen([str(x) for x in args], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        output = process.communicate(timeout=timeout)[0]
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGTERM)
        try: output=process.communicate(timeout=3)[0]
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL);output=process.communicate()[0]
        Path(log).write_text(output)
        raise RuntimeError(Path(str(args[0])).name+' timed out; see '+Path(log).name)
    Path(log).write_text(output)
    if process.returncode or 'SCRIPT ERROR' in output or 'Parse Error' in output:
        raise RuntimeError(Path(str(args[0])).name+' failed; see '+Path(log).name)
    return output

def config(path, source):
    path = path.resolve(); data = json.loads(path.read_text())
    engine = data.pop('godot_engine_library', None)
    if not engine: raise ValueError('godot_engine_library is required; build it with build_audio_engine.py')
    def absolute(value):
        p = Path(os.path.expandvars(str(value))).expanduser()
        return str((path.parent/p).resolve() if not p.is_absolute() else p.resolve())
    for key in preview.PATHS: data[key] = absolute(data[key])
    data['dependency_sources'] = {name:absolute(value) for name,value in data['dependency_sources'].items()}
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json') as stream:
        json.dump(data, stream); stream.flush()
        cfg, pins = preview.load_config(Path(stream.name), source)
    cfg['godot_engine_library'] = Path(absolute(engine))
    pin = json.loads((source/'native/godot-opensl-runtime.json').read_text())
    if digest(cfg['godot_engine_library']) != pin['arm64_sha256']:
        raise ValueError('Audio engine differs from the documented source build pin')
    return cfg,pins

def stage_app(source, out):
    if out.exists(): raise ValueError('Output directory must be new')
    out.mkdir(mode=0o700, parents=True)
    allowed = subprocess.check_output(['git','-C',str(source),'ls-files','-z','--','app']).decode().split('\0')
    app = out/'app'; app.mkdir()
    for name in filter(None,allowed):
        relative = Path(name).relative_to('app')
        if any(x in {'.import','.godot','android','build','tests','music'} for x in relative.parts): continue
        if len(relative.parts)==1 and relative.name not in {'Main.tscn','project.godot','export_presets.cfg'}: continue
        if len(relative.parts)>1 and relative.parts[0] not in {'scripts','native','assets','shaders'}: continue
        if relative.parts[0]=='assets' and relative.parts[1] not in {'icons','branding','original','fonts','notices'}: continue
        if relative.parts[:2] == ('native','bin') or relative.suffix in {'.so','.aar','.keystore','.jks'}: continue
        original = source/name
        if original.is_symlink(): raise ValueError('Source symlinks are not accepted')
        target = app/relative; target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(original,target)
    if not re.search(r'(?m)^const SOURCES = \[\]$',(app/'scripts/OfflineMusic.gd').read_text()):
        raise ValueError('Public runtime must have no bundled music sources')
    if not re.search(r'(?m)^const TRACK_COVERS = \[\]$',(app/'scripts/MusicFirstUI.gd').read_text()):
        raise ValueError('Public runtime must have no bundled cover paths')
    if (app/'assets/music').exists(): raise ValueError('Music folder leaked into the public stage')
    return app

def stage_release_aar(cfg, app, source):
    template, plugins = preview.stage_template(source,app,cfg)
    shutil.rmtree(template/'libs/debug')
    release = template/'libs/release'; release.mkdir(parents=True)
    target = release/'godot-lib.release.aar'
    with zipfile.ZipFile(cfg['godot_aar']) as original, zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED) as output:
        for entry in original.infolist():
            data = cfg['godot_engine_library'].read_bytes() if entry.filename == 'jni/arm64-v8a/libgodot_android.so' else original.read(entry)
            output.writestr(entry,data)
    return template,plugins

def preset(source, app):
    version = re.search(r'(?m)^config/version="([^"\n]+)"',(app/'project.godot').read_text())[1]
    code = int(re.search(r'(?m)^version/code=(\d+)$',(source/'app/export_presets.cfg').read_text())[1])
    original = source/'app/export_presets.cfg'
    text = original.read_text().split('[preset.0.options]')[0]
    text = re.sub(r'(?m)^custom_features=.*$', 'custom_features="shieldamp_production"', text)
    text = re.sub(r'(?m)^include_filter=.*$', 'include_filter="assets/original/*.bin,assets/notices/*"',text)
    text = re.sub(r'(?m)^exclude_filter=.*$', 'exclude_filter="tests/*,*.md,**/*.md"',text)
    text += '''[preset.0.options]
package/unique_name="org.local.tegramilkdrop"
package/name="Kinegra Amp"
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
'''.format(code=code,version=version)
    (app/'export_presets.cfg').write_text(text)
    return version,code

def build(source,out,cfg,pins):
    app = stage_app(source,out); logs=out/'logs'; logs.mkdir(); state=out/'state'
    sdk = preview.stage_build_sdk(cfg['android_sdk'],out)
    env = dict(os.environ, JAVA_HOME=str(cfg['jdk']), ANDROID_SDK_ROOT=str(sdk), ANDROID_NDK_ROOT=str(cfg['ndk']),
               GRADLE_USER_HOME=str(cfg['gradle_user_home']), ANDROID_USER_HOME=str(out/'android-user'),
               XDG_CONFIG_HOME=str(state/'config'), XDG_DATA_HOME=str(state/'data'), XDG_CACHE_HOME=str(state/'cache'),
               TMPDIR=str(out/'tmp'), LP_NUM_THREADS='2', KINEGRA_PORTABLE_BUILD='1')
    env['PATH'] = str(cfg['jdk']/'bin')+os.pathsep+env.get('PATH','')
    for path in [state/'config/godot',state/'data/godot/templates',state/'cache',out/'tmp']:path.mkdir(parents=True,exist_ok=True)
    (state/'data/godot/templates/3.6.3.stable').symlink_to(cfg['godot_templates'],target_is_directory=True)
    template,plugins=stage_release_aar(cfg,app,source)
    version,code=preset(source,app)
    native=app/'native/bin'; native.mkdir(parents=True)
    cc=cfg['ndk']/'toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang'
    run([cc,'-std=c11','-O2','-fPIC','-fvisibility=hidden','-Wall','-Wextra','-Werror','-Wno-unused-function',
         '-I'+str(source/'native'),'-I'+str(source/'native/vendor/godot-headers'),'-ffile-prefix-map='+str(source)+'=/src/shieldamp','-shared',
         *[source/'native'/name for name in ['godot_codec.c','tegra_codec.c','minimp3_impl.c','stb_vorbis_impl.c']],
         '-Wl,-z,max-page-size=16384','-Wl,-z,common-page-size=16384','-o',native/'libtegra_godot_arm64.so','-lm'],env,logs/'codec.log')
    cmake=['-DBUILD_EXAMPLES=OFF','-DSENDSPIN_ENABLE_MESSAGE_TRACE=ON','-DSENDSPIN_BUILD_TESTS=OFF','-DSENDSPIN_USE_CCACHE=OFF','-DCMAKE_BUILD_TYPE=Release','-DFETCHCONTENT_FULLY_DISCONNECTED=ON']
    # Clang can retain lambda source names outside file-prefix maps. A line
    # directive changes only the diagnostic/RTTI filename in a fresh export.
    ix=out/'portable-ixwebsocket';ix.mkdir()
    data=subprocess.check_output(['git','-C',str(cfg['dependency_sources']['IXWebSocket']),'archive','HEAD'])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
            if member.issym() or member.islnk():
                target=os.path.normpath(str(Path(member.name).parent/member.linkname))
                assert not Path(member.linkname).is_absolute() and not target.startswith('../')
        archive.extractall(ix,filter='data')
    run(['patch','--batch','-p1','-d',ix,'-i',source/'native/ixwebsocket-source-path.patch'],env,logs/'portable-source.log')
    for name,var in preview.DEPENDENCIES.items():
        path=ix if name=='IXWebSocket' else cfg['dependency_sources'][name]
        cmake.append('-DFETCHCONTENT_SOURCE_DIR_'+var+'='+str(path))
    maps=["-ffile-prefix-map="+str(source)+"=/src/shieldamp","-ffile-prefix-map="+str(out)+"=/build/shieldamp","-ffile-prefix-map="+str(cfg["ndk"])+"=/toolchain/android-ndk"]
    maps += ["-ffile-prefix-map="+str(path)+"=/src/"+name for name,path in cfg["dependency_sources"].items()]
    cmake += ["-DCMAKE_C_FLAGS="+" ".join(maps),"-DCMAKE_CXX_FLAGS="+" ".join(maps)]
    sdk_build=out/'sendspin-build'
    run(['bash',source/'native/build_sendspin_android.sh',cfg['sendspin_checkout'],cfg['ndk'],sdk_build,*cmake],env,logs/'sendspin-sdk.log')
    run(['bash',source/'native/build_sendspin_adapter.sh','android',cfg['sendspin_checkout'],sdk_build/'sdk-patched',sdk_build,native/'libshield_sendspin_arm64.so'],env,logs/'sendspin-adapter.log')
    for name in ['ShieldSendspin.gdns','ShieldSendspin.gdnlib']:shutil.copyfile(source/'native/sendspin_assets'/name,app/'native'/name)
    for name in ['TegraCodec.gdnlib','ShieldSendspin.gdnlib']:
        path=app/'native'/name;path.write_text(re.sub(r'(?m)^(?:X11|Server)\.64=.*\n?','',path.read_text()))
    run([sys.executable,source/'android_secure_storage/build_offline.py','--godot-aar',cfg['godot_aar'],
         '--android-jar',cfg['android_sdk']/'platforms'/('android-'+cfg['android_platform'])/'android.jar',
         '--javac',cfg['jdk']/'bin/javac','--output',plugins/'ShieldAmpTokenStore.aar'],env,logs/'token-plugin.log')
    # Godot validates a debug-keystore setting even for an unsigned release.
    # Create a disposable tool-only key; package/signed=false prevents its use.
    validation_key=out/'validation-key.keystore'
    env['KINEGRA_VALIDATION_KEY_PASSWORD']='android'
    run([cfg['jdk']/'bin/keytool','-genkeypair','-noprompt','-keystore',validation_key,
         '-alias','androiddebugkey','-keyalg','RSA','-keysize','2048','-validity','30',
         '-dname','CN=Build Validation,O=Kinegra','-storepass:env','KINEGRA_VALIDATION_KEY_PASSWORD',
         '-keypass:env','KINEGRA_VALIDATION_KEY_PASSWORD'],env,logs/'validation-key.log')
    validation_key.chmod(0o600)
    settings=state/'config/godot/editor_settings-3.tres'
    values=[('android_sdk_path',sdk),('debug_keystore',validation_key),('debug_keystore_user','androiddebugkey'),('debug_keystore_pass','android')]
    settings.write_text('[gd_resource type="EditorSettings" format=2]\n\n[resource]\n'+"\n".join('export/android/'+name+' = '+json.dumps(str(value)) for name,value in values)+'\n')
    settings.chmod(0o600)
    # Runtime dependency resolution supplies the exact notice inventory before export.
    graph=out/'gradle-runtime-graph.json'
    run([cfg['gradle'],'--offline','--no-daemon','-p',template,'-I',source/'packaging/runtime_inventory.gradle',
         '-Dkinegra.inventory='+str(graph),'kinegraRuntimeInventory'],env,logs/'gradle-runtime.log')
    from assemble_notices import assemble
    inventory=assemble(source,app,cfg,graph,native)
    wrapper=['xvfb-run','-a'] if not os.environ.get('DISPLAY') else []
    sys.path.insert(0,str(source/'tools'))
    spec=importlib.util.spec_from_file_location('host_import_gate',source/'tools/build_preview.py')
    host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)
    import_assets=host.import_assets
    # Import art in a minimal host project. Android-only GDNative descriptors
    # are not Linux editor libraries; they are validated in the actual APK.
    art_project=out/'asset-import';art_project.mkdir()
    shutil.copytree(app/'assets',art_project/'assets')
    (art_project/'project.godot').write_text('config_version=4\n[rendering]\nquality/driver/driver_name="GLES2"\n')
    assets=sorted(p for p in (art_project/'assets').rglob('*') if p.is_file() and p.suffix.lower() in {'.png','.jpg','.jpeg','.svg','.ogg','.mp3'})
    import_assets([*wrapper,cfg['godot'],'--path',art_project,'--audio-driver','Dummy'],env,art_project,logs/'import.log',assets=assets)
    shutil.copytree(art_project/'.import',app/'.import')
    for path in (art_project/'assets').rglob('*.import'):
        target=app/'assets'/path.relative_to(art_project/'assets')
        shutil.copyfile(path,target)
    base=out/'base-unsigned.apk'
    export_log=run([*wrapper,cfg['godot'],'--path',app,'--export','Android',base],env,logs/'export.log')
    errors=[line for line in export_log.splitlines() if line.startswith('ERROR:')]
    assert all(line=='ERROR:  does not have a library for the current platform.' for line in errors), 'Unexpected Android export error'
    tools=cfg['android_sdk']/'build-tools'/cfg['android_build_tools']
    checks.validate_token_export_config((app/'export_presets.cfg').read_text());checks.validate_sendspin_min_sdk((app/'export_presets.cfg').read_text())
    checks.validate_token_plugin_apk(base,tools,env)
    native_hash=checks.validate_sendspin_source(app);checks.validate_sendspin_apk(base,native_hash)
    banner=resolve_banner_resource(run([tools/'aapt','dump','--values','resources',base],env,logs/'resources.log'))
    raw=out/'tv-unsigned.apk'
    run([sys.executable,source/'packaging/patch_android_tv_manifest.py','--input',base,'--output',raw,
         '--icon',app/'assets/branding/icon_192.png','--banner',app/'assets/branding/tv_banner_320x180.png',
         '--release-safety','--banner-resource-path',banner],env,logs/'tv-manifest.log')
    apk=out/('KinegraAmp-'+version+'-code'+str(code)+'-MUSIC-FREE-UNSIGNED.apk')
    run([tools/'zipalign','-f','-P','16','4',raw,apk],env,logs/'align.log')
    xml=run([tools/'aapt','dump','xmltree',apk,'AndroidManifest.xml'],env,logs/'manifest.log')
    validate_release_manifest(xml);validate_native_alignment(apk);checks.validate_native_source_paths(apk)
    run([tools/'zipalign','-c','-P','16','4',apk],env,logs/'align-check.log')
    checks.validate_token_plugin_apk(apk,tools,env);checks.validate_sendspin_apk(apk,native_hash)
    signature=subprocess.run([str(tools/'apksigner'),'verify',str(apk)],env=env,capture_output=True,text=True)
    assert signature.returncode!=0, 'Public candidate must remain unsigned'
    badging=run([tools/'aapt','dump','badging',apk],env,logs/'badging.log')
    assert "name='"+PACKAGE+"'" in badging and "versionCode='"+str(code)+"'" in badging
    assert "sdkVersion:'26'" in badging and 'leanback-launchable-activity:' in badging
    with zipfile.ZipFile(apk) as archive:
        names=archive.namelist();assert len(names)==len(set(names)) and archive.testzip() is None
        assert not any('/music/' in name or name.endswith(('.oggstr','.mp3')) for name in names), 'Bundled music leaked'
        assert not any(name.startswith('META-INF/') and name.endswith(('.RSA','.DSA','.EC','.SF')) for name in names)
        for entry in inventory['notices']:
            path='assets/assets/notices/'+entry['file'];assert names.count(path)==1 and hashlib.sha256(archive.read(path)).hexdigest()==entry['sha256']
        libraries={name:hashlib.sha256(archive.read(name)).hexdigest() for name in names if name.startswith('lib/') and name.endswith('.so')}
    result={'kind':'music-free-unsigned-release-candidate','package':PACKAGE,'version':version,'code':code,
            'apk':str(apk),'sha256':digest(apk),'source_commit':subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip(),
            'music_included':False,'production_signing_inputs_read':False,'generated_validation_key_for_configuration_only':True,'signed':False,'device_actions':False,
            'native_libraries':libraries,'notices':len(inventory['notices']),'license_inventory_sha256':digest(app/'assets/notices/INDEX.json'),
            'gradle_offline':True,'sdk_source_pin':pins['sendspin-cpp'],'physical_acceptance':'Not exercised by this build'}
    (out/'public-build.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,required=True);parser.add_argument('--source',type=Path,default=ROOT)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    cfg,pins=config(args.config,args.source.resolve());build(args.source.resolve(),args.output.resolve(),cfg,pins)
if __name__=='__main__':main()
