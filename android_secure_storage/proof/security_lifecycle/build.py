#!/usr/bin/env python3
"""Offline standalone Android Keystore proof. Builds only; never operates a device."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,zipfile,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent
PLUGIN=ROOT.parents[1]
PACKAGE="local.shieldamp.securityproof20261103"
ACTIVITY="au.local.shieldamp.SecurityLifecycleProofActivity"
PRODUCTION_CERTS={"83a4649776860037aea3a7800fa3c3b42742dff0ed680e3b0181b7ab8300f39e","aaaa5b415884020e155a0cf2f14bf78e24d4f5b4d3e94d36e59036a7cd94fe81"}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def run(args,env,log):
    result=subprocess.run([str(x) for x in args],env=env,capture_output=True,text=True,timeout=120)
    log.write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError("Proof build step failed; see "+log.name)
    return result.stdout+result.stderr

def build(sdk,jar,jdk,output):
    if output.exists():raise ValueError("Choose a new output directory")
    for name in ("aapt","zipalign","apksigner","dexdump","lib/d8.jar"):
        if not (sdk/name).is_file():raise ValueError("Missing Android build input: "+name)
    for name in ("java","javac","keytool"):
        if not (jdk/"bin"/name).is_file():raise ValueError("Missing JDK tool: "+name)
    if not jar.is_file():raise ValueError("Missing android.jar")
    manifest=ET.parse(ROOT/"AndroidManifest.xml").getroot();ns="{http://schemas.android.com/apk/res/android}"
    app=manifest.find("application");activities=app.findall("activity")
    if manifest.attrib.get("package")!=PACKAGE or any("sharedUserId" in key for key in manifest.attrib) or manifest.findall("uses-permission") or len(activities)!=1:
        raise ValueError("Proof identity/permission boundary differs")
    activity=activities[0]
    if app.attrib.get(ns+"allowBackup")!="false" or app.attrib.get(ns+"debuggable")!="false" or activity.attrib.get(ns+"name")!=ACTIVITY or activity.attrib.get(ns+"excludeFromRecents")!="true" or activity.findall("intent-filter"):
        raise ValueError("Proof backup/debug/recents/launcher boundary differs")
    output.mkdir(parents=True,mode=0o700);logs=output/"logs";logs.mkdir();classes=output/"classes";classes.mkdir();dex=output/"dex";dex.mkdir();keys=output/"keys";keys.mkdir()
    env=dict(os.environ,JAVA_HOME=str(jdk),SHIELDAMP_PROOF_PASSWORD="android");env["PATH"]=str(jdk/"bin")+os.pathsep+env.get("PATH","")
    sources=sorted((PLUGIN/"src/main/java/au/local/shieldamp").glob("*.java"))+sorted((ROOT/"java").rglob("*.java"))+sorted((ROOT/"stubs").rglob("*.java"))
    before={str(p.relative_to(PLUGIN)):digest(p) for p in sources}
    run([jdk/"bin/javac","--release","8","-g:none","-cp",jar,"-d",classes,*sources],env,logs/"javac.log")
    classes_jar=output/"classes.jar"
    with zipfile.ZipFile(classes_jar,"w",zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(classes.rglob("*.class")):
            info=zipfile.ZipInfo(path.relative_to(classes).as_posix(),(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;archive.writestr(info,path.read_bytes())
    run([jdk/"bin/java","-cp",sdk/"lib/d8.jar","com.android.tools.r8.D8","--min-api","26","--lib",jar,"--output",dex,classes_jar],env,logs/"d8.log")
    unsigned=output/"unsigned.apk"
    run([sdk/"aapt","package","-f","-M",ROOT/"AndroidManifest.xml","-I",jar,"-F",unsigned],env,logs/"aapt.log")
    with zipfile.ZipFile(unsigned,"a",zipfile.ZIP_DEFLATED) as archive:archive.write(dex/"classes.dex","classes.dex")
    aligned=output/"aligned.apk"
    run([sdk/"zipalign","-f","-p","4",unsigned,aligned],env,logs/"align.log")
    key=keys/"synthetic-proof.keystore"
    run([jdk/"bin/keytool","-genkeypair","-noprompt","-keystore",key,"-alias","synthetic-proof","-keyalg","RSA","-keysize","2048","-validity","3650","-dname","CN=Synthetic Security Proof,O=Development","-storepass:env","SHIELDAMP_PROOF_PASSWORD","-keypass:env","SHIELDAMP_PROOF_PASSWORD"],env,logs/"key.log")
    apk=output/"Kinegra Amp-Synthetic-Security-Proof-20261103.apk"
    run([sdk/"apksigner","sign","--ks",key,"--ks-key-alias","synthetic-proof","--ks-pass","env:SHIELDAMP_PROOF_PASSWORD","--key-pass","env:SHIELDAMP_PROOF_PASSWORD","--out",apk,aligned],env,logs/"sign.log")
    certificate=run([sdk/"apksigner","verify","--verbose","--print-certs","--min-sdk-version","26",apk],env,logs/"signature.log")
    match=re.search(r"Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})",certificate)
    if not match or match[1] in PRODUCTION_CERTS:raise RuntimeError("Proof signer must be a separate development identity")
    run([sdk/"zipalign","-c","-p","4",apk],env,logs/"alignment-check.log")
    badging=run([sdk/"aapt","dump","badging",apk],env,logs/"badging.log")
    if "name='"+PACKAGE+"'" not in badging or "sdkVersion:'26'" not in badging or "application-debuggable" in badging or "launchable-activity:" in badging or "uses-permission:" in badging:
        raise RuntimeError("Built APK identity/permission/launcher boundary differs")
    permissions=run([sdk/"aapt","dump","permissions",apk],env,logs/"permissions.log")
    if "uses-permission" in permissions:raise RuntimeError("Proof APK must request no permissions")
    binary_manifest=run([sdk/"aapt","dump","xmltree",apk,"AndroidManifest.xml"],env,logs/"manifest.log")
    for field in ("allowBackup","debuggable"):
        if not re.search(r"android:"+field+r"[^\n]*0x0\b",binary_manifest):raise RuntimeError("Built proof backup/debug flag differs")
    if not re.search(r"android:excludeFromRecents[^\n]*0xffffffff",binary_manifest) or "sharedUserId" in binary_manifest or "android.intent.action.MAIN" in binary_manifest:
        raise RuntimeError("Built proof recents/shared-UID/entrypoint boundary differs")
    if before!={str(p.relative_to(PLUGIN)):digest(p) for p in sources}:raise RuntimeError("Production or proof sources changed during build")
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None or len(archive.namelist())!=len(set(archive.namelist())):raise RuntimeError("Invalid proof APK")
    record={"kind":"standalone-synthetic-android-keystore-proof","package":PACKAGE,"activity":ACTIVITY,"sha256":digest(apk),"certificate_sha256":match[1],"permissions":[],"launcher":False,"exclude_from_recents":True,"backup":False,"debuggable":False,"shared_uid":False,"uses_production_java_unchanged":True,"godot_jni_exercised":False,"platform_execution":"PENDING: builder does not install or run","source_sha256":before,"android_jar_sha256":digest(jar),"device_actions":False}
    (output/"proof-build.json").write_text(json.dumps(record,indent=2)+"\n")
    print("SYNTHETIC_PROOF_APK="+str(apk));print("APK_SHA256="+record["sha256"]);print("PACKAGE="+PACKAGE)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-tools",type=Path,required=True)
    parser.add_argument("--android-jar",type=Path,required=True)
    parser.add_argument("--jdk",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    try:build(args.build_tools.resolve(),args.android_jar.resolve(),args.jdk.resolve(),args.output.resolve())
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:parser.exit(1,str(error)+"\n")
if __name__=="__main__":main()
