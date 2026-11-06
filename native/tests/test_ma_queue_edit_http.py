#!/usr/bin/env python3
"""Synthetic own-queue seek/edit fixture; no real MA service or device."""
from pathlib import Path
import http.server,json,os,socket,subprocess,sys,tempfile,threading,time
root=Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def date_time_string(self,timestamp=None):
  if self.server.mode=='seek-bad-date':return 'not a valid server date'
  if self.server.mode.startswith('seek-clock-skew'):timestamp=time.time()+3.5
  return super().date_time_string(timestamp)
 def do_POST(self):
  obj=json.loads(self.rfile.read(int(self.headers['Content-Length'])));cmd=obj['command'];args=obj['args'];self.server.calls.append((cmd,args));mode=self.server.mode
  if cmd=='players/all':
   output={'output_protocol_id':'own-client','protocol_domain':'cast' if mode=='clear-wrong-route' else 'sendspin','available':True,'derived_from':None}
   value=[{'player_id':'own-wrapper','provider':'universal_player','type':'player','available':True,'enabled':True,'active_group':None,'synced_to':None,'group_members':[],'static_group_members':[],'active_output_protocol':None,'output_protocols':[output]}]
  elif cmd=='player_queues/get':
   if mode=='owner-change-remove':time.sleep(.3)
   if mode=='seek-slow-clock':time.sleep(2.1)
   value={'queue_id':'own-wrapper','active':True,'state':'paused' if mode=='seek-paused' else 'playing','current_index':0,'index_in_buffer':1,'elapsed_time':20.25,'elapsed_time_last_updated':time.time()+(3.5 if mode.startswith('seek-clock-skew') else 0)-(30 if mode in ['seek-stale','seek-clock-skew-stale'] else 0),'current_item':{'queue_item_id':'current','name':'Synthetic current','duration':None if mode=='seek-radio' else 120},'next_item':{'queue_item_id':'buffered','name':'Synthetic buffered'}}
  elif cmd=='player_queues/items':
   assert args=={'queue_id':'own-wrapper','limit':10,'offset':2},args
   value=[{'queue_id':'own-wrapper','queue_item_id':'future-2','name':'Synthetic future A'},{'queue_id':'own-wrapper','queue_item_id':'future-3','name':'Synthetic future B'}]
   if mode=='remove-malformed-items':value[1]['queue_item_id']='future-2'
  else:
   assert args['queue_id']=='own-wrapper'
   if cmd=='player_queues/seek':assert isinstance(args['position'],int) and ((9<=args['position']<=12) if mode=='seek-backward' else (29<=args['position']<=32)),args
   elif cmd=='player_queues/delete_item':assert args=={'queue_id':'own-wrapper','item_id_or_index':'future-2'},args
   elif cmd=='player_queues/clear':assert args=={'queue_id':'own-wrapper','skip_stop':False},args
   else:raise AssertionError(cmd)
   if mode.endswith('-eof'):
    self.close_connection=True;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   value=None
  body=json.dumps(value).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers()
  try:self.wfile.write(body)
  except (BrokenPipeError,ConnectionResetError):pass
cases=['seek-clock-skew','seek-clock-skew-stale','seek-bad-date','seek-slow-clock','seek-forward','seek-backward','seek-paused','seek-stale','seek-radio','seek-eof','remove-valid','remove-current','remove-buffered','remove-missing','remove-malformed-items','remove-eof','owner-change-remove','clear-valid','clear-wrong-route','clear-eof']
for mode in cases:
 if os.environ.get('EDIT_CASE') and os.environ['EDIT_CASE']!=mode:continue
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);server.calls=[];server.mode=mode;thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 try:
  with tempfile.TemporaryDirectory(prefix='amp-edit-http-') as temp:
   env=dict(os.environ,METHEXIS_SOURCE_TEST='1',XDG_DATA_HOME=temp,EDIT_MODE=mode,EDIT_URL='http://127.0.0.1:'+str(server.server_port))
   run=subprocess.run(['timeout','20','xvfb-run','-a',sys.argv[1],'--path',str(root/'app'),'--no-window','--audio-driver','Dummy','--script','res://tests/test_ma_queue_edit_http.gd'],env=env,capture_output=True,text=True)
   log=run.stdout+run.stderr;ok=mode in ['seek-clock-skew','seek-forward','seek-backward','remove-valid','clear-valid'];assert run.returncode==0 and 'SCRIPT ERROR' not in log and ('EDIT_OK='+str(ok)) in log and 'EDIT_RELEASED=True' in log,(mode,log)
   writes=[(cmd,args) for cmd,args in server.calls if cmd not in ['players/all','player_queues/get','player_queues/items']]
   expected_write=ok or mode.endswith('-eof');assert len(writes)==int(expected_write),(mode,server.calls)
   if mode.endswith('-eof'):assert 'EDIT_DETAIL=TV COMMAND RESULT UNKNOWN / CHECK QUEUE' in log,(mode,log)
   print('QUEUE_EDIT_HTTP_PASS_'+mode,flush=True)
 finally:server.shutdown();server.server_close();thread.join()
print('QUEUE_EDIT_HTTP_ALL_PASS')
