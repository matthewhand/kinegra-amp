from pathlib import Path
import os,subprocess,tempfile,threading,http.client,json,signal
from playwright.sync_api import sync_playwright,expect
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True);parser.add_argument('--project',required=True);args=parser.parse_args()
godot=args.godot;project=args.project
checks=0
for mode in ['key','no_key','restricted']:
 with tempfile.TemporaryDirectory(prefix='shieldamp-access-') as state:
  env=dict(os.environ,SHIELDAMP_TEST_ACCESS=mode,XDG_DATA_HOME=state+'/data',XDG_CONFIG_HOME=state+'/cfg',XDG_CACHE_HOME=state+'/cache')
  p=subprocess.Popen(['xvfb-run','-a',godot,'--path',project,'--audio-driver','Dummy','-s','res://tests/test_web_access.gd'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,env=env,start_new_session=True)
  lines=[];ready=threading.Event();key=[]
  def reader():
   for line in p.stdout:
    lines.append(line)
    if 'WEB_ACCESS_READY ' in line:
     key.append(line.split()[2]);ready.set()
  threading.Thread(target=reader,daemon=True).start()
  try:
   assert ready.wait(10),''.join(lines)[-3000:]
   assert 'FAILURES=0' in ''.join(lines),''.join(lines)[-3000:]
   def request(path,expected,auth=None):
    c=http.client.HTTPConnection('127.0.0.1',8765,timeout=4)
    c.request('GET',path,headers={'Authorization':'Bearer '+auth} if auth else {})
    r=c.getresponse();data=r.read();c.close()
    assert r.status==expected,(mode,path,r.status,data[:120])
    return json.loads(data) if path!='/ ' and data.startswith(b'{') else data
   if mode=='restricted':
    request('/',403);request('/api/access',403);request('/api/status',403,key[0]);checks+=3
   else:
    assert request('/api/access',200)['require_key']==(mode=='key');checks+=1
    request('/api/status',401 if mode=='key' else 200);checks+=1
    request('/api/diagnostics',200,key[0]);checks+=1
    if mode=='key':request('/api/status',401,'0000000000000000');checks+=1
    with sync_playwright() as pw:
     browser=pw.chromium.launch(headless=True,args=['--no-sandbox'])
     page=browser.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
     page.goto('http://127.0.0.1:8765/')
     if mode=='key':
      expect(page.locator('#key')).to_be_visible()
      page.locator('#key').fill(key[0]);page.locator('#connect').click()
     else:expect(page.locator('#key')).to_be_hidden()
     expect(page.locator('#track')).to_contain_text('Synthetic access test')
     assert not errors,errors
     checks+=2;browser.close()
   print('MODE_PASS='+mode)
  finally:
   os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=5)
  assert not any(x in ''.join(lines) for x in ['SCRIPT ERROR','Parse Error']),''.join(lines)[-3000:]
print('WEB_ACCESS_HTTP_BROWSER_CHECKS='+str(checks))
