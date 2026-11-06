"""Production manifest and 16 KiB native-payload checks; no device actions."""
from pathlib import Path
import re, struct, zipfile

def validate_release_manifest(text, require_single_task=True):
    applications=[b for b in re.split(r'(?m)^\s*E: ',text) if b.startswith('application ')]
    if len(applications)!=1:raise RuntimeError('Expected one application manifest element')
    app=applications[0]
    for field,required in [('debuggable',False),('allowBackup',True)]:
        entries=re.findall(r'(?m)^\s*A: android:'+field+r'\([^\n]+$',app)
        if not entries and not required:continue # Android default is non-debuggable.
        if len(entries)!=1 or not re.search(r'=\(type 0x12\)0x0\s*$',entries[0]):
            raise RuntimeError('Production application must disable '+field)
    activities=[b for b in re.split(r'(?m)^\s*E: ',text) if b.startswith('activity ') and 'com.godot.game.GodotApp' in b]
    if require_single_task and (len(activities)!=1 or len(re.findall(r'A: android:launchMode\(',activities[0]))!=1 or not re.search(r'android:launchMode\([^\n]+=\(type 0x10\)0x2\s*$',activities[0],re.M)):
        raise RuntimeError('Godot must reuse its single task on supported Android versions')

def validate_native_alignment(apk):
    """Inspect ELF program headers and actual uncompressed ZIP data offsets."""
    count=0
    with zipfile.ZipFile(apk) as archive, Path(apk).open('rb') as raw:
        names=archive.namelist()
        if len(names)!=len(set(names)):raise RuntimeError('Duplicate APK paths')
        for info in archive.infolist():
            if not (info.filename.startswith('lib/') and info.filename.endswith('.so')):continue
            count+=1
            if info.compress_type!=zipfile.ZIP_STORED:raise RuntimeError('Native library must be uncompressed')
            raw.seek(info.header_offset+26)
            header=raw.read(4)
            if len(header)!=4:raise RuntimeError('Truncated ZIP header')
            name_length,extra_length=struct.unpack('<HH',header)
            offset=info.header_offset+30+name_length+extra_length
            if offset%16384:raise RuntimeError('Native ZIP payload is not 16 KiB aligned')
            data=archive.read(info)
            if len(data)<64 or data[:6]!=b'\x7fELF\x02\x01' or data[18:20]!=b'\xb7\x00':
                raise RuntimeError('Expected ARM64 little-endian ELF')
            phoff=struct.unpack_from('<Q',data,32)[0]
            entry_size,count_headers=struct.unpack_from('<HH',data,54)
            if entry_size!=56 or not 0<count_headers<=128 or phoff+entry_size*count_headers>len(data):
                raise RuntimeError('Invalid ELF program headers')
            loads=0
            for i in range(count_headers):
                kind,flags,file_offset,virtual,physical,file_size,memory_size,alignment=struct.unpack_from('<IIQQQQQQ',data,phoff+i*entry_size)
                if kind!=1:continue
                loads+=1
                if alignment<16384 or alignment%16384 or (virtual-file_offset)%16384 or memory_size<file_size:
                    raise RuntimeError('ELF LOAD segment is not 16 KiB compatible')
            if not loads:raise RuntimeError('ELF has no LOAD segment')
    if not count:raise RuntimeError('Missing native libraries')
    return count

def resolve_banner_resource(text):
    matches=re.findall(r'(?m)^\s*resource 0x7f06000c [^\n]*:drawable/splash:[^\n]*\n\s+\(string(?:8|16)?\) "([^"\n]+)"',text)
    if len(matches)!=1:raise RuntimeError('Expected one mapped Godot splash resource')
    path=matches[0]
    if not re.fullmatch(r'res/[A-Za-z0-9_./-]+\.png',path) or '..' in path.split('/'):
        raise RuntimeError('Unsafe splash resource path')
    return path
