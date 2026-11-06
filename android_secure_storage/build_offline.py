#!/usr/bin/env python3
"""Compile the Android plugin from explicit offline inputs. No device actions."""
from pathlib import Path
import argparse,hashlib,io,os,shutil,subprocess,tempfile
from zipfile import ZipFile,ZipInfo,ZIP_DEFLATED

ROOT=Path(__file__).resolve().parent
GODOT_AAR_SHA256="8375005ada94c72d2a2608cc3c09a24a77cf640cde04126b43365faf6e4775a3"

def build_plugin(engine,android,javac,target):
    engine,android,javac,target=map(lambda p:Path(p).resolve(),(engine,android,javac,target))
    if not all(p.is_file() for p in (engine,android,javac)):raise ValueError("Godot AAR, android.jar and javac must be existing files")
    if hashlib.sha256(engine.read_bytes()).hexdigest()!=GODOT_AAR_SHA256:raise ValueError("Godot 3.6.3 release AAR hash mismatch")
    if target.exists():raise ValueError("Refusing to overwrite an existing plugin artifact")
    java=javac.with_name("java")
    with tempfile.TemporaryDirectory(prefix="shieldamp-token-build-") as temp:
        work=Path(temp);classes=work/"classes";classes.mkdir()
        with ZipFile(engine) as aar:(work/"godot.jar").write_bytes(aar.read("classes.jar"))
        src=ROOT/"src/main/java/au/local/shieldamp"
        subprocess.run([str(javac),"--release","8","-cp",str(work/"godot.jar")+os.pathsep+str(android),"-d",str(classes),*[str(p) for p in sorted(src.glob("*.java"))]],check=True)
        host_tests=("TokenMigrationTest","TokenCredentialRecordTest","TokenForgetTest","SnapshotCommitTest","SelfTaskCleanerTest","OfflineFileImporterTest","OfflineImportSessionTest","OfflineLibraryAdmissionTest","OfflineCatalogSyntaxTest")
        subprocess.run([str(javac),"--release","8","-cp",str(classes),"-d",str(classes),*[str(ROOT/"tests"/(name+".java")) for name in host_tests]],check=True)
        for name in host_tests:subprocess.run([str(java),"-cp",str(classes),"au.local.shieldamp."+name],check=True)
        def add(archive,name,content):
            info=ZipInfo(name,(1980,1,1,0,0,0));info.external_attr=0o644<<16;info.compress_type=ZIP_DEFLATED;archive.writestr(info,content)
        jar=io.BytesIO()
        with ZipFile(jar,"w",ZIP_DEFLATED) as archive:
            for file in sorted(classes.rglob("*.class")):
                if "Test" not in file.name:add(archive,file.relative_to(classes).as_posix(),file.read_bytes())
        target.parent.mkdir(parents=True,exist_ok=True)
        with ZipFile(target,"w",ZIP_DEFLATED) as archive:
            add(archive,"AndroidManifest.xml",(ROOT/"src/main/AndroidManifest.xml").read_bytes())
            add(archive,"classes.jar",jar.getvalue());add(archive,"R.txt",b"")
    return hashlib.sha256(target.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-aar",type=Path,default=os.environ.get("GODOT_AAR"),required=not bool(os.environ.get("GODOT_AAR")))
    parser.add_argument("--android-jar",type=Path,default=os.environ.get("ANDROID_JAR"),required=not bool(os.environ.get("ANDROID_JAR")))
    default_javac=os.environ.get("JAVAC") or (str(Path(os.environ["JAVA_HOME"])/"bin/javac") if os.environ.get("JAVA_HOME") else shutil.which("javac"))
    parser.add_argument("--javac",type=Path,default=default_javac,required=not bool(default_javac))
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    try:digest=build_plugin(args.godot_aar,args.android_jar,args.javac,args.output)
    except (OSError,ValueError,subprocess.SubprocessError) as error:parser.exit(1,str(error)+"\n")
    print("ANDROID_PLUGIN_COMPILED="+str(args.output.resolve()));print("AAR_SHA256="+digest)
if __name__=="__main__":main()
