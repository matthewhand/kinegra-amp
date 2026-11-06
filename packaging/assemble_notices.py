"""Assemble auditable runtime notices from exact resolved build inputs."""
from pathlib import Path
import hashlib,json,re,shutil,zipfile,xml.etree.ElementTree as ET
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def assemble(source,app,cfg,graph,native):
    out=app/'assets/notices';out.mkdir(parents=True,exist_ok=True)
    for item in list(out.iterdir()):
        if not item.is_file() or item.is_symlink(): raise ValueError('Unexpected notice path')
        item.unlink()
    entries=[]
    def entry(name,title,data):
        assert re.fullmatch(r'[A-Za-z0-9._-]+',name)
        data=data.encode() if isinstance(data,str) else data
        (out/name).write_bytes(data)
        entries.append({'file':name,'title':title,'sha256':hashlib.sha256(data).hexdigest()})
    sources=json.loads((source/'third_party/notice-sources.json').read_text())
    for record in sources['notices']:
        path=source/'third_party/notices'/record['file']
        assert sha(path)==record['sha256'],record['file']
        entry(record['file'],record['title'],path.read_bytes())
    dependencies=[];poms=[];embedded=[]
    for item in json.loads(Path(graph).read_text()):
        group,name,version=item['group'],item['name'],item['version']
        artifact=Path(item['file'])
        cache=cfg['gradle_user_home']/'caches/modules-2/files-2.1'/group/name/version
        paths=sorted(cache.glob('*/*.pom'))
        if len(paths)!=1:raise ValueError('Exactly one cached POM required for '+group+':'+name+':'+version)
        pom=paths[0];root=ET.fromstring(pom.read_bytes())
        ns={'m':'http://maven.apache.org/POM/4.0.0'}
        licenses=[{'name':x.findtext('m:name','',ns),'url':x.findtext('m:url','',ns)} for x in root.findall('m:licenses/m:license',ns)]
        parents=[]
        while not licenses and root.find('m:parent',ns) is not None and len(parents)<8:
            parent=root.find('m:parent',ns)
            pg,pn,pv=[parent.findtext('m:'+key,'',ns) for key in ['groupId','artifactId','version']]
            parent_paths=sorted((cfg['gradle_user_home']/'caches/modules-2/files-2.1'/pg/pn/pv).glob('*/*.pom'))
            if len(parent_paths)!=1:raise ValueError('Cached license parent POM missing for '+pg+':'+pn+':'+pv)
            parent_pom=parent_paths[0]
            parents.append({'coordinate':pg+':'+pn+':'+pv,'pom_sha256':sha(parent_pom)})
            poms.append('LICENSE PARENT '+pg+':'+pn+':'+pv+'\n'+parent_pom.read_text()+'\n')
            root=ET.fromstring(parent_pom.read_bytes())
            licenses=[{'name':x.findtext('m:name','',ns),'url':x.findtext('m:url','',ns)} for x in root.findall('m:licenses/m:license',ns)]
        if not licenses:raise ValueError('No published POM license for '+group+':'+name+':'+version)
        if not all('apache' in x['name'].lower() and ('2' in x['name'] or '2.0' in x['url']) for x in licenses):
            raise ValueError('Unreviewed runtime license for '+group+':'+name+':'+version)
        coordinate=group+':'+name+':'+version
        dependencies.append({'coordinate':coordinate,'artifact':artifact.name,'artifact_sha256':sha(artifact),'pom_sha256':sha(pom),'license_parent_poms':parents,'licenses':licenses})
        poms.append('COORDINATE '+coordinate+'\n'+pom.read_text()+'\n')
        if zipfile.is_zipfile(artifact):
            with zipfile.ZipFile(artifact) as z:
                for original in sorted(z.namelist()):
                    leaf=Path(original).name.upper()
                    if original.startswith('META-INF/') and any(leaf.startswith(x) for x in ['LICENSE','NOTICE','COPYING','COPYRIGHT']):
                        data=z.read(original)
                        if len(data)>2*1024*1024:raise ValueError('Unexpected embedded license size')
                        title=coordinate+' / '+original
                        target='GRADLE-'+hashlib.sha256(title.encode()).hexdigest()[:16]+'.txt'
                        entry(target,title,data);embedded.append({'coordinate':coordinate,'path':original,'notice_file':target,'sha256':hashlib.sha256(data).hexdigest()})
    dependencies.sort(key=lambda x:x['coordinate'])
    lock={'schema':1,'configuration':'releaseRuntimeClasspath','dependencies':dependencies}
    expected=source/'third_party/gradle-runtime.lock.json'
    if expected.exists() and json.loads(expected.read_text())!=lock:raise ValueError('Resolved Gradle runtime differs from the reviewed dependency lock')
    (Path(graph).parent/'generated-gradle-runtime.lock.json').write_text(json.dumps(lock,indent=2,sort_keys=True)+'\n')
    entry('GRADLE-RUNTIME-POMS.txt','Android runtime dependency POM licenses','\n'.join(poms))
    entry('APACHE-2.0.txt','Apache License 2.0',(source/'tools/licenses/sendspin-cpp-LICENSE.txt').read_bytes())
    libs={name:sha(native/name) for name in ['libshield_sendspin_arm64.so','libtegra_godot_arm64.so']}
    libs['libgodot_android.so']=sha(cfg['godot_engine_library'])
    with zipfile.ZipFile(cfg['godot_aar']) as z:
        data=z.read('jni/arm64-v8a/libc++_shared.so')
        assert hashlib.sha256(data).hexdigest()=='c4c2fe5cbcb1fba0003a31fc7ab29a9bb12df6cc187ec45a806462540e83d93b'
        libs['libc++_shared.so']=hashlib.sha256(data).hexdigest()
    inventory={'schema':1,'package':'org.local.tegramilkdrop','engine':'Godot 3.6.3 with published OpenSL shutdown patch',
               'native_libraries':libs,'source_patch_sha256':{name:sha(source/'native'/name) for name in ['sendspin-ordered-clear.patch','sendspin-outbound-only.patch','noise-pattern-bounds.patch','ixwebsocket-source-path.patch','patches/godot-3.6.3-opensl-shutdown.patch']},'native_linkage':{'libgodot_android.so':'Godot3.6.3+NDKr26d; original Godot full copyright/license retained',
               'libc++_shared.so':'Exact official Godot3.6.3 AAR runtime; Android NDK28.0.13004108 notices',
               'libshield_sendspin_arm64.so':'Pinned Sendspin+ArduinoJson+IXWebSocket+micro-flac+micro-ogg-demuxer+Noise-C; NDKr26d static C++/libunwind; Android zlib/log/android system linkage. Opus disabled.',
               'libtegra_godot_arm64.so':'Project codec+minimp3+stb_vorbis+GDNative headers; Android math/system linkage'},
               'gradle':lock,'embedded_upstream_notices':embedded,'static_notice_sources':sources,
               'font':'Unmodified DejaVuSans with Bitstream Vera/DejaVu notices',
               'application':'MIT project code, original generated artwork, procedural icons and synthetic hero; no soundtrack/cover media',
               'device_actions':False}
    entry('RUNTIME-INVENTORY.json','Exact runtime component inventory',json.dumps(inventory,indent=2,sort_keys=True)+'\n')
    overview='''Kinegra Amp — licenses and notices

Project code, documentation, original artwork and hero media: MIT.
No music, private cover artwork or inference model is bundled.

This release uses Godot3.6.3/GLES2, the published OpenSL shutdown fix,
the original Godot Android Java API and native C++ runtime, Sendspin,
the minimp3/stb codecs and the unmodified DejaVuSans font.

Full Godot and Android NDK notices are retained conservatively, together
with pinned native dependency licenses, Noise-C subcomponent headers,
and the actual resolved Android runtime dependency POM/embedded notices.
RUNTIME-INVENTORY.json maps the exact native payload hashes and Gradle
artifacts. Runtime dependency resolution fails if its reviewed lock changes.

Use the component selector and Previous/Next Page to read long notices.
The complete notice bundle is also included with the source distribution.

Source: https://github.com/matthewhand/kinegra-amp
'''
    entry('OVERVIEW.txt','About these licenses',overview)
    entries.sort(key=lambda x:(x['file']!='OVERVIEW.txt',x['title'].lower()))
    result={'schema':1,'notices':entries}
    (out/'INDEX.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return result
