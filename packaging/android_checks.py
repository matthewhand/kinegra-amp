#!/usr/bin/env python3
"""Android package, secure-storage, native payload and alignment validation."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from release_gates import validate_release_manifest, validate_native_alignment, resolve_banner_resource
from arm_noise_gate import validate_arm_noise_proof
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PACKAGE = 'org.local.tegramilkdrop'
EXPECTED_CERT = '83a4649776860037aea3a7800fa3c3b42742dff0ed680e3b0181b7ab8300f39e'

def command(args, *, env=None, timeout=120):
    process = subprocess.run([str(x) for x in args], env=env, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
    if process.returncode:
        # Arguments may contain private local paths; never expose signing input.
        raise RuntimeError(Path(str(args[0])).name + ' failed: ' + (process.stdout + process.stderr)[-1800:])
    return process.stdout

# Guard the app's secure-token integration before any signing operation.
# The old prebuilt Android template silently omits Godot v1 plugins.
def validate_token_export_config(export):
    required=('custom_build/use_custom_build','plugins/ShieldAmpTokenStore')
    for name in required:
        values=re.findall(r'^\s*'+re.escape(name)+r'\s*=\s*([^\s#;]+)\s*$',export,re.M)
        if values!=['true']:
            raise RuntimeError('Secure token plugin requires unambiguous Android custom build and enabled ShieldAmpTokenStore; refusing to package a broken catalog')

def validate_token_manifest(text):
    blocks=re.split(r'(?m)^\s*E: ',text)
    matches=[b for b in blocks if b.startswith('meta-data ') and
             'org.godotengine.plugin.v1.ShieldAmpTokenStore' in b and
             'au.local.shieldamp.ShieldAmpTokenStore' in b]
    if len(matches)!=1:
        raise RuntimeError('Exported APK is missing unique secure-token plugin registration')

def validate_token_dex(dumps):
    blocks=[]
    for text in dumps:
        blocks.extend(re.split(r'(?m)^Class #\d+\s*-',text))
    target=[b for b in blocks if "Class descriptor  : 'Lau/local/shieldamp/ShieldAmpTokenStore;'" in b]
    if len(target)!=1 or "Superclass        : 'Lorg/godotengine/godot/plugin/GodotPlugin;'" not in target[0]:
        raise RuntimeError('Exported APK does not contain the expected Godot secure-token plugin')
    for method in ('loadTokenStaged','storageStatus','loadSendspinSnapshotBase64','replaceSendspinSnapshotBase64','sendspinSnapshotStatus','hasUsbWebcam','processCpuTimeMs','thermalStatus','loadTokenForEndpoint','storeTokenForEndpoint','tokenEndpoint','forgetToken','staleTaskPrunedCount','beginOfflineImport','offlineImportStatus','cancelOfflineImport'):
        if not re.search(r"name\s*:\s*'"+method+r"'",target[0]):
            raise RuntimeError('Exported APK is missing secure-token plugin method '+method)

    # Godot 3 JNI cannot dispatch Java long returns. Check the actual DEX
    # descriptors, not only method names, before any candidate can be signed.
    declarations=re.findall(r"(?m)^\s*name\s*:\s*'([^']+)'\s*\n\s*type\s*:\s*'([^']+)'",target[0])
    for method,signature in (("processCpuTimeMs","()Ljava/lang/String;"),("thermalStatus","()I"),("loadTokenForEndpoint","(Ljava/lang/String;)Ljava/lang/String;"),("storeTokenForEndpoint","(Ljava/lang/String;Ljava/lang/String;)Z"),("tokenEndpoint","()Ljava/lang/String;"),("forgetToken","()Z"),("staleTaskPrunedCount","()I"),("beginOfflineImport","(Ljava/lang/String;)Z"),("offlineImportStatus","()Ljava/lang/String;"),("cancelOfflineImport","()Z")):
        actual=[descriptor for name,descriptor in declarations if name==method]
        if actual!=[signature]:
            raise RuntimeError("Exported APK has incompatible Godot 3 metrics signature for "+method)

def validate_token_plugin_apk(apk,sdk,env):
    validate_token_manifest(command([sdk/'aapt','dump','xmltree',apk,'AndroidManifest.xml'],env=env))
    dumps=[]
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory(prefix='shieldamp-token-dex-') as temp:
        names=[n for n in archive.namelist() if re.fullmatch(r'classes(?:[2-9][0-9]*)?\.dex',n)]
        if not names or len(names)!=len(set(names)):
            raise RuntimeError('Exported APK has no unique DEX files')
        for name in names:
            info=archive.getinfo(name)
            if info.file_size>100*1024*1024:
                raise RuntimeError('Exported DEX file is unexpectedly large')
            path=Path(temp)/name;path.write_bytes(archive.read(name))
            result=subprocess.run([str(sdk/'dexdump'),'-f',str(path)],env=env,capture_output=True,timeout=120,check=False)
            if result.returncode!=0:
                raise RuntimeError('Could not inspect exported APK DEX')
            dumps.append(result.stdout.decode('utf-8',errors='replace'))
    validate_token_dex(dumps)

def validate_sendspin_min_sdk(export):
    # The staged Sendspin native library targets Android API 26.
    values = re.findall(r'^\s*custom_build/min_sdk\s*=\s*([^\s#;]+)\s*$', export, re.M)
    if len(values) != 1 or not values[0].isdigit() or int(values[0]) < 26:
        raise RuntimeError('Sendspin requires an unambiguous Android minimum SDK of at least 26')

def validate_sendspin_source(app):
    native=app/'native'
    gdns=native/'ShieldSendspin.gdns'
    gdnlib=native/'ShieldSendspin.gdnlib'
    library=native/'bin/libshield_sendspin_arm64.so'
    if not all(path.is_file() for path in (gdns,gdnlib,library)):
        raise RuntimeError('Sendspin descriptors or Android library missing; refusing broken TV player')
    if 'class_name="ShieldSendspin"' not in gdns.read_text() or 'res://native/ShieldSendspin.gdnlib' not in gdns.read_text():
        raise RuntimeError('Invalid Sendspin NativeScript descriptor')
    descriptor=gdnlib.read_text()
    if 'Android.arm64-v8a="res://native/bin/libshield_sendspin_arm64.so"' not in descriptor:
        raise RuntimeError('Sendspin NativeScript does not target Android ARM64')
    data=library.read_bytes()
    if len(data)<4096 or data[:6]!=b"\x7fELF\x02\x01" or data[18:20]!=b"\xb7\x00":
        raise RuntimeError('Sendspin library is not an ARM64 ELF')
    return hashlib.sha256(data).hexdigest()

def validate_sendspin_apk(apk,expected_hash):
    with zipfile.ZipFile(apk) as archive:
        names=archive.namelist()
        required=('assets/native/ShieldSendspin.gdns','assets/native/ShieldSendspin.gdnlib','lib/arm64-v8a/libshield_sendspin_arm64.so')
        if any(names.count(name)!=1 for name in required):
            raise RuntimeError('Exported APK is missing unique Sendspin resources')
        data=archive.read(required[2])
        if hashlib.sha256(data).hexdigest()!=expected_hash:
            raise RuntimeError('Exported Sendspin native library differs from staged artifact')
        if any('libshield_sendspin_x11' in name for name in names):
            raise RuntimeError('Desktop Sendspin library leaked into APK')

def validate_audio_engine(apk):
    record=json.loads((ROOT/'native/godot-opensl-runtime.json').read_text())
    with zipfile.ZipFile(apk) as archive:
        actual=hashlib.sha256(archive.read('lib/arm64-v8a/libgodot_android.so')).hexdigest()
    if actual!=record['arm64_sha256']:
        raise RuntimeError('Android audio engine does not match reviewed cleanup runtime')


def validate_native_source_paths(apk):
    """Reject local build/user directories in owned native libraries, including RTTI."""
    owned={'lib/arm64-v8a/libshield_sendspin_arm64.so','lib/arm64-v8a/libtegra_godot_arm64.so'}
    pattern=re.compile(rb'(?:/(?:home|Users)/[^/\x00\r\n\t ]+/|/(?:mnt)/(?:data|downloads)/|[A-Za-z]:\\Users\\[^\\\x00]+\\)')
    with zipfile.ZipFile(apk) as archive:
        for name in sorted(owned.intersection(archive.namelist())):
            if pattern.search(archive.read(name)):
                raise RuntimeError('Native source path is not portable: '+name)
