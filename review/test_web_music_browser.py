"""Real browser + Godot + synthetic MA HTTP proof; no owner library or media."""
from pathlib import Path
import argparse,subprocess,tempfile,threading,json,os,time,urllib.request,urllib.error,signal
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from playwright.sync_api import sync_playwright,expect
parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True);parser.add_argument('--project',required=True);args=parser.parse_args()
state={'unsafe':False,'fail_mutation':False,'mutations':[],'queue':[],'play_state':'paused','empty_queue':False,'item_reads':0,'route_delay':2,'discoveries':0,'fail_read_once':True,'read_attempts':0,'message_ids':[]}
def track(index):return {'item_id':str(index),'provider':'library','name':('<b>not HTML</b>' if index==2 else 'Synthetic Track '+str(index)),'media_type':'track','artists':[{'name':'Synthetic Artist'}],'album':{'name':'Synthetic Album'},'is_playable':index!=3}
class MA(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_POST(self):
  data=json.loads(self.rfile.read(int(self.headers['Content-Length'])));cmd=data['command'];v=data.get('args',{});code=200
  assert self.headers.get('Authorization')=='Bearer synthetic-library-access'
  state['message_ids'].append(data['message_id'])
  if cmd=='players/all':
   def player(id,client):return {'player_id':id,'provider':'universal_player','type':'player','available':True,'enabled':True,'active_group':None,'synced_to':None,'group_members':[],'static_group_members':[],'active_output_protocol':None,'output_protocols':[{'output_protocol_id':client,'protocol_domain':'sendspin','available':True,'derived_from':None}]}
   state['discoveries']+=1;delayed=state['route_delay']>0;state['route_delay']=max(0,state['route_delay']-1)
   result=[player('fixture-own-output','wrong-client' if state['unsafe'] or delayed else 'fixture-client'),player('unrelated-output','unrelated-client')]
  elif cmd.startswith('music/') and state['fail_read_once']:
   state['fail_read_once']=False;state['read_attempts']+=1;code=500;result={'error':'synthetic temporary read failure'}
  elif cmd in ['music/tracks/library_items','music/albums/library_items','music/playlists/library_items']:
   state['read_attempts']+=1
   kind=cmd.split('/')[1]
   rows=[track(i) for i in range(1,81)] if kind=='tracks' else [{'item_id':str(i),'provider':'library','name':'Synthetic '+kind+' '+str(i),'media_type':kind[:-1],'is_playable':True} for i in range(1,4)]
   rows=[r for r in rows if v.get('search','').lower() in r['name'].lower()];result=rows[v.get('offset',0):v.get('offset',0)+v.get('limit',25)]
  elif cmd in ['music/albums/album_tracks','music/playlists/playlist_tracks']:result=[track(i) for i in range(1,131)]
  elif cmd=='player_queues/play_media':
   assert v['queue_id']=='fixture-own-output' and v['option'] in ['add','play']
   state['mutations'].append(v)
   media=v['media'] if isinstance(v['media'],list) else [v['media']]
   for uri in media:
    assert uri.startswith('library://')
    index=uri.split('/')[-1];state['queue'].append({'queue_id':'fixture-own-output','queue_item_id':'queued-'+str(len(state['queue'])+1),'name':'Synthetic Track '+index})
   if v['option']=='play':state['play_state']='playing'
   result=None
   if state['fail_mutation']:state['fail_mutation']=False;code=500;result={'error':'synthetic ambiguous reply'}
  elif cmd=='player_queues/get' and state['empty_queue']:result={'queue_id':'fixture-own-output','state':'idle','active':False,'items':0,'current_index':None,'index_in_buffer':None,'current_item':None,'next_item':None}
  elif cmd=='player_queues/get':result={'queue_id':'fixture-own-output','state':state['play_state'],'active':True,'items':len(state['queue'])+1,'current_index':0,'index_in_buffer':0,'current_item':{'queue_item_id':'current','name':'Synthetic current'},'next_item':state['queue'][0] if state['queue'] else None}
  elif cmd=='player_queues/items':
   state['item_reads']+=1;result=state['queue'][max(0,v['offset']-1):max(0,v['offset']-1)+v['limit']]
  else:raise AssertionError(cmd)
  body=json.dumps(result).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
server=ThreadingHTTPServer(('127.0.0.1',18766),MA);threading.Thread(target=server.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='shieldamp-web-music-') as folder:
 env=dict(os.environ,XDG_CONFIG_HOME=folder+'/config',XDG_DATA_HOME=folder+'/data',XDG_CACHE_HOME=folder+'/cache')
 p=subprocess.Popen(['xvfb-run','-a',args.godot,'--path',args.project,'--audio-driver','Dummy','--script','res://tests/test_web_music_server.gd'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
 lines=[];ready=threading.Event();keys=[]
 def read():
  for line in p.stdout:
   lines.append(line)
   if 'WEB_MUSIC_READY ' in line:keys.append(line.strip().split()[-1]);ready.set()
 threading.Thread(target=read,daemon=True).start()
 checks=0
 def ck(ok,name):
  global checks
  checks+=1
  assert ok,name
 try:
  assert ready.wait(12),''.join(lines)[-4000:]
  key=keys[0];base='http://127.0.0.1:8765'
  def api(path,body=None,expected=200):
   payload=None if body is None else json.dumps(body).encode();h={'Authorization':'Bearer '+key}
   if payload is not None:h['Content-Type']='application/json'
   try:
    response=urllib.request.urlopen(urllib.request.Request(base+path,data=payload,headers=h),timeout=5);data=json.loads(response.read());code=response.status
   except urllib.error.HTTPError as e:code=e.code;data=json.loads(e.read())
   assert code==expected,(path,code,data)
   return data
  def job(path,value):
   result=api(path,value,202)
   for _ in range(120):
    value=api('/api/operations/'+result['operation'])
    if value['state']!='loading':return value
    time.sleep(.1)
   raise AssertionError('job timeout')
  state['empty_queue']=True
  empty=job('/api/queue/refresh',{})
  ck(empty['state']=='done' and not empty['queue']['items'],'empty queue is successful')
  ck(state['item_reads']==0,'empty queue never requests invalid upcoming offset')
  ck(state['discoveries']>=3,'initial queue read waits for own-output registration')
  ck(not state['mutations'],'read-only registration retries never send playback commands')
  state['empty_queue']=False
  with sync_playwright() as pw:
   browser=pw.chromium.launch(headless=True,args=['--no-sandbox']);page=browser.new_page(viewport={'width':1200,'height':1000});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   page.goto(base);page.locator('#connect').click();ck('16-character' in page.locator('#pair-error').inner_text(),'blank key error is adjacent to Connect')
   page.locator('#key').fill('0'*16);page.locator('#connect').click();expect(page.locator('#pair-error')).to_contain_text('restarted');ck(page.locator('#connect').is_enabled(),'wrong key explains restart and allows retry')
   page.evaluate('Object.defineProperty(document,"hidden",{configurable:true,get:()=>true})');page.locator('#key').fill(key);page.locator('#connect').click();page.wait_for_selector('#library-list article');ck(not page.locator('#pair').is_visible(),'explicit Connect works even for hidden embedded documents')
   ck(page.locator('#connection').inner_text()=='Connected to Kinegra Amp','clear connected indicator')
   ck(state['read_attempts']>=2,'temporary library read retries once')
   ck(not state['mutations'],'library retry sends no playback or queue mutation')
   ck(page.locator('#library-list article').count()==25,'tracks load on connect even when albums are absent')
   page.locator('[data-kind="albums"]').click();expect(page.locator('#library-list article')).to_have_count(3)
   page.locator('#library-list article').first.get_by_role('button',name='Open',exact=True).click();expect(page.locator('#library-title')).to_contain_text('1–25');ck(page.locator('#library-list article').count()==25,'open collection has first 25 tracks')
   ck(page.locator('#library-list img').count()==0 and '<b>not HTML</b>' in page.locator('#library-list').inner_text(),'library metadata is text, not injected HTML')
   ck(page.locator('#library-list article').nth(2).get_by_role('button',name='+ Add to Queue').count()==0,'unavailable track has no queue action')
   page.locator('#library-list article').first.get_by_role('button',name='+ Add to Queue',exact=True).click();expect(page.locator('#queue-list li')).to_have_count(1);ck(len(state['mutations'])==1 and state['play_state']=='paused','Add to Queue appends once without playing')
   page.locator('#queue-page').click();expect(page.locator('#queue-list li')).to_have_count(10);ck(len(state['mutations'])==2 and len(state['mutations'][-1]['media'])==24,'Queue Page appends only the 24 available visible tracks')
   page.locator('#next-page').click();expect(page.locator('#library-title')).to_contain_text('26–50');ck('Synthetic Track 26' in page.locator('#library-list').inner_text(),'collection paging reaches later tracks')
   page.locator('#search').fill('Track 126');page.locator('#search-form button').click();expect(page.locator('#library-list article')).to_have_count(1);ck('Synthetic Track 126' in page.locator('#library-list').inner_text(),'collection filtering finds a track beyond the first 100')
   page.locator('#library-list article').first.get_by_role('button',name='▶ Play',exact=True).click();expect(page.locator('#message')).to_contain_text('Play requested');ck(state['play_state']=='playing' and state['mutations'][-1]['option']=='play','explicit row Play uses owned output')
   page.locator('[data-kind="tracks"]').click();expect(page.locator('#library-title')).to_contain_text('tracks');page.locator('#search').fill('Track 75');page.locator('#search-form button').click();expect(page.locator('#library-list')).to_contain_text('Synthetic Track 75');ck(page.locator('#library-list article').count()==1,'server-side track search is available')
   page.set_viewport_size({'width':390,'height':844});ck(page.evaluate('document.documentElement.scrollWidth<=window.innerWidth'),'mobile layout has no horizontal overflow')
   ck(not errors,'browser has no script errors')
   browser.close()
  # Public API guards: no arbitrary media URI/player, no stale page, and no
  # duplicated mutation even if a caller retries the exact idempotency key.
  result=job('/api/library',{'kind':'tracks','offset':0,'search':''});page_id=result['page']['page_id'];ck(result['state']=='done','API library job completes')
  api('/api/queue/add',{'page_id':page_id,'item':'library://track/1','request_id':'invalid-id-1'},400);ck(True,'raw URI rejected')
  api('/api/queue/add',{'page_id':page_id-1,'item':0,'request_id':'stale-id-1'},409);ck(True,'stale page rejected')
  api('/api/queue/add',{'page_id':page_id,'item':0,'request_id':'wrong-player-1','player_id':'unrelated-output'},400);ck(True,'arbitrary player field rejected')
  before=len(state['mutations']);value={'page_id':page_id,'item':0,'request_id':'dedupe-proof-1'};result=job('/api/queue/add',value);duplicate=job('/api/queue/add',value);ck(result==duplicate and len(state['mutations'])==before+1,'repeated request ID does not queue twice')
  state['unsafe']=True;before=len(state['mutations']);result=job('/api/queue/add',dict(value,request_id='unsafe-proof-1'));ck(result['state']=='error' and len(state['mutations'])==before,'wrong own-output route blocks queue mutation');state['unsafe']=False
  state['fail_mutation']=True;before=len(state['mutations']);result=job('/api/queue/add',dict(value,request_id='ambiguous-proof-1'));ck(result['state']=='error' and 'unknown' in result['message'].lower() and len(state['mutations'])==before+1,'ambiguous reply is surfaced without retry')
  time.sleep(.3);ck(len(state['mutations'])==before+1,'no delayed duplicate mutation')
  ck(all(m['queue_id']=='fixture-own-output' for m in state['mutations']),'all mutations use exactly the app-owned output')
  ck(len(set(state['message_ids']))==len(state['message_ids']),'request IDs are unique across concurrent catalog instances')
  ck(not any(s in ''.join(lines) for s in ['SCRIPT ERROR','Parse Error']),'Godot fixture has no script errors')
  print('WEB_MUSIC_BROWSER_API_CHECKS='+str(checks))
 except BaseException:
  print(''.join(lines)[-5000:]);raise
 finally:
  try:os.killpg(p.pid,signal.SIGTERM)
  except ProcessLookupError:pass
  try:p.wait(timeout=5)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL)
  server.shutdown()
