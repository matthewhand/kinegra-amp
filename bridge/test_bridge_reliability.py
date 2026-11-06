import io
import pathlib
import sys
import threading
import time
import unittest
import subprocess
from unittest.mock import patch
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import codec_bridge as b


class Reliability(unittest.TestCase):
    def decode(self, source=None, sink=None, **kwargs):
        processes = []
        spawn = subprocess.Popen
        def record(*a, **k):
            process = spawn(*a, **k)
            processes.append(process)
            return process
        try:
            with patch.object(b.subprocess, 'Popen', record):
                return b.decode_stream(source or io.BytesIO(b'input'), sink or io.BytesIO(), **kwargs)
        finally:
            self.assertTrue(processes)
            self.assertTrue(all(p.poll() is not None for p in processes), 'child leaked')
            self.assertFalse(any(t.name == 'bounded-codec-input' and t.is_alive() for t in threading.enumerate()))

    def test_stalled_decoder_idle(self):
        started = time.monotonic()
        with self.assertRaises(TimeoutError):
            self.decode(ffmpeg=[sys.executable, '-c', 'import time; time.sleep(10)'], idle_seconds=.12, max_seconds=2)
        self.assertLess(time.monotonic() - started, 1.5)

    def test_watchdog_duration(self):
        with self.assertRaises(TimeoutError):
            self.decode(ffmpeg=[sys.executable, '-c', 'import time; time.sleep(10)'], idle_seconds=5, max_seconds=.15)

    def test_explicit_cancellation(self):
        event = threading.Event()
        event.set()
        with self.assertRaises(InterruptedError):
            self.decode(ffmpeg=[sys.executable, '-c', 'import time; time.sleep(10)'], cancel_event=event)

    def test_backpressure_and_partial_sink(self):
        class BrokenSink:
            writes = 0
            def write(self, data):
                self.writes += 1
                if self.writes > 1:
                    raise BrokenPipeError('cancelled downstream')
        # Both pipes exceed capacity: independent input worker must make progress.
        program = 'import os; [os.write(1,b"x"*16384) for i in range(64)]; os.read(0,1)'
        with self.assertRaises(BrokenPipeError):
            self.decode(source=io.BytesIO(b'x' * 2_000_000), sink=BrokenSink(), ffmpeg=[sys.executable, '-c', program], max_seconds=2)

    def test_stalled_upstream_close(self):
        class Source:
            def __init__(self):
                self.closed = threading.Event()
            def read(self, n):
                self.closed.wait(2)
                return b''
            def close(self):
                self.closed.set()
        source = Source()
        with self.assertRaises(TimeoutError):
            self.decode(source=source, ffmpeg=[sys.executable, '-c', 'import sys; sys.stdin.buffer.read()'], idle_seconds=.12)
        self.assertTrue(source.closed.is_set())

    def test_failed_decoder_not_success(self):
        with self.assertRaises(ValueError):
            self.decode(ffmpeg=[sys.executable, '-c', 'raise SystemExit(7)'])

    def test_direct_source_success_and_redirect_rejection(self):
        import http.server
        class Source(http.server.BaseHTTPRequestHandler):
            requests = 0
            def log_message(self, *args):
                pass
            def do_GET(self):
                Source.requests += 1
                if self.path == '/redirect':
                    self.send_response(302)
                    self.send_header('Location', 'https://unvisited.invalid/')
                    self.end_headers()
                    return
                data = b'x' * 32768
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Source)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = 'http://127.0.0.1:' + str(server.server_port)
        try:
            with b.open_source(base + '/source') as source:
                sent = self.decode(source=source, ffmpeg=[sys.executable, '-c', 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read())'], max_seconds=2)
            self.assertEqual(sent, 32768)
            with self.assertRaises(b.urllib.error.URLError):
                b.open_source(base + '/redirect')
            self.assertEqual(Source.requests, 2)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(2)

    def test_real_http_drip_header_has_absolute_deadline(self):
        import http.server
        class HeaderDrip(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                try:
                    self.wfile.write(b'HTTP/1.1 200 OK\r\nX-Drip: ')
                    self.wfile.flush()
                    for _ in range(1000):
                        self.wfile.write(b'x')
                        self.wfile.flush()
                        time.sleep(.02)
                except OSError:
                    pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), HeaderDrip)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        started = time.monotonic()
        try:
            with self.assertRaises(TimeoutError):
                b.open_source('http://127.0.0.1:' + str(server.server_port) + '/', header_timeout=.15)
            self.assertLess(time.monotonic() - started, 1.2)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(2)

    def test_real_http_drip_cannot_hold_buffered_read_lock(self):
        import http.server
        import urllib.request
        class Drip(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length', '20000')
                self.end_headers()
                try:
                    for _ in range(1000):
                        self.wfile.write(b'x')
                        self.wfile.flush()
                        time.sleep(.02)
                except OSError:
                    pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Drip)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        source = urllib.request.urlopen('http://127.0.0.1:' + str(server.server_port), timeout=6)
        started = time.monotonic()
        try:
            with self.assertRaises(TimeoutError):
                self.decode(source=source, ffmpeg=[sys.executable, '-c', 'import sys; sys.stdin.buffer.read()'], max_seconds=.2, idle_seconds=.15)
            self.assertLess(time.monotonic() - started, 1.2)
            self.assertTrue(source.isclosed())
        finally:
            source.close()
            server.shutdown()
            server.server_close()
            thread.join(2)

    def test_real_http_drip_cancel_interrupts_reader(self):
        import http.server
        import urllib.request
        class Drip(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length', '20000')
                self.end_headers()
                try:
                    for _ in range(1000):
                        self.wfile.write(b'x')
                        self.wfile.flush()
                        time.sleep(.02)
                except OSError:
                    pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Drip)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        source = urllib.request.urlopen('http://127.0.0.1:' + str(server.server_port), timeout=6)
        cancelled = threading.Event()
        timer = threading.Timer(.1, cancelled.set)
        timer.start()
        started = time.monotonic()
        try:
            with self.assertRaises(InterruptedError):
                self.decode(source=source, ffmpeg=[sys.executable, '-c', 'import sys; sys.stdin.buffer.read()'], cancel_event=cancelled, max_seconds=5)
            self.assertLess(time.monotonic() - started, 1.2)
            self.assertTrue(source.isclosed())
        finally:
            timer.cancel()
            source.close()
            server.shutdown()
            server.server_close()
            thread.join(2)

    def test_single_process_limit(self):
        import http.client
        server = b.DecoderServer(('127.0.0.1', 0), allow_ma=True, upstream_origin='http://10.77.0.111:8097', allow_insecure_private=True)
        server.limiter.acquire()
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            connection.request('GET', '/stream?url=http%3A%2F%2F10.77.0.111%3A8097%2Fsynthetic')
            self.assertEqual(connection.getresponse().status, 503)
            connection.close()
        finally:
            server.limiter.release()
            server.shutdown()
            server.server_close()
            worker.join(2)

if __name__ == '__main__':
    unittest.main(verbosity=2)
