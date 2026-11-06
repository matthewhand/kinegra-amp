#!/usr/bin/env python3
"""Loopback-only playlist paging: real HTTP coordinator, no private services."""
from pathlib import Path
import http.server,json,os,subprocess,sys,tempfile,threading
root=Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  value=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  assert value['command']=='music/playlists/playlist_tracks'
  args=value['args'];assert set(args)=={'item_id','provider_instance_id_or_domain','force_refresh','allow_dynamic_tracks'}
  assert args['item_id']=='1' and args['provider_instance_id_or_domain']=='library' and args['allow_dynamic_tracks'] is False
  self.server.calls+=1;mode=self.server.mode
  assert args['force_refresh']==(mode=='changing' and self.server.calls==2)
  count={'empty':0,'one':1,'large':500,'changing':1 if self.server.calls==2 else 500,'malformed':0,'oversized':0}[mode]
  result=[{'item_id':str(i+1),'provider':'library','name':'Synthetic '+str(i),'media_type':'track','is_playable':True} for i in range(count)]
  if mode=='malformed':result=[{'broken':True}]
  body=json.dumps(result).encode() if mode!='oversized' else b'['+b' '*(2097152+10)+b']'
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers()
  try:self.wfile.write(body)
  except (BrokenPipeError,ConnectionResetError):pass
for mode in ['empty','one','large','changing','malformed','oversized']:
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);server.mode=mode;server.calls=0
 thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 try:
  with tempfile.TemporaryDirectory(prefix='amp-playlist-http-') as temp:
   env=dict(os.environ,METHEXIS_SOURCE_TEST='1',XDG_DATA_HOME=temp,PLAYLIST_MODE=mode,PLAYLIST_URL='http://127.0.0.1:'+str(server.server_port))
   run=subprocess.run(['timeout','20','xvfb-run','-a',sys.argv[1],'--path',str(root/'app'),'--audio-driver','Dummy','--script','res://tests/test_ma_playlist_http.gd'],env=env,capture_output=True,text=True)
   text=run.stdout+run.stderr
   assert run.returncode==0 and 'PLAYLIST_HTTP_PASS_'+mode in text and 'SCRIPT ERROR' not in text,(mode,text)
   assert server.calls==(2 if mode=='changing' else 1),(mode,server.calls)
   print('PLAYLIST_HTTP_PASS_'+mode,flush=True)
 finally:server.shutdown();server.server_close();thread.join()
print('PLAYLIST_HTTP_ALL_PASS')
