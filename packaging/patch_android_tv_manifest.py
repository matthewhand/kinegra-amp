#!/usr/bin/env python3
"""Patch only an isolated Godot 3.6 Android *candidate* APK's binary manifest.

No source APK edits, no device operations, no network access.
Fail closed on format/schema mismatches. The Android TV banner aliases the
existing drawable/splash (id 0x7f06000c), with 320x180 art inserted at its
existing resource path. All values in the resource table remain valid.
"""
import argparse
import io
import pathlib
import struct
import zipfile
from PIL import Image, ImageDraw, ImageFont

ANDROID_NS="http://schemas.android.com/apk/res/android"
BANNER_RESOURCE_ID=0x7f06000c
ANDROID_BANNER_ATTR_ID=0x010103f2
ROOT_CHUNK=0x0003
STRING_POOL=0x0001
RESOURCE_MAP=0x0180
NS_START=0x0100
START=0x0102
END=0x0103

def unpack(fmt, buf, at): return struct.unpack_from(fmt,buf,at)
def chunk(t,header,body=b""):
    return struct.pack("<HHI",t,header,8+len(body)) + body
def xml_node(t, name,ns=0xffffffff,line=1):
    return struct.pack("<HHIIIII",t,16,24,line,0xffffffff,ns,name)
def xml_attr(ns,name,raw,data_type,data):
    return struct.pack("<IIIHBBI",ns,name,raw,8,0,data_type,data)
def start_element(name, attrs, ns=0xffffffff, line=1):
    body=struct.pack("<IIHHHHHH",ns,name,20,20,len(attrs),0,0,0)+b"".join(attrs)
    return struct.pack("<HHIII",START,16,16+len(body),line,0xffffffff)+body
def u16len(data, pos):
    n,=unpack("<H",data,pos)
    if n&0x8000:
        low,=unpack("<H",data,pos+2)
        return ((n&0x7fff)<<16)|low, pos+4
    return n,pos+2
def put_u16len(n):
    if n < 0x8000: return struct.pack("<H",n)
    return struct.pack("<HH",((n>>16)&0x7fff)|0x8000,n&0xffff)
def unpack_pool(old):
    kind,head,sz=unpack("<HHI",old,0)
    if kind != STRING_POOL or head !=28 or sz!=len(old): raise ValueError("unexpected string-pool")
    count,styles,flags,sstart,stylestart=unpack("<IIIII",old,8)
    if styles or stylestart or flags!=0: raise ValueError("unsupported utf8/styled string pool")
    offsets=list(unpack("<"+str(count)+"I",old,head))
    strings=[]
    for off in offsets:
        pos=sstart+off
        n,pos=u16len(old,pos)
        raw=old[pos:pos+n*2]
        if len(raw)!=n*2: raise ValueError("truncated utf16")
        strings.append(raw.decode("utf-16le"))
    payload=old[sstart:]
    return strings,offsets,payload

