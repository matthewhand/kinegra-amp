#!/usr/bin/env python3
"""Create a fresh, silent-by-default source preview with synthetic media only."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
SOURCE_DIRS={"assets","native","scripts","shaders","tests"}
SOURCE_SUFFIXES={".godot",".tscn",".tres",".md"}
RUNTIME_DIRS={".import",".godot",".state","__pycache__","android","build","releases","user_data"}
RUNTIME_SUFFIXES={".cfg",".ini",".log",".db",".sqlite",".keystore",".jks",".p12",".pem",".so",".aar",".apk",".a"}

def source_files(source_root):
    # Git checkouts copy tracked files only. Source archives use the reviewed
    # manifest allowlist; no broad recursive fallback can import stray secrets.
    result=subprocess.run(["git","-C",str(source_root),"rev-parse","--show-toplevel"],capture_output=True,text=True) if shutil.which("git") else None
    if result is not None and result.returncode==0 and Path(result.stdout.strip()).resolve()==source_root:
        raw=subprocess.check_output(["git","-C",str(source_root),"ls-files","-z","--","app"])
        allowed={name.decode() for name in raw.split(b"\0") if name}
    else:
        manifest=source_root/"tools/SOURCE-MANIFEST.json"
        if not manifest.is_file():raise ValueError("Preview source needs a Git index or tools/SOURCE-MANIFEST.json allowlist")
        allowed=set(json.loads(manifest.read_text())["files"])
    allowed={name for name in allowed if name.startswith("app/")}
    if "app/project.godot" not in allowed:raise ValueError("Source allowlist is missing app/project.godot")
    if any(Path(name).is_absolute() or ".." in Path(name).parts for name in allowed):raise ValueError("Unsafe source allowlist path")
    return allowed

def generic_credit_replacements(source_root,allowed):
    """Only preview copies replace the four bundled titles and literal artist credit.

    Both legacy direct and conditional bundled/imported attribution are supported;
    runtime Music Assistant metadata and original source credits stay untouched.
    """
    source=Path(source_root)/"app"
    replacements={}
    offline=source/"scripts/OfflineMusic.gd"
    if "app/scripts/OfflineMusic.gd" in allowed:
        if offline.is_symlink():raise ValueError("Preview sources must not contain symlinks")
        match=re.search(r"(?m)^const TITLES\s*=\s*(\[.*\])\s*$",offline.read_text())
        if match is None:raise ValueError("Cannot derive generic sample labels from this source")
        titles=json.loads(match[1])
        if not isinstance(titles,list) or len(titles)!=4 or not all(isinstance(title,str) and title for title in titles):raise ValueError("Expected four source sample labels")
        replacements.update({title:"Review sample %d"%(i+1) for i,title in enumerate(titles)})
    stage=source/"scripts/MusicFirstUI.gd"
    if "app/scripts/MusicFirstUI.gd" in allowed:
        if stage.is_symlink():raise ValueError("Preview sources must not contain symlinks")
        for artist in re.findall(r'_set_fullscreen_track\((?:name|app\.offline_music\.current_title\(\)),\s*"([^"\n]+)"(?:\s+if\s+app\.offline_music\.track_index\s*<\s*4\s+else\s*"Imported audio")?,\s*"OFFLINE"\)',stage.read_text()):
            replacements[artist]="Synthetic sample artist"
    return replacements

def make_fixtures(source_root,output,bundled_samples=True):
    source_root=Path(source_root).resolve()
    source=(source_root/"app").resolve()
    output=Path(output).resolve()
    if not (source/"project.godot").is_file():raise ValueError("Source must contain app/project.godot")
    if output.exists() or output==source_root or output in source_root.parents or output.is_relative_to(source):
        raise ValueError("Choose a new output directory outside the source app")
    allowed=source_files(source_root)
    def ignore(directory,names):
        directory=Path(directory)
        relative=directory.relative_to(source)
        excluded=set()
        for name in names:
            path=directory/name
            if name in RUNTIME_DIRS or path.suffix.lower() in RUNTIME_SUFFIXES or name.endswith(".import"):
                excluded.add(name);continue
            if relative==Path(".") and name not in SOURCE_DIRS and path.suffix not in SOURCE_SUFFIXES:
                excluded.add(name);continue
            if (relative==Path("assets") and name=="music") or (relative==Path("native") and name=="bin"):
                excluded.add(name);continue
            source_name="app/"+path.relative_to(source).as_posix()
            permitted=source_name in allowed or (path.is_dir() and any(name.startswith(source_name+"/") for name in allowed))
            if not permitted:excluded.add(name);continue
            if path.is_symlink():raise ValueError("Preview sources must not contain symlinks")
        return excluded
    # Derive generic labels before creating output, and transform code while it
    # is copied so a failed import never leaves an unsanitized code copy.
    replacements=generic_credit_replacements(source_root,allowed) if bundled_samples else {}
    def copy_source(original,target):
        if Path(original).suffix==".gd":
            text=Path(original).read_text()
            for owner_label,generic in replacements.items():text=text.replace(owner_label,generic)
            Path(target).write_text(text);shutil.copystat(original,target)
            return target
        return shutil.copy2(original,target)
    shutil.copytree(source,output/"app",ignore=ignore,copy_function=copy_source)
    app=output/"app"
    # Generated samples exist only in this disposable host/developer fixture.
    # The production source has no bundled song paths and no unavailable loads.
    offline=app/"scripts/OfflineMusic.gd"
    text=offline.read_text()
    if bundled_samples and re.search(r"(?m)^const SOURCES = \[\]$",text):
        sources=["res://assets/music/track_%02d.ogg"%i for i in range(1,5)]
        text=re.sub(r"(?m)^const SOURCES = \[\]$","const SOURCES = "+json.dumps(sources),text)
        offline.write_text(text)
    stage=app/"scripts/MusicFirstUI.gd"
    text=stage.read_text()
    if bundled_samples and re.search(r"(?m)^const TRACK_COVERS = \[\]$",text):
        covers=["res://assets/music/artwork/track_%02d.jpg"%i for i in range(1,5)]
        text=re.sub(r"(?m)^const TRACK_COVERS = \[\]$","const TRACK_COVERS = "+json.dumps(covers),text)
        stage.write_text(text)
    music=app/"assets/music";artwork=music/"artwork";artwork.mkdir(parents=True)
    font_path=app/"assets/fonts/DejaVuSans.ttf"
    font=ImageFont.truetype(str(font_path),22) if font_path.is_file() else ImageFont.load_default()
    tracks=[]
    for i in range(1,5):
        target=music/("track_%02d.ogg"%i)
        subprocess.run(["ffmpeg","-nostdin","-hide_banner","-loglevel","error","-f","lavfi","-i","sine=frequency=%d:duration=12"%(220+110*i),"-fflags","+bitexact","-ar","48000","-ac","2","-c:a","libvorbis","-flags:a","+bitexact","-map_metadata","-1","-metadata","title=REVIEW TEST TONE %d"%i,str(target)],check=True)
        image=Image.new("RGB",(400,400),(16,35,50));draw=ImageDraw.Draw(image)
        draw.rectangle((20,20,380,380),outline=(100,230,205),width=6)
        draw.text((40,160),"REVIEW TEST",font=font,fill="white")
        draw.text((40,195),"TONE %d"%i,font=font,fill="white")
        image.save(artwork/("track_%02d.jpg"%i),quality=90)
        tracks.append({"title":"Review sample %d"%i,"output":"assets/music/"+target.name,"fixture":True,"sha256":hashlib.sha256(target.read_bytes()).hexdigest()})
    (music/"manifest.json").write_text(json.dumps({"fixture":True,"rights":"Synthetic test tones and code-drawn placeholders; not the separately licensed soundtrack","tracks":tracks},indent=2)+"\n")
    return app

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--source",default=ROOT,type=Path)
    args=parser.parse_args()
    try:app=make_fixtures(args.source,args.output)
    except (ValueError,OSError) as error:parser.error(str(error))
    print("NEW_SYNTHETIC_REVIEW_APP="+str(app))
if __name__=="__main__":main()
