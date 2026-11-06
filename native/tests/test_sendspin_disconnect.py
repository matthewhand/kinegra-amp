#!/usr/bin/env python3
"""Loopback-only active-stream disconnect fixture.
All identities are freshly generated and only exist in memory; never contacts MA.
"""
import asyncio, base64, os, pathlib, sys, tempfile, shutil
from importlib.metadata import version
from aiohttp import web
from aiohttp.test_utils import TestServer
from aiosendspin.noise.keys import Identity, generate_psk, psk_id_for
from aiosendspin.noise.trust_store import InMemoryServerPairingStore, ServerPairingRecord
from aiosendspin.server.server import SendspinServer
from aiosendspin.server.audio import AudioFormat
import struct

if version("aiosendspin") != "10.2.0": raise SystemExit("expected pinned aiosendspin 10.2.0")
root=pathlib.Path(__file__).resolve().parent
if len(sys.argv)!=4 or sys.argv[3]!='main': raise SystemExit('usage: test_sendspin_disconnect.py <godot> <host-plugin> main')
main_test=True
def snapshot(items):
    data=bytearray(b'SSV1'+bytes([len(items)]))
    for key,value in sorted(items.items()):
        name=key.encode('ascii')
        data+=bytes([len(name)])+name+bytes([len(value)])+value
    return base64.b64encode(data).decode('ascii')
async def run():
    identity=Identity.generate(); client_identity=Identity.generate(); psk=generate_psk()
    store=InMemoryServerPairingStore()
    await store.store_record(ServerPairingRecord(psk_id=psk_id_for(psk),psk=psk,client_id=client_identity.peer_id,pair_methods=[]))
    server=SendspinServer(loop=asyncio.get_running_loop(),identity=identity,server_name='fictional loopback server',pairing_store=store,allow_noncompliant_clients=False)
    app=web.Application(); blocked=asyncio.Event()
    async def endpoint(request):
        if blocked.is_set(): raise web.HTTPServiceUnavailable()
        return await server.on_client_connect(request)
    app.router.add_get(SendspinServer.API_PATH,endpoint)
    webserver=TestServer(app); await webserver.start_server()
    try:
        with tempfile.TemporaryDirectory(prefix='shieldamp-paired-') as folder:
            work=pathlib.Path(folder)
            if main_test:
                app_source=root.parent.parent/'app'
                def ignore_private(directory,names):
                    path=pathlib.Path(directory)
                    if path==app_source/'assets': return {'music'} & set(names)
                    if path==app_source/'.import': return {name for name in names if name.startswith('track_')}
                    return set()
                shutil.copytree(app_source,work,dirs_exist_ok=True,ignore=ignore_private)
                music=work/'assets'/'music'; artwork=music/'artwork'; artwork.mkdir(parents=True)
                silent=music/'track_01.ogg'
                subprocess_result=await asyncio.create_subprocess_exec('ffmpeg','-nostdin','-loglevel','error','-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-t','0.2','-c:a','libvorbis',str(silent))
                if await subprocess_result.wait()!=0: raise SystemExit('synthetic audio fixture creation failed')
                from PIL import Image
                for i in range(1,5):
                    if i>1: shutil.copyfile(silent,music/f'track_{i:02d}.ogg')
                    Image.new('RGB',(16,16),(0,0,0)).save(artwork/f'track_{i:02d}.jpg')
                importer=await asyncio.create_subprocess_exec('xvfb-run','-a',sys.argv[1],'--path',folder,'--editor','--quit',env=dict(os.environ,XDG_DATA_HOME=folder),stdout=asyncio.subprocess.DEVNULL,stderr=asyncio.subprocess.PIPE)
                _,import_errors=await asyncio.wait_for(importer.communicate(),timeout=20)
                if importer.returncode: raise SystemExit('synthetic fixture import failed: '+import_errors.decode(errors='replace'))
            else:
                (work/'project.godot').write_text('config_version=4\n[application]\nconfig/name="Sendspin Paired Test"\n')
            (work/'ShieldSendspin.gdnlib').write_text('[gd_resource type="GDNativeLibrary" format=2]\n[resource]\nsingleton=false\nload_once=true\nsymbol_prefix="godot_"\nreloadable=false\n[entry]\nX11.64="res://libshield_sendspin_x11.so"\n')
            (work/'ShieldSendspin.gdns').write_text('[gd_resource type="NativeScript" load_steps=2 format=2]\n[ext_resource path="res://ShieldSendspin.gdnlib" type="GDNativeLibrary" id=1]\n[resource]\nresource_name="ShieldSendspin"\nclass_name="ShieldSendspin"\nlibrary=ExtResource( 1 )\n')
            (work/'libshield_sendspin_x11.so').write_bytes(pathlib.Path(sys.argv[2]).read_bytes())
            (work/'test.gd').write_bytes((root/('test_sendspin_disconnect.gd' if main_test else 'test_sendspin_paired.gd')).read_bytes())
            scripts=root.parent.parent/'app'/'scripts'
            for name in ('SendspinPcmOutput.gd','SendspinMixerFeedback.gd','SendspinPlaybackRuntime.gd','SendspinBridgePump.gd'):
                content=(scripts/name).read_text().replace('res://scripts/','res://')
                (work/name).write_text(content)
            blobs={'keypair':client_identity.private_bytes,'pairing_psk':generate_psk(),'rec_0':psk+identity.public_bytes,'rec_order':bytes([0]+[255]*11)}
            marker=work/'clear-marker'
            env=dict(os.environ,SHIELDAMP_CLEAR_MARKER=str(marker),SHIELDAMP_TEST_URL=f'ws://127.0.0.1:{webserver.port}{SendspinServer.API_PATH}',SHIELDAMP_SYNTHETIC_SNAPSHOT=snapshot(blobs),XDG_DATA_HOME=folder,METHEXIS_SOURCE_TEST='1')
            proc=await asyncio.create_subprocess_exec('xvfb-run','-a',sys.argv[1],'--path',folder,'--no-window','--script','res://test.gd',env=env,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
            async def produce():
                async with asyncio.timeout(10):
                    while True:
                        connected=server.get_client(client_identity.peer_id)
                        if connected is not None and connected.is_connected and connected.group is not None:
                            break
                        await asyncio.sleep(.02)
                stream=connected.group.start_stream()
                stream.set_live_source(True)
                pcm=(struct.pack("<hh",500,-500)*32+struct.pack("<hh",-500,500)*32)*15
                for _ in range(600):
                    if marker.exists():
                        blocked.set()
                        await connected.connection.disconnect(retry_connection=False)
                        return
                    stream.prepare_audio(pcm,AudioFormat(sample_rate=48000,bit_depth=16,channels=2))
                    await stream.commit_audio()
                    await asyncio.sleep(.02)
            task=asyncio.create_task(produce())
            try:
                out,err=await asyncio.wait_for(proc.communicate(),timeout=22)
            finally:
                task.cancel()
                await asyncio.gather(task,return_exceptions=True)
            print(out.decode(errors='replace'))
            required=[b'FAULT_INITIAL_AUDIO=True',b'FAULT_STREAM_STALE=True',b'FAULT_NO_OFFLINE_AUTOPLAY=True',b'FAULT_RECONNECT_VISIBLE=True']
            if proc.returncode or any(item not in out for item in required):
                print(err.decode(errors='replace'),file=sys.stderr)
                raise SystemExit('synthetic pairing failed')
    finally:
        await webserver.close(); await server.close()
    print('SENDSPIN_SYNTHETIC_DISCONNECT_PASS')
asyncio.run(run())
