"""Real loopback HTTP checks for the CLI; synthetic data only."""
from pathlib import Path
import contextlib,http.server,importlib.util,io,json,os,socket,threading,unittest
from unittest.mock import patch

path=Path(__file__).resolve().parents[1]/'clients/kinegra_amp_remote.py'
spec=importlib.util.spec_from_file_location('shieldamp_remote',path)
cli=importlib.util.module_from_spec(spec);spec.loader.exec_module(cli)
KEY='0123456789abcdef'

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def reply(self,status,data):
        raw=json.dumps(data).encode();self.send_response(status)
        self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        s=self.server;s.seen.append(('GET',self.path,None,self.headers.get('Authorization')))
        if self.path=='/api/access':return self.reply(200,{'require_key':s.require_key})
        if s.require_key and self.headers.get('Authorization')!='Bearer '+KEY:return self.reply(401,{})
        if s.redirect:
            self.send_response(302);self.send_header('Location','http://127.0.0.1:1/');self.end_headers();return
        if self.path.startswith('/api/operations/'):
            return self.reply(200,{'state':'loading'} if s.pending else {'state':'done','message':'Synthetic completion','page':{'page_id':7,'items':[]}})
        return self.reply(200,{'title':'Synthetic track','state':'paused'})
    def do_POST(self):
        s=self.server;body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        s.seen.append(('POST',self.path,body,self.headers.get('Authorization')))
        if self.headers.get('Authorization')!='Bearer '+KEY and s.require_key:return self.reply(401,{})
        if s.ambiguous:
            self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
        return self.reply(202,{'accepted':True} if self.path=='/api/control' else {'operation':'1','state':'loading'})

class RemoteTests(unittest.TestCase):
    def setUp(self):
        self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.server.require_key=True;self.server.redirect=False;self.server.ambiguous=False;self.server.pending=False;self.server.seen=[]
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.url='http://127.0.0.1:'+str(self.server.server_port)
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join()
    def run_cli(self,*args,key=KEY):
        out=io.StringIO();err=io.StringIO()
        with patch.dict(os.environ,{'KINEGRA_AMP_ACCESS_KEY':key}),contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
            code=cli.main(['--url',self.url,*args])
        self.assertNotIn(KEY,out.getvalue()+err.getvalue())
        return code,out.getvalue(),err.getvalue()
    def test_status_and_authenticated_transport(self):
        code,out,err=self.run_cli('status');self.assertEqual(code,0);self.assertEqual(json.loads(out)['title'],'Synthetic track')
        code,out,err=self.run_cli('play');self.assertEqual(code,0);self.assertIn('not proof of audio',err)
        self.assertEqual(self.server.seen[-1][2],{'action':'play'})
    def test_missing_key_is_actionable_and_sends_no_mutation(self):
        code,out,err=self.run_cli('play',key='');self.assertEqual(code,2);self.assertIn('KINEGRA_AMP_ACCESS_KEY',err)
        self.assertFalse(any(r[0]=='POST' for r in self.server.seen))
    def test_wrong_key_and_key_free_policy(self):
        code,out,err=self.run_cli('status',key='0000000000000000');self.assertEqual(code,2);self.assertIn('rejected',err)
        self.server.require_key=False
        code,out,err=self.run_cli('--no-key','status',key='');self.assertEqual(code,0)
        self.assertIsNone(self.server.seen[-1][3])
    def test_no_key_option_cannot_bypass_key_requirement(self):
        code,out,err=self.run_cli('--no-key','play',key='');self.assertEqual(code,2)
        self.assertFalse(any(r[0]=='POST' for r in self.server.seen))
    def test_browse_open_page_queue_paths(self):
        for args,path in [(['browse','albums','--search','Synthetic'],'/api/library'),(['open','--page-id','7','--item','0'],'/api/library/open'),(['page','--page-id','7','--offset','25'],'/api/library/page'),(['queue'],'/api/queue/refresh')]:
            code,out,err=self.run_cli(*args);self.assertEqual(code,0,err);self.assertEqual(json.loads(out)['state'],'done')
            self.assertEqual([r for r in self.server.seen if r[0]=='POST'][-1][1],path)
    def test_queue_mutation_uses_explicit_handle_and_request_id_once(self):
        code,out,err=self.run_cli('add','--page-id','7','--item','2','--request-id','synthetic-action-001')
        self.assertEqual(code,0,err);writes=[r for r in self.server.seen if r[0]=='POST'];self.assertEqual(len(writes),1)
        self.assertEqual(writes[0][2],{'page_id':7,'item':2,'request_id':'synthetic-action-001'})
    def test_ambiguous_mutation_is_never_retried(self):
        self.server.ambiguous=True
        code,out,err=self.run_cli('play-item','--page-id','7','--item','0')
        self.assertEqual(code,2);self.assertIn('No request was retried',err)
        self.assertEqual(len([r for r in self.server.seen if r[0]=='POST']),1)
    def test_redirect_does_not_forward_key(self):
        self.server.redirect=True
        code,out,err=self.run_cli('status');self.assertEqual(code,2);self.assertIn('HTTP 302',err)
    def test_bounded_polling_and_invalid_request_id(self):
        self.server.pending=True
        code,out,err=self.run_cli('--wait-seconds','1','queue');self.assertEqual(code,2);self.assertIn('No request was repeated',err)
        self.server.seen=[]
        code,out,err=self.run_cli('add-page','--page-id','7','--request-id','bad');self.assertEqual(code,2);self.assertEqual(self.server.seen,[])
    def test_origin_does_not_accept_public_urls_or_embedded_credentials(self):
        for url in ['https://192.168.1.20','http://8.8.8.8','http://0.0.0.0','http://user:pass@127.0.0.1','http://127.0.0.1/x','http://127.0.0.1?key=x','http://[::1]']:
            with self.assertRaises(cli.RemoteError):cli.origin(url)

if __name__=='__main__':unittest.main()
