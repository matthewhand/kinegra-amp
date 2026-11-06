"""Loopback protocol regression; no physical device or library credentials."""
from pathlib import Path
import argparse,subprocess,json,tempfile,os,time,socket,threading,http.client,shutil
parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True);parser.add_argument('--project',required=True);args=parser.parse_args()
with tempfile.TemporaryDirectory(prefix='shieldamp-web-test-') as state:
 env=dict(os.environ,XDG_CONFIG_HOME=state+'/config',XDG_DATA_HOME=state+'/data',XDG_CACHE_HOME=state+'/cache')
 p=subprocess.Popen(['xvfb-run','-a',args.godot,'--path',args.project,'--audio-driver','Dummy','-s','res://tests/test_web_remote.gd'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,env=env)
 lines=[];ready=threading.Event();token=[]
 def reader():
  for line in p.stdout:
   lines.append(line)
   if 'WEB_REMOTE_READY ' in line:token.append(line.strip().split()[-1]);ready.set()
 thread=threading.Thread(target=reader,daemon=True);thread.start()
 try:
  assert ready.wait(12),'Fixture did not start: '+''.join(lines)[-4000:]
  key=token[0];checks=0
  def request(method,path,body=None,headers=None,expected=200):
   c=http.client.HTTPConnection('127.0.0.1',8765,timeout=4)
   c.request(method,path,body,headers or {});r=c.getresponse();data=r.read();c.close()
   assert r.status==expected,(method,path,r.status,data[:180])
   assert r.getheader('Cache-Control')=='no-store'
   assert r.getheader('Access-Control-Allow-Origin') is None
   return data
  html=request('GET','/');assert b'Kinegra Amp Remote' in html and b'Synthetic remote track' not in html;checks+=1
  request('GET','/api/status',expected=401);checks+=1
  request('POST','/api/control','{"action":"next"}',{'Content-Type':'application/json'},expected=401);checks+=1
  h={'Authorization':'Bearer '+key}
  data=json.loads(request('GET','/api/status',headers=h));assert data['title']=='Synthetic remote track';checks+=1
  request('GET','/api/status',headers=dict(h,Origin='https://foreign.invalid'),expected=403);checks+=1
  request('GET','/api/status',headers=dict(h,Host='rebind.invalid:8765'),expected=403);checks+=1
  request('GET','/api/status?key='+key,expected=401);checks+=1
  request('POST','/api/control','{"action":"next"}',h,expected=415);checks+=1
  j=dict(h,**{'Content-Type':'application/json'})
  for payload in ['[]','{"action":"delete"}','{"action":"next","extra":true}','{bad']:
   request('POST','/api/control',payload,j,expected=400);checks+=1
  request('GET','/missing',headers=h,expected=404);checks+=1
  # Partial input must be assembled without blocking the frame thread.
  with socket.create_connection(('127.0.0.1',8765),timeout=4) as s:
   payload=('GET /api/status HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nAuthorization: Bearer '+key+'\r\n\r\n').encode()
   s.sendall(payload[:30]);time.sleep(.2);s.sendall(payload[30:]);reply=b''
   while chunk:=s.recv(4096):reply+=chunk
   assert b'200 Response' in reply and b'Synthetic remote track' in reply
  checks+=1
  # A slow client expires; another request can still complete meanwhile.
  with socket.create_connection(('127.0.0.1',8765),timeout=4) as slow:
   slow.sendall(b'GET /');request('GET','/api/status',headers=h);time.sleep(2.2);assert slow.recv(1)==b''
  checks+=1
  for raw in [b'GET / HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nHost: 127.0.0.1:8765\r\n\r\n', b'GET / HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nTransfer-Encoding: chunked\r\n\r\n', b'GET / HTTP/1.1\r\nX: '+b'x'*6200]:
   with socket.create_connection(('127.0.0.1',8765),timeout=4) as s:
    s.sendall(raw);reply=s.recv(4096);assert b'200 Response' not in reply
   checks+=1
  for action in ['play','pause','previous','next','stop']:
   request('POST','/api/control',json.dumps({'action':action}),j,expected=202);checks+=1;time.sleep(.18)
  assert p.wait(timeout=5)==0,''.join(lines)[-3000:]
  assert not any(term in ''.join(lines) for term in ['SCRIPT ERROR','Parse Error'])
  print('WEB_REMOTE_HTTP_CHECKS='+str(checks));print(next(x.strip() for x in lines if 'WEB_REMOTE_CHECKS=' in x))
 except BaseException:
  p.terminate();print(''.join(lines)[-5000:]);raise
