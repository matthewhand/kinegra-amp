#!/usr/bin/env python3
"""Loopback-only SDK/aiosendspin encrypted pairing-record fixture.
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
import struct, signal

if version("aiosendspin") != "10.2.0": raise SystemExit("expected pinned aiosendspin 10.2.0")
root=pathlib.Path(__file__).resolve().parent
if len(sys.argv) not in (3,4) or (len(sys.argv)==4 and sys.argv[3] not in ('main','main-timeout','buffer','sustained','continuity','continuity-jitter','startup')): raise SystemExit('usage: test_sendspin_paired.py <godot> <host-plugin> [main|main-timeout|buffer|sustained|continuity|continuity-jitter|startup]')
startup_test=len(sys.argv)==4 and sys.argv[3]=="startup"
timeout_test=len(sys.argv)==4 and sys.argv[3]=="main-timeout"
main_test=len(sys.argv)==4 and sys.argv[3] in ("main","main-timeout")
buffer_test=len(sys.argv)==4 and sys.argv[3]=="buffer"
sustained_test=len(sys.argv)==4 and sys.argv[3]=="sustained"
continuity_test=len(sys.argv)==4 and sys.argv[3] in ("continuity","continuity-jitter")
jitter_test=len(sys.argv)==4 and sys.argv[3]=="continuity-jitter"
continuity_seconds=int(os.environ.get("SHIELDAMP_CONTINUITY_SECONDS","8"))
if not 8<=continuity_seconds<=120:raise SystemExit("continuity duration must be 8..120 seconds")
stress_seconds=int(os.environ.get("SHIELDAMP_STRESS_SECONDS","16"))
if not 16<=stress_seconds<=120: raise SystemExit("stress duration must be 16..120 seconds")
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
    app=web.Application(); app.router.add_get(SendspinServer.API_PATH,server.on_client_connect)
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
                native_bin=work/'native'/'bin';native_bin.mkdir(parents=True,exist_ok=True)
                codec_source=root.parent
                compiler=await asyncio.create_subprocess_exec('cc','-std=c11','-O2','-fPIC','-fvisibility=hidden','-Wall','-Wextra','-Werror','-Wno-unused-function','-I'+str(codec_source),'-I'+str(codec_source/'vendor/godot-headers'),'-shared',*[str(codec_source/name) for name in ('godot_codec.c','tegra_codec.c','minimp3_impl.c','stb_vorbis_impl.c')],'-o',str(native_bin/'libtegra_godot_x11.so'),'-lm',stdout=asyncio.subprocess.DEVNULL,stderr=asyncio.subprocess.PIPE)
                _,compile_errors=await asyncio.wait_for(compiler.communicate(),timeout=30)
                if compiler.returncode: raise SystemExit('synthetic fixture codec build failed: '+compile_errors.decode(errors='replace'))
                importer=await asyncio.create_subprocess_exec('xvfb-run' ,'-a',sys.argv[1],'--path',folder,'--editor','--quit',env=dict(os.environ,XDG_DATA_HOME=folder),stdout=asyncio.subprocess.DEVNULL,stderr=asyncio.subprocess.PIPE)
                _,import_errors=await asyncio.wait_for(importer.communicate(),timeout=20)
                if importer.returncode: raise SystemExit('synthetic fixture import failed: '+import_errors.decode(errors='replace'))
            else:
                (work/'project.godot').write_text('config_version=4\n[application]\nconfig/name="Sendspin Paired Test"\n')
            (work/'ShieldSendspin.gdnlib').write_text('[gd_resource type="GDNativeLibrary" format=2]\n[resource]\nsingleton=false\nload_once=true\nsymbol_prefix="godot_"\nreloadable=false\n[entry]\nX11.64="res://libshield_sendspin_x11.so"\n')
            (work/'ShieldSendspin.gdns').write_text('[gd_resource type="NativeScript" load_steps=2 format=2]\n[ext_resource path="res://ShieldSendspin.gdnlib" type="GDNativeLibrary" id=1]\n[resource]\nresource_name="ShieldSendspin"\nclass_name="ShieldSendspin"\nlibrary=ExtResource( 1 )\n')
            (work/'libshield_sendspin_x11.so').write_bytes(pathlib.Path(sys.argv[2]).read_bytes())
            scenario='test_sendspin_startup_network.gd' if startup_test else 'test_sendspin_main_timeout.gd' if timeout_test else ('test_sendspin_main_network.gd' if main_test else ('test_sendspin_continuity_network.gd' if continuity_test else ('test_sendspin_buffered_network.gd' if buffer_test else ('test_sendspin_sustained_network.gd' if sustained_test else 'test_sendspin_paired.gd'))))
            (work/'test.gd').write_bytes((root/scenario).read_bytes())
            scripts=root.parent.parent/'app'/'scripts'
            for name in ('SendspinPcmOutput.gd','SendspinMixerFeedback.gd','SendspinPlaybackRuntime.gd','SendspinBridgePump.gd'):
                content=(scripts/name).read_text().replace('res://scripts/','res://')
                (work/name).write_text(content)
            blobs={'keypair':client_identity.private_bytes,'pairing_psk':generate_psk(),'rec_0':psk+identity.public_bytes,'rec_order':bytes([0]+[255]*11)}
            marker=work/'clear-marker'
            env=dict(os.environ,SHIELDAMP_CLEAR_MARKER=str(marker),SHIELDAMP_TEST_URL=f'ws://127.0.0.1:{webserver.port}{SendspinServer.API_PATH}',SHIELDAMP_SYNTHETIC_SNAPSHOT=snapshot(blobs),XDG_DATA_HOME=folder,METHEXIS_SOURCE_TEST='1')
            out_file=(work/'stdout.log').open('wb');err_file=(work/'stderr.log').open('wb')
            proc=await asyncio.create_subprocess_exec('xvfb-run','-a',sys.argv[1],'--path',folder,'--no-window','--script','res://test.gd',env=env,stdout=out_file,stderr=err_file,start_new_session=True)
            async def produce():
                async with asyncio.timeout(10):
                    while True:
                        connected=server.get_client(client_identity.peer_id)
                        if connected is not None and connected.is_connected and connected.group is not None:
                            break
                        await asyncio.sleep(.02)
                if startup_test:
                    role=connected.roles_by_family("player")[0]
                    async with asyncio.timeout(2):
                        while role.get_min_buffer_us()!=3_000_000 or role.get_required_lead_time_us()!=4_000_000:
                            await asyncio.sleep(.01)
                    capacity=connected.info.player_support.buffer_capacity
                    assert capacity>=800_000,"advertised PCM queue must cover requested startup lead plus overhead"
                    print("STARTUP_NEGOTIATED_MIN_MS=3000 LEAD_MS=4000 CAPACITY="+str(capacity))
                stream=connected.group.start_stream()
                stream.set_live_source(not startup_test)
                pcm=(struct.pack("<hh",500,-500)*32+struct.pack("<hh",-500,500)*32)*15
                replaced=False
                segment_index=0
                reconnect_marker=""
                started=asyncio.get_running_loop().time()
                for index in range((continuity_seconds+15)*50 if continuity_test else ((stress_seconds+15)*50 if sustained_test else (1200 if startup_test else 600))):
                    if startup_test and marker.exists() and marker.read_text() in ("reconnect","cancel") and marker.read_text()!=reconnect_marker:
                        reconnect_marker=marker.read_text()
                        stream=None
                        segment_index=0
                    if timeout_test or startup_test:
                        candidate=server.get_client(client_identity.peer_id)
                        if candidate is None or not candidate.is_connected or candidate.group is None:
                            stream=None
                            segment_index=0
                            await asyncio.sleep(.02)
                            continue
                        if stream is None:
                            stream=candidate.group.start_stream()
                            stream.set_live_source(not startup_test)
                    if marker.exists() and not replaced:
                        stream.clear()
                        pcm=(struct.pack("<hh",1000,-1000)*32+struct.pack("<hh",-1000,1000)*32)*15
                        replaced=True
                        segment_index=0
                    if startup_test:
                        pcm=b"".join(struct.pack("<hh",(segment_index*960+j)%30000+1,-((segment_index*960+j)%30000+1)) for j in range(960))
                        segment_index+=1
                    if continuity_test:
                        pcm=b"".join(struct.pack("<hh",(index*960+j)%30000+1,-((index*960+j)%30000+1)) for j in range(960))
                    stream.prepare_audio(pcm,AudioFormat(sample_rate=48000,bit_depth=16,channels=2))
                    await stream.commit_audio()
                    if sustained_test or continuity_test or startup_test:
                        # Bounded scheduling jitter and one 350 ms delivery gap;
                        # resume against the same producer clock after the gap.
                        if sustained_test and index==500:await asyncio.sleep(.35)
                        jitter=(0.0,.005,.025,0.0)[index%4] if sustained_test or jitter_test or startup_test else 0.0
                        deadline=started+(index+1)*.02+jitter
                        await asyncio.sleep(max(0.0,deadline-asyncio.get_running_loop().time()))
                    else:await asyncio.sleep(.02)
            task=asyncio.create_task(produce())
            try:
                await asyncio.wait_for(proc.wait(),timeout=35 if startup_test else (continuity_seconds+20 if continuity_test else (stress_seconds+20 if sustained_test else 22)))
                out_file.close();err_file.close()
                out=(work/"stdout.log").read_bytes();err=(work/"stderr.log").read_bytes()
            except TimeoutError:
                os.killpg(proc.pid,signal.SIGKILL)
                await proc.wait()
                out_file.close();err_file.close()
                out=(work/"stdout.log").read_bytes();err=(work/"stderr.log").read_bytes()
                print(out.decode(errors='replace'),flush=True)
                print(err.decode(errors='replace'),file=sys.stderr,flush=True)
                raise SystemExit('synthetic pairing timed out')
            finally:
                task.cancel()
                await asyncio.gather(task,return_exceptions=True)
            print(out.decode(errors='replace'))
            required=([b'MAIN_AUTH_SHARED_SYSTEM_GAIN=True',b'MAIN_AUTH_CAPABILITIES=True',b'MAIN_AUTH_LIVE=True',b'MAIN_AUTH_SPECTRUM=True',b'MAIN_AUTH_CLEAR_REPLACEMENT=True',b'MAIN_AUTH_STOPPED=True'] if main_test else [b'AUTHENTICATED_SYNTHETIC_PAIRED=True',b'AUTHENTICATED_SYNTHETIC_PCM=True',b'ESTIMATED_MIXER_FEEDBACK=True',b'SYNTHETIC_CLEAR_AND_REPLACEMENT=True',b'SYNTHETIC_STALE_AUDIO_FRAMES=0'])
            if startup_test:required=[b"STARTUP_COLD_CLEAR_RECONNECT_CANCEL=True"]
            if continuity_test:required=[b"CONTINUITY_ACTIVE=True",b"CONTINUITY_ZERO_FRAMES=0",b"CONTINUITY_LARGE_STEPS=0",b"CONTINUITY_CHANNEL_ERRORS=0",b"CONTINUITY_UNDERRUNS=0"]
            if timeout_test: required=[b"MAIN_CLEAR_TIMEOUT_FAILS_CLOSED=True",b"MAIN_CLEAR_TIMEOUT_RECONNECT=True"]
            if buffer_test: required=[b"BUFFERED_NETWORK_ACTIVE=True",b"BUFFERED_NETWORK_60MS_STALLS=12",b"BUFFERED_NETWORK_UNDERRUNS=0"]
            if sustained_test: required=[b"SUSTAINED_ACTIVE=True",b"SUSTAINED_FORCED_UNDERRUN=True",b"SUSTAINED_RECOVERED=True",b"SUSTAINED_CLEAR_REPLACEMENT=True",b"SUSTAINED_STALE_FRAMES=0"]
            if proc.returncode or any(item not in out for item in required) or b"SCRIPT ERROR" in out+err:
                print(err.decode(errors='replace'),file=sys.stderr)
                raise SystemExit('synthetic pairing failed')
    finally:
        await webserver.close(); await server.close()
    print('SENDSPIN_AUTHENTICATED_LOOPBACK_PASS')
asyncio.run(run())
