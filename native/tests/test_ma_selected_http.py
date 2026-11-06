#!/usr/bin/env python3
"""Synthetic Main→library selection→exact-own MA queue HTTP proof. No live service."""
from pathlib import Path
import http.server,json,os,socket,subprocess,sys,tempfile,threading
root=Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  obj=json.loads(self.rfile.read(int(self.headers['Content-Length'])));self.server.calls.append(obj)
  if obj['command']=='players/all':
   output='foreign' if self.server.mode=='wrong-route' else 'own-client'
   value=[{'player_id':'own-wrapper','provider':'universal_player','type':'player','available':True,'enabled':True,'active_group':None,'synced_to':None,'group_members':[],'static_group_members':[],'active_output_protocol':output,'output_protocols':[{'output_protocol_id':output,'protocol_domain':'sendspin','available':True,'derived_from':None}]}]
  else:
   assert obj['command']=='player_queues/play_media',obj['command']
   if self.server.mode=='play-lost':
    self.close_connection=True;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   value={} if self.server.mode=='play-weird' else None
  body=json.dumps({'message_id':'obsolete' if self.server.mode=='play-stale' and obj['command']=='player_queues/play_media' else obj.get('message_id'),'result':value}).encode()
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
for mode in ['track-play','playlist-play','playlist-add','wrong-client','wrong-route','stale-page','stopped-session','add-wrong-client','add-stopped-session','play-lost','play-stale','play-weird']:
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);server.mode=mode;server.calls=[]
 thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 try:
  with tempfile.TemporaryDirectory(prefix='amp-selected-http-') as state:
   env=dict(os.environ,METHEXIS_SOURCE_TEST='1',XDG_DATA_HOME=state,XDG_CONFIG_HOME=state,XDG_CACHE_HOME=state,SELECTED_MODE=mode,SELECTED_URL='http://127.0.0.1:'+str(server.server_port))
   result=subprocess.run(['timeout','20','xvfb-run','-a',sys.argv[1],'--path',str(root/'app'),'--audio-driver','Dummy','--script','res://tests/test_ma_selected_http.gd'],env=env,capture_output=True,text=True)
   text=result.stdout+result.stderr
   assert result.returncode==0 and 'SCRIPT ERROR' not in text and '\nERROR:' not in text,(mode,text)
   expected={'playlist-add':'queue_added','wrong-client':'guarded','wrong-route':'guarded','stale-page':'guarded','stopped-session':'guarded','add-wrong-client':'guarded','add-stopped-session':'guarded','play-lost':'disconnected','play-stale':'stale_reply','play-weird':'malformed_reply'}.get(mode,'play_requested')
   assert 'SELECTED_FINAL='+expected in text,(mode,text)
   writes=[x for x in server.calls if x['command']!='players/all']
   guarded=expected=='guarded'
   assert len(writes)==(0 if guarded else 1),(mode,server.calls)
   if writes:
    args=writes[0]['args'];assert args['queue_id']=='own-wrapper'
    assert args['option']==('add' if mode=='playlist-add' else 'play')
    assert args['media']==(['library://playlist/42'] if mode=='playlist-add' else 'library://playlist/42' if mode=='playlist-play' else 'library://track/7')
   if not guarded and mode!='playlist-add':assert 'SELECTED_CONTEXT=ma' in text,(mode,text)
   print('SELECTED_HTTP_PASS_'+mode,flush=True)
 finally:server.shutdown();server.server_close();thread.join()
print('SELECTED_HTTP_ALL_PASS')
