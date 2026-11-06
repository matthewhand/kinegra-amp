#!/usr/bin/env python3
"""Loopback-only generated artwork fixture; no real images, services or credentials."""
import http.server, threading, tempfile, pathlib, subprocess, os, sys, io, time, signal, types
from PIL import Image
root=pathlib.Path(__file__).resolve().parents[2]
def run_fixture(args,env):
    process=subprocess.Popen(args,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
    try:output,_=process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL)
        output,_=process.communicate()
        print(output)
        raise
    return types.SimpleNamespace(returncode=process.returncode,stdout=output)
def png(edge):
    out=io.BytesIO();Image.new("RGB",(edge,edge),(30,90,130)).save(out,format="PNG");return out.getvalue()
small=png(64);large=png(512)
stats={"requests":0,"bad_auth":0,"token_in_path":0,"external_redirect":0,"bad_route":0}
class Sink(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        stats["external_redirect"]+=1
        self.send_response(200);self.end_headers()
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        stats["requests"]+=1
        if self.headers.get("Authorization")!="Bearer fictional-artwork-credential":stats["bad_auth"]+=1
        if "fictional-artwork-credential" in self.path:stats["token_in_path"]+=1
        valid=len(self.path.split("?")[0])==76 and self.path.startswith("/imageproxy/") and self.path.endswith("?size=256&fmt=png")
        if not valid:stats["bad_route"]+=1
        id=self.path[12:13]
        if id=="0":
            self.send_response(401);self.end_headers();return
        if id=="b":
            self.send_response(302);self.send_header("Location",f"http://127.0.0.1:{sink.server_port}/capture");self.end_headers();return
        content="image/png";body=small
        if id=="c":body=b"x"*524289
        elif id=="d":body=small[:16]+(4096).to_bytes(4,"big")+(4096).to_bytes(4,"big")+small[24:]
        elif id=="e":content="image/svg+xml";body=b"<svg><script>never decoded</script></svg>"
        elif id=="f":time.sleep(.5)
        elif id in "12345":body=large
        self.send_response(200);self.send_header("Content-Type",content);self.send_header("Content-Length",str(len(body)));self.end_headers()
        try:self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError):pass
sink=http.server.ThreadingHTTPServer(("127.0.0.1",0),Sink)
server=http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
for service in (sink,server):threading.Thread(target=service.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix="shieldamp-artwork-",dir=os.environ.get("SHIELDAMP_TEST_TMPDIR")) as folder:
        app=pathlib.Path(folder);(app/"scripts").mkdir()
        (app/"project.godot").write_text('config_version=4\n[application]\nconfig/name="Synthetic artwork test"\n[rendering]\nquality/driver/driver_name="GLES2"\n')
        for name in ("MAArtworkController.gd","MAArtworkPolicy.gd","ConnectionPolicy.gd"):(app/"scripts"/name).write_bytes((root/"app/scripts"/name).read_bytes())
        (app/"test.gd").write_bytes((root/"app/tests/test_ma_artwork_http.gd").read_bytes())
        env=dict(os.environ,XDG_DATA_HOME=folder,ARTWORK_TEST_ORIGIN=f"http://127.0.0.1:{server.server_port}")
        result=run_fixture(["xvfb-run","-a",sys.argv[1],"--path",folder,"--no-window","--script","res://test.gd"],env)
        print(result.stdout)
        assert result.returncode==0 and "SCRIPT ERROR" not in result.stdout and "ARTWORK_HTTP_FAILURES=0" in result.stdout
    assert stats["requests"]>=10 and all(stats[key]==0 for key in ("bad_auth","token_in_path","external_redirect","bad_route")),stats
    print("ARTWORK_LOOPBACK_PRIVACY_BOUNDS_PASS")
finally:
    for service in (server,sink):service.shutdown();service.server_close()
