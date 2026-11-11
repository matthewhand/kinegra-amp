#!/usr/bin/env python3
"""Real loopback copy/transcode + Godot queue UI tests using generated audio only."""
from pathlib import Path
import argparse
import hashlib
import http.server
import importlib.util
import json
import os
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--godot',required=True)
    a=parser.parse_args()
    spec=importlib.util.spec_from_file_location('offline_source',a.source/'clients/offline_source.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    key='synthetic-source-key-1234567890123456'
    with tempfile.TemporaryDirectory(prefix='shieldamp-offline-test-') as temporary:
        root=Path(temporary);music=root/'music';music.mkdir();(music/'Original').mkdir()
        for n in [0,1]:
            subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i',f'sine=frequency={440+n*110}:duration=1','-c:a','aac',str(music/'Original'/f'fictional{n}.m4a')],check=True)
        subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i','sine=frequency=660:duration=96',
                        '-c:a','libmp3lame','-b:a','192k',str(music/'Original'/'long.mp3')],check=True)
        (music/'escape.m4a').symlink_to('/etc/passwd')
        source=module.Source(music,root/'cache',key,['127.0.0.1'])
        helper=module.Server(('127.0.0.1',0),source)
        threading.Thread(target=helper.serve_forever,daemon=True).start()
        helper_url=f'http://127.0.0.1:{helper.server_port}'
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def prepare(path,token=key):
            request=urllib.request.Request(helper_url+'/prepare',json.dumps({'path':path}).encode(),{'Authorization':'Bearer '+token,'Content-Type':'application/json'})
            with opener.open(request,timeout=10) as response:return json.load(response)
        for bad in ['../etc/passwd','/etc/passwd','escape.m4a','https://example.invalid/audio','Original/../fictional0.m4a']:
            try:prepare(bad);raise AssertionError('unsafe path accepted')
            except urllib.error.HTTPError as error:assert error.code==422
        try:prepare('Original/fictional0.m4a','wrong');raise AssertionError('wrong key accepted')
        except urllib.error.HTTPError as error:assert error.code==403
        manifest=prepare('Original/fictional0.m4a')
        assert manifest['file'].endswith('.mp3')
        request=urllib.request.Request(helper_url+'/audio/'+manifest['file'],headers={'Authorization':'Bearer '+key})
        with opener.open(request,timeout=10) as response:audio=response.read()
        assert len(audio)==manifest['bytes'] and hashlib.sha256(audio).hexdigest()==manifest['sha256']
        assert prepare('Original/fictional0.m4a')==manifest
        long_file=prepare('Original/long.mp3')
        assert long_file['bytes']>2*1024*1024
        request.add_header('Range','bytes=500-799')
        with opener.open(request,timeout=10) as response:
            assert response.status==206 and response.headers['Content-Range']==f"bytes 500-799/{manifest['bytes']}"
            assert response.read()==audio[500:800]
        request.add_header('Range','bytes=9-3')
        try:opener.open(request,timeout=10);raise AssertionError('invalid range accepted')
        except urllib.error.HTTPError as error:assert error.code==416
        class FaultHelper(module.Handler):
            def do_POST(self):
                if helper.mode=='transient' and helper.faults.get('prepare',0)==0 and self.authenticated():
                    helper.faults['prepare']=1
                    self.rfile.read(int(self.headers['Content-Length']))
                    self.reply(503,{'error':'synthetic temporary failure'})
                    return
                super().do_POST()
            def do_GET(self):
                range_header=self.headers.get('Range','')
                helper.ranges.append((self.path,range_header))
                if helper.mode=='legacy':
                    if range_header:del self.headers['Range']
                if helper.mode=='resume-start' and self.path.endswith(long_file['file']) and range_header.startswith('bytes=1048576-'):
                    time.sleep(2)
                if helper.mode=='transient' and helper.faults.get('download',0)==0 and self.authenticated():
                    helper.faults['download']=1
                    self.send_response(206)
                    self.send_header('Content-Length','1000')
                    self.end_headers()
                    self.wfile.write(b'partial')
                    self.close_connection=True
                    return
                super().do_GET()
        helper.RequestHandlerClass=FaultHelper
        helper.ranges=[]
        helper.faults={}
        helper.mode=''
        print('OFFLINE_SOURCE_AUTH_PATH_CONVERSION_HASH_CACHE_PASS',flush=True)
        class MA(http.server.BaseHTTPRequestHandler):
            def log_message(self,*_):pass
            def do_POST(self):
                assert self.headers.get('Authorization')=='Bearer synthetic-library-token'
                obj=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                command=obj['command'];args=obj['args'];self.server.calls.append(command)
                assert command in ['players/all','player_queues/get','player_queues/items','music/tracks/get'],command
                mode=self.server.mode
                if command=='music/tracks/get':self.server.items.append(args['item_id'])
                fail=mode=='transient' and (command=='players/all' or command=='music/tracks/get' and args['item_id']=='1') and self.server.faults.get(command,0)==0
                fail=fail or (mode=='failed-one' and command=='music/tracks/get' and args['item_id']=='1' and self.server.faults.get(command,0)<3)
                if fail:
                    self.server.faults[command]=self.server.faults.get(command,0)+1
                    self.send_response(503);self.send_header('Content-Length','0');self.end_headers()
                    return
                count=2 if mode=='corrupt' else 35
                if command=='players/all':
                    value=[{'player_id':'own-wrapper','provider':'universal_player','type':'player','available':True,'enabled':True,'active_group':None,'synced_to':None,'group_members':[],'static_group_members':[],'active_output_protocol':None,'output_protocols':[{'output_protocol_id':'own-client','protocol_domain':'sendspin','available':True,'derived_from':None}]}]
                elif command=='player_queues/get':
                    value={'queue_id':'own-wrapper','active':True,'state':'playing','items':count,'current_index':(-1 if self.server.mode=='idle' else 0),'index_in_buffer':1,'current_item':{'queue_item_id':'first','name':'Fictional current','duration':1},'next_item':None}
                elif command=='player_queues/items':
                    assert args['queue_id']=='own-wrapper' and 1<=args['limit']<=32
                    value=[{'queue_id':'own-wrapper','queue_item_id':'fictional-'+str(i),'name':'Fictional '+str(i),'media_item':{'provider':'library','item_id':str(i),'media_type':'track'}} for i in range(args['offset'],min(count,args['offset']+args['limit']))]
                else:
                    assert args['provider_instance_id_or_domain']=='library'
                    n=int(args['item_id'])
                    path=f'Original/fictional{n%2}.m4a'
                    if mode.startswith('resume-') and n%2:path='Original/long.mp3'
                    value={'item_id':str(n),'provider':'library','media_type':'track','provider_mappings':[{'provider_domain':'filesystem_local' if n!=34 else 'unsupported_subscription','item_id':path,'available':True}]}
                body=json.dumps(value).encode();self.send_response(200);self.send_header('Content-Length',str(len(body)));self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
        ma=http.server.ThreadingHTTPServer(('127.0.0.1',0),MA);ma.calls=[];ma.items=[];ma.faults={}
        threading.Thread(target=ma.serve_forever,daemon=True).start()
        try:
            for mode in ['complete','idle','during','cancel','legacy','transient','failed-one','resume-start','resume-finish','corrupt']:
                if os.environ.get('OFFLINE_CASE') and mode not in os.environ['OFFLINE_CASE'].split(','):continue
                ma.mode=helper.mode=mode
                ma.items.clear()
                ma.faults.clear()
                helper.ranges.clear()
                helper.faults.clear()
                if mode=='corrupt':
                    for file in source.cache.glob('*.mp3'):
                        data=bytearray(file.read_bytes());data[-1]^=1;file.write_bytes(data)
                env=dict(os.environ,METHEXIS_SOURCE_TEST='0',OFFLINE_MODE=mode,OFFLINE_MA_URL=f'http://127.0.0.1:{ma.server_port}',OFFLINE_SOURCE_URL=helper_url,XDG_DATA_HOME=str(root/('resume' if mode.startswith('resume-') else mode)))
                p=subprocess.run(['xvfb-run','-a',a.godot,'--path',str(a.app),'--audio-driver','Dummy','--script','res://tests/test_offline_queue_save.gd'],env=env,capture_output=True,text=True,timeout=50)
                output=p.stdout+p.stderr
                print(mode,output,flush=True)
                assert p.returncode==0 and 'SCRIPT ERROR' not in output and 'FAIL_' not in output and 'FAILURES=0' in output
                if mode=='transient':
                    assert ma.faults=={'players/all':1,'music/tracks/get':1} and helper.faults=={'prepare':1,'download':1}
                if mode=='failed-one':
                    assert ma.items.count('1')==4 and ma.items[-1]=='1' and len(ma.items)==38
                if mode=='resume-start':
                    checkpoint=next((root/'resume').rglob('offline_queue_copy_v1.json'))
                    text=checkpoint.read_text()
                    assert key not in text and 'synthetic-library-token' not in text and helper_url not in text
                if mode=='resume-finish':
                    assert helper.ranges and all(path.endswith(long_file['file']) for path,_ in helper.ranges)
                    assert helper.ranges[0][1].startswith('bytes=1048576-') and '0' not in ma.items
            assert 'player_queues/items' in ma.calls
            assert not any(x in ma.calls for x in ['player_queues/play','player_queues/clear','player_queues/next'])
            print('OFFLINE_QUEUE_READ_ONLY_HTTP_PASS')
        finally:
            ma.shutdown();ma.server_close();helper.shutdown();helper.server_close()


if __name__=='__main__':main()
