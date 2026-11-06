#!/usr/bin/env python3
"""Loopback-only queue serialization/ambiguous-response fixture; no live server."""
from pathlib import Path
import http.server,json,os,socket,subprocess,sys,tempfile,threading
root=Path(__file__).resolve().parents[2]
engine=sys.argv[1]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  self.server.calls.append(data)
  if data['command']=='players/all':
   own='cast-other' if self.server.mode=='wrong-route' else 'own-client'
   value=[{'player_id':'own-wrapper','provider':'universal_player','type':'player','available':True,'enabled':True,'active_group':None,'synced_to':None,'group_members':[],'static_group_members':[],'active_output_protocol':own,'output_protocols':[{'output_protocol_id':own,'protocol_domain':'cast' if self.server.mode=='wrong-route' else 'sendspin','available':True,'derived_from':None}]}]
  else:
   assert data['command']=='player_queues/play_media'
   args=data['args'];assert args['queue_id']=='own-wrapper' and args['option']=='add'
   assert args['media']==(['library://track/1','library://track/2'] if self.server.mode=='batch' else ['library://track/1'])
   if self.server.mode=='lost-result':
    self.close_connection=True;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   if self.server.mode=='stale-result':value={'message_id':'obsolete','result':None}
   else:value=None
  body=b'{invalid' if self.server.mode=='malformed-result' and data['command']=='player_queues/play_media' else json.dumps(value).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
for mode in ['single','batch','wrong-route','lost-result','malformed-result','stale-result']:
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);server.mode=mode;server.calls=[]
 threading.Thread(target=server.serve_forever,daemon=True).start()
 try:
  with tempfile.TemporaryDirectory(prefix='amp-queue-http-') as temp:
   env=dict(os.environ,METHEXIS_SOURCE_TEST='1',XDG_DATA_HOME=temp,ADD_MODE=mode,ADD_URL='http://127.0.0.1:'+str(server.server_port))
   run=subprocess.run(['timeout','20','xvfb-run','-a',engine,'--path',str(root/'app'),'--no-window','--audio-driver','Dummy','--script','res://tests/test_ma_queue_add_http.gd'],env=env,capture_output=True,text=True)
   log=run.stdout+run.stderr
   expected={'wrong-route':'unsafe_route','lost-result':'disconnected','malformed-result':'malformed_reply','stale-result':'stale_reply'}.get(mode,'queue_added')
   assert run.returncode==0 and 'QUEUE_HTTP_FINAL='+expected in log and 'SCRIPT ERROR' not in log,log
   assert 'QUEUE_HTTP_CONTEXT_NOTICES='+str(1 if mode in ['single','batch'] else 0) in log,log
   errors=[line for line in log.splitlines() if line.startswith('ERROR:')]
   if mode=='malformed-result':
    assert errors==['ERROR: Error parsing JSON at line 0: Expected key'],log
   else:assert not errors,log
   mutations=[call for call in server.calls if call['command']!='players/all']
   assert len(mutations)==(0 if mode=='wrong-route' else 1),server.calls
   assert all(call['command'] in ['players/all','player_queues/play_media'] for call in server.calls)
   if mode in ['lost-result','malformed-result','stale-result']:assert 'QUEUE_HTTP_DETAIL=Queue result unknown. Check the queue before adding again.' in log,log
   print('QUEUE_HTTP_PASS_'+mode,flush=True)
 finally:server.shutdown();server.server_close()
print('QUEUE_HTTP_ALL_PASS')