def rewrite_pool(old, strings, offsets, newvalues):
    strlist=list(strings)
    raw=bytearray(old[unpack("<I",old,20)[0]:])  # old stringsStart at offset 20
    for value in newvalues:
        if value not in strlist:
            offsets.append(len(raw))
            coded=value.encode("utf-16le")
            raw.extend(put_u16len(len(coded)//2)); raw.extend(coded);raw.extend(b"\0\0")
            strlist.append(value)
    while len(raw)%4:raw.append(0)
    payload=struct.pack("<IIIII",len(strlist),0,0,28+4*len(strlist),0)
    offsetdata=struct.pack("<"+str(len(offsets))+"I",*offsets)
    return chunk(STRING_POOL,28,payload+offsetdata+raw),strlist

def read_chunks(x):
    h,header,total=unpack("<HHI",x,0)
    if h!=ROOT_CHUNK or header!=8 or total!=len(x):raise ValueError("bad axml header")
    chunks=[]
    p=8
    while p<len(x):
        typ,hs,size=unpack("<HHI",x,p)
        if size<hs or size==0 or p+size>len(x):raise ValueError("bad axml chunk")
        chunks.append((typ,x[p:p+size]))
        p+=size
    return chunks

def attrs(chunkbytes, strings):
    start=16
    ns,tag,atstart,atsize,count,ididx,clsidx,styidx=unpack("<IIHHHHHH",chunkbytes,start)
    if atsize!=20 or atstart!=20:raise ValueError("nonstandard attr struct")
    result=[]
    for j in range(count):
        off=16+atstart+j*atsize
        a_ns,a_name,raw,sz,res,kind,data=unpack("<IIIHBBI",chunkbytes,off)
        result.append((strings[a_name],strings[raw] if raw!=0xffffffff else None,kind,data))
    return strings[tag],result,count

def insert_sorted_attribute(node, attribute, resource_ids):
    # Android's typed-attribute reader walks resource IDs in ascending order.
    # aapt's text dump can show an out-of-order attribute that PackageParser
    # silently ignores; banner must be placed before isGame/resizeableActivity.
    _,_,atstart,atsize,count,ididx,clsidx,styidx=unpack("<IIHHHHHH",node,16)
    if atstart!=20 or atsize!=20 or len(node)!=36+20*count:
        raise ValueError("unsupported attribute layout")
    entries=[node[36+20*i:56+20*i] for i in range(count)]
    entries.append(attribute)
    def key(entry):
        name=unpack("<I",entry,4)[0]
        if name>=len(resource_ids) or resource_ids[name]==0:
            raise ValueError("unmapped manifest attribute")
        return resource_ids[name]
    keys=[key(entry) for entry in entries]
    if len(set(keys))!=len(keys):raise ValueError("duplicate manifest attribute")
    order=sorted(range(len(entries)),key=lambda i:keys[i])
    header=bytearray(node[:36])
    struct.pack_into("<I",header,4,len(node)+20)
    struct.pack_into("<H",header,28,count+1)
    for offset,index in [(30,ididx),(32,clsidx),(34,styidx)]:
        struct.pack_into("<H",header,offset,order.index(index-1)+1 if index else 0)
    return bytes(header)+b"".join(entries[i] for i in order)

def modify_manifest(axml, release=False):
    parts=read_chunks(axml)
    if [parts[0][0],parts[1][0]] != [STRING_POOL,RESOURCE_MAP]:
        raise ValueError("expected AXML pool + resource map")
    strings,offsets,_=unpack_pool(parts[0][1])
    existing=tuple(strings)
    add=["android.intent.category.LEANBACK_LAUNCHER","android.software.leanback","android.hardware.touchscreen","android.hardware.gamepad","banner","launchMode","debuggable","allowBackup"]
    parts[0]=(STRING_POOL,rewrite_pool(parts[0][1],strings,offsets,add)[0])
    strings2=unpack_pool(parts[0][1])[0]
    def idx(s):
        if s not in strings2:raise ValueError("expected manifest name "+s)
        return strings2.index(s)
    android_ns=idx(ANDROID_NS)
    required=idx("required")
    name=idx("name")
    pool=parts[1][1]
    ids=list(unpack("<"+str((len(pool)-8)//4)+"I",pool,8))
    if len(ids)<=idx("banner"):ids.extend([0]*(idx("banner")+1-len(ids)))
    if ids[idx("banner")] not in (0,ANDROID_BANNER_ATTR_ID):raise ValueError("unexpected banner attr id")
    ids[idx("banner")]=ANDROID_BANNER_ATTR_ID
    for attribute,resource_id in [("launchMode",0x0101001d),("debuggable",0x0101000f),("allowBackup",0x01010280)]:
        if len(ids)<=idx(attribute):ids.extend([0]*(idx(attribute)+1-len(ids)))
        if ids[idx(attribute)] not in (0,resource_id):raise ValueError("unexpected framework attribute id")
        ids[idx(attribute)]=resource_id
    parts[1]=(RESOURCE_MAP,chunk(RESOURCE_MAP,8,struct.pack("<"+str(len(ids))+"I",*ids)))
    def set_attribute(node,attribute,kind,value):
        _,_,atstart,atsize,count,_,_,_=unpack("<IIHHHHHH",node,16)
        found=[]
        for j in range(count):
            off=16+atstart+j*atsize
            ns,field=unpack("<II",node,off)
            if ns==android_ns and field==idx(attribute):found.append(off)
        if len(found)>1:raise ValueError("duplicate framework attribute")
        entry=xml_attr(android_ns,idx(attribute),0xffffffff,kind,value)
        if not found:return insert_sorted_attribute(node,entry,ids)
        result=bytearray(node);result[found[0]:found[0]+20]=entry;return bytes(result)
    # Features inserted as children of manifest, before <application>.
    features=[]
    for feature in ("android.software.leanback","android.hardware.touchscreen","android.hardware.gamepad"):
        fields=[
            xml_attr(android_ns,name,idx(feature),0x03,idx(feature)),
            xml_attr(android_ns,required,0xffffffff,0x12,0)]
        features.append(start_element(idx("uses-feature"),fields))
        features.append(xml_node(END,idx("uses-feature")))
    features=b"".join(features)
    category=start_element(idx("category"),[
        xml_attr(android_ns,name,idx("android.intent.category.LEANBACK_LAUNCHER"),0x03,idx("android.intent.category.LEANBACK_LAUNCHER"))
    ]) + xml_node(END,idx("category"))
    out=[]
    stack=[]
    applied={"feature":0,"banner":0,"activity_banner":0,"category":0}
    target_intent=False
    saw_main=False
    saw_launcher=False
    for i,(t,c) in enumerate(parts):
        if t==START:
            tag,a,count=attrs(c,strings2)
            path=stack+[tag]
            if tag=="application":
                if applied["feature"] or path!=["manifest","application"]:
                    raise ValueError("nonstandard application position")
                out.append(features)
                applied["feature"]+=1
                # Pin original icon and label; append Android TV banner as reference.
                if any(x[0]=="banner" for x in a):raise ValueError("pre-existing banner not supported")
                c=insert_sorted_attribute(c,xml_attr(android_ns,idx("banner"),0xffffffff,0x01,BANNER_RESOURCE_ID),ids)
                applied["banner"]+=1
                if release:
                    c=set_attribute(c,"debuggable",0x12,0)
                    c=set_attribute(c,"allowBackup",0x12,0)
            if tag=="intent-filter" and path==["manifest","application","activity","intent-filter"]:
                # Only the GodotApp activity's MAIN/LAUNCHER filter is eligible.
                target_intent=False;saw_main=False;saw_launcher=False
                # Inspect parent activity in most recent start: its class name.
                parent=parts[i-1][1] if i>0 else b""
                # Regular intervening meta-data means use an active context instead.
                if active_godot_activity:target_intent=True
            if tag=="activity":
                values=[a[1] for a in a if a[0]=="name"]
                active_godot_activity=values==["com.godot.game.GodotApp"]
                if active_godot_activity:
                    # API31 singleInstancePerTask is not a supported launch mode
                    # on Android11 Shield. Reuse the existing Godot task instead.
                    c=set_attribute(c,"launchMode",0x10,2)
                    if any(x[0]=="banner" for x in a):raise ValueError("pre-existing activity banner not supported")
                    c=insert_sorted_attribute(c,xml_attr(android_ns,idx("banner"),0xffffffff,0x01,BANNER_RESOURCE_ID),ids)
                    applied["activity_banner"]+=1
            if tag=="action" and target_intent and any(x[1]=="android.intent.action.MAIN" for x in a):
                saw_main=True
            if tag=="category" and target_intent and any(x[1]=="android.intent.category.LAUNCHER" for x in a):
                saw_launcher=True
            stack.append(tag)
            out.append(c)
        elif t==END:
            tag_idx=unpack("<I",c,20)[0]
            tag=strings2[tag_idx]
            if not stack or stack[-1]!=tag:raise ValueError("unexpected axml nesting")
            if tag=="intent-filter" and target_intent and saw_main and saw_launcher:
                if applied["category"]:raise ValueError("duplicate target intent")
                out.append(category)
                applied["category"]+=1
                target_intent=False
            if tag=="activity":active_godot_activity=False
            stack.pop()
            out.append(c)
        else:
            out.append(c)
    if stack:raise ValueError("unclosed xml elements")
    if applied != {"feature":1,"banner":1,"activity_banner":1,"category":1}:raise ValueError("missing targeted manifest insertion "+str(applied))
    contents=b"".join(out)
    result=struct.pack("<HHI",ROOT_CHUNK,8,8+len(contents))+contents
    for typ,node in read_chunks(result):
        if typ!=START:continue
        _,_,atstart,atsize,count,_,_,_=unpack("<IIHHHHHH",node,16)
        framework=[]
        for j in range(count):
            ns,name=unpack("<II",node,16+atstart+j*atsize)
            if ns==android_ns: framework.append(ids[name])
        if framework!=sorted(framework):raise ValueError("Android framework attributes are unsorted")
    return result

def banner_png(iconfile, title="KINEGRA AMP", subtitle="VISUALS", strapline="MUSIC MADE VISIBLE"):
    img=Image.new("RGB",(320,180),(8,15,33))
    d=ImageDraw.Draw(img)
    for y in range(180):
        d.line((0,y,320,y),fill=(8+int(y/32),15+int(y/24),33+int(y/18)))
    emblem=Image.open(iconfile).convert("RGBA")
    emblem.thumbnail((145,145))
    img.paste(emblem,(12+(145-emblem.width)//2,17+(145-emblem.height)//2),emblem)
    fontpath="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    if not pathlib.Path(fontpath).is_file():raise ValueError("no local banner font")
    strong=ImageFont.truetype(fontpath,23)
    medium=ImageFont.truetype(fontpath,12)
    d.text((148,58),title,font=strong,fill=(171,235,255))
    d.text((148,89),subtitle,font=strong,fill=(249,237,195))
    d.text((148,130),strapline,font=medium,fill=(145,182,211))
    o=io.BytesIO();img.save(o,format="PNG",optimize=True)
    return o.getvalue()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--input",type=pathlib.Path,required=True)
    ap.add_argument("--output",type=pathlib.Path,required=True)
    ap.add_argument("--icon",type=pathlib.Path,required=True)
    ap.add_argument("--banner",type=pathlib.Path,default=None,
                    help="Use a pinned 320x180 original TV banner instead of generated template")
    ap.add_argument("--title", default="KINEGRA AMP")
    ap.add_argument("--subtitle", default="MUSIC VISUALS")
    ap.add_argument("--strapline", default="MUSIC MADE VISIBLE")
    ap.add_argument("--banner-resource-path",default="res/drawable-nodpi-v4/splash.png")
    ap.add_argument("--release-safety",action="store_true",help="Disable Android debugging and backup in the signed production manifest")
    a=ap.parse_args()
    if not a.input.is_file() or a.output.exists() or a.input.resolve()==a.output.resolve():
        raise SystemExit("fail closed: input/output safety")
    with zipfile.ZipFile(a.input) as source:
        entries=source.infolist()
        if len({x.filename for x in entries})!=len(entries):raise ValueError("duplicate zip entries")
        banner_path=a.banner_resource_path
        if not banner_path.startswith("res/") or not banner_path.endswith(".png") or ".." in pathlib.PurePosixPath(banner_path).parts or "\\" in banner_path:raise ValueError("unsafe banner resource path")
        if not {"AndroidManifest.xml",banner_path,"resources.arsc"}.issubset({x.filename for x in entries}):
            raise ValueError("required template resources absent")
        manifest=modify_manifest(source.read("AndroidManifest.xml"),release=a.release_safety)
        if a.banner is not None:
            if not a.banner.is_file():
                raise ValueError("required original Kinegra Amp banner missing")
            banner=a.banner.read_bytes()
            with Image.open(io.BytesIO(banner)) as im:
                if im.size!=(320,180) or im.format!="PNG":
                    raise ValueError("TV banner must be a 320x180 PNG")
        else:
            banner=banner_png(a.icon, a.title, a.subtitle, a.strapline)
        with zipfile.ZipFile(a.output,"w") as dest:
            for info in entries:
                # Never carry forward v0.3 or Godot-export signatures after modifying manifest.
                # The Android TV candidate is UNSIGNED until an independent signing gate.
                if info.filename.startswith("META-INF/") and info.filename.upper().endswith((".SF",".RSA",".DSA","MANIFEST.MF")):
                    continue
                contents=manifest if info.filename=="AndroidManifest.xml" else banner if info.filename==banner_path else source.read(info.filename)
                dest.writestr(info,contents)
    print("ANDROID_TV_MANIFEST_PATCHED_AND_BANNER_320x180",a.output)
if __name__=="__main__": main()
