from pathlib import Path
import http.server
import subprocess
import os
import threading
root = Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path not in ['/synthetic.mp3', '/synthetic.ogg']:
            self.send_error(404)
            return
        data = (root / 'app/tests/fixtures' / self.path.removeprefix('/')).read_bytes()
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        for at in range(0, len(data), 127):
            self.wfile.write(data[at:at + 127])
            self.wfile.flush()
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    engine = os.environ['GODOT_BIN']
    result = subprocess.run([engine, '--path', str(root / 'app'), '--script', 'res://tests/test_native_http.gd', '--native-test-port', str(server.server_port)], capture_output=True, text=True, timeout=20)
    print(result.stdout + result.stderr)
    assert result.returncode == 0 and 'NATIVE_HTTP_FAILURES=[]' in result.stdout and 'SCRIPT ERROR' not in result.stderr
finally:
    server.shutdown()
    server.server_close()
    thread.join(2)
