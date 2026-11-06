#!/usr/bin/env python3
"""Opt-in *development* MA codec bridge: only loopback listener, no HA/MA writes.

Real MP3, Ogg Vorbis, FLAC, or WAV bytes are decoded by local FFmpeg to bounded
22050-Hz stereo s16le chunks. The Shield Godot client consumes PCM WAV and
analyzes those samples using its actual AudioEffectSpectrumAnalyzer.
Never expose this service on LAN or tailnet without a separate security design.
"""
import argparse
import ipaddress
import socket
from ma_catalog import origin, CatalogError
import os
import selectors
import contextlib
import http.server
import http.client
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

BIND_HOST = "127.0.0.1"
CHUNK = 16384
MAX_SECONDS = 900
WAV_HEADER = (
    b"RIFF" + struct.pack("<I", 0xffffffff) + b"WAVEfmt " +
    struct.pack("<IHHIIHH", 16, 1, 2, 22050, 88200, 4, 16) +
    b"data" + struct.pack("<I", 0xffffffff)
)
FFMPEG_ARGS = (
    "/usr/bin/ffmpeg", "-nostdin", "-hide_banner", "-nostats",
    "-loglevel", "fatal", "-threads", "1", "-i", "pipe:0",
    "-map", "0:a:0", "-vn", "-sn", "-dn", "-ac", "2",
    "-ar", "22050", "-c:a", "pcm_s16le", "-f", "s16le", "pipe:1"
)


def validate_ma_url(value, allowed_origin=""):
    """Fail closed: explicit installation origin only; never infer a stream URL."""
    try:
        allowed_origin = origin(allowed_origin)
    except CatalogError:
        raise ValueError("upstream origin is not configured") from None
    if not isinstance(value, str) or len(value) > 2048:
        raise ValueError("bad URL length")
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("control character")
    parsed = urllib.parse.urlsplit(value)
    if ((parsed.scheme + "://" + parsed.netloc).lower() != allowed_origin
            or parsed.username is not None or parsed.password is not None
            or parsed.fragment or any(name in parsed.query.lower() for name in ("token=", "password=", "authorization="))
            or not parsed.path.startswith("/")
            or parsed.path.startswith("//") or "\\" in parsed.path
            or ".." in urllib.parse.unquote(parsed.path).split("/")):
        raise ValueError("MA URL not allowlisted")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def open_source(url, connect_timeout=6, header_timeout=6):
    """Direct origin connection, no proxies/redirects; absolute header deadline.

    A per-read socket timeout alone does not stop drip-fed status/headers. The
    timer shuts down the established socket even while HTTPResponse.readline()
    holds its buffered lock. Decoder/body cancellation handles the next stage.
    """
    parsed = urllib.parse.urlsplit(url)
    cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    connection = cls(parsed.hostname, parsed.port, timeout=connect_timeout)
    expired = threading.Event()
    timer = None
    try:
        connection.connect()
        upstream_socket = connection.sock

        def interrupt_headers():
            expired.set()
            with contextlib.suppress(OSError):
                upstream_socket.shutdown(socket.SHUT_RDWR)

        timer = threading.Timer(header_timeout, interrupt_headers)
        timer.daemon = True
        timer.start()
        path = parsed.path + (("?" + parsed.query) if parsed.query else "")
        connection.request("GET", path, headers={
            "Accept": "audio/mpeg, audio/ogg, audio/wav, audio/flac, application/octet-stream",
            "User-Agent": "TegraMilkdrop-dev-codec-bridge/0.3",
            "Connection": "close",
        })
        response = connection.getresponse()
        if expired.is_set():
            response.close()
            raise TimeoutError("upstream header deadline reached")
        if response.status != 200:
            response.close()
            raise urllib.error.URLError("upstream rejected request")
        return response
    except (OSError, http.client.HTTPException):
        connection.close()
        if expired.is_set():
            raise TimeoutError("upstream header deadline reached") from None
        raise urllib.error.URLError("upstream connection failed") from None
    finally:
        if timer is not None:
            timer.cancel()


def decode_stream(source, sink, ffmpeg=FFMPEG_ARGS, max_seconds=MAX_SECONDS,
                  idle_seconds=10, cancel_event=None):
    """Return converted audio byte count. O(CHUNK) transient IO memory.
    Drains ffmpeg stdin and stdout on independent threads to avoid pipe deadlock.
    Caller supplies source stream and sink; FFmpeg is never given upstream URL.
    """
    # urllib HTTPResponse wraps a socket in a buffered reader. Closing that
    # reader from another thread can block behind its read lock. Capture the
    # socket before the input worker starts, and shutdown it before close/join.
    source_socket = getattr(getattr(getattr(source, "fp", None), "raw", None), "_sock", None)

    def interrupt_http_source():
        if source_socket is not None:
            with contextlib.suppress(OSError):
                source_socket.shutdown(socket.SHUT_RDWR)

    proc = subprocess.Popen(
        ffmpeg, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, close_fds=True, shell=False
    )
    stop = threading.Event()
    expired = threading.Event()
    input_errors = []
    # Never leave a blocked stdout.read() alive beyond this bounded session.
    def timeout_kill():
        expired.set()
        stop.set()
        if proc.poll() is None:
            proc.kill()
        interrupt_http_source()
    watchdog = threading.Timer(max_seconds, timeout_kill)
    watchdog.daemon = True
    watchdog.start()

    def supply():
        count = 0
        try:
            while not stop.is_set() and count < 1024 * 1024 * 1024:
                data = source.read(CHUNK)
                if not data:
                    break
                if len(data) > CHUNK:
                    raise ValueError("upstream violated chunk limit")
                proc.stdin.write(data)
                count += len(data)
        except (OSError, BrokenPipeError, ValueError) as exc:
            if not stop.is_set():
                input_errors.append(type(exc).__name__)
        finally:
            with contextlib.suppress(OSError):
                proc.stdin.close()

    worker = threading.Thread(target=supply, name="bounded-codec-input", daemon=True)
    worker.start()
    sent = 0
    selector = selectors.DefaultSelector()
    os.set_blocking(proc.stdout.fileno(), False)
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + max_seconds
    last_output = time.monotonic()
    try:
        sink.write(WAV_HEADER)
        while True:
            now = time.monotonic()
            if cancel_event is not None and cancel_event.is_set():
                raise InterruptedError("decoder cancelled")
            if expired.is_set() or now >= deadline:
                raise TimeoutError("source duration limit reached")
            if now - last_output >= idle_seconds:
                raise TimeoutError("decoder output idle limit reached")
            if not selector.select(min(0.05, max(0.001, deadline - now))):
                continue
            chunk = os.read(proc.stdout.fileno(), CHUNK)
            if not chunk:
                break
            sink.write(chunk)
            sent += len(chunk)
            last_output = time.monotonic()
        if expired.is_set():
            raise TimeoutError("source duration limit reached")
        code = proc.wait(timeout=min(3, max(0.01, deadline - time.monotonic())))
        if input_errors or code != 0 or sent == 0:
            raise ValueError("decoder or upstream failed")
        return sent
    finally:
        watchdog.cancel()
        stop.set()
        selector.close()
        if proc.poll() is None:
            proc.kill()
        with contextlib.suppress(subprocess.TimeoutExpired):
            proc.wait(timeout=3)
        interrupt_http_source()
        # HTTP socket shutdown releases the buffered read lock. Non-network
        # sources must provide a cooperative, nonblocking close() contract.
        with contextlib.suppress(OSError, ValueError):
            source.close()
        worker.join(timeout=1)
        if worker.is_alive():
            raise RuntimeError("upstream did not honor cancellation")
        with contextlib.suppress(OSError, ValueError):
            proc.stdout.close()


class ChunkedSink:
    """HTTP/1.1 streaming body framing; bounded chunk writes."""
    def __init__(self, stream):
        self.stream = stream

    def write(self, payload):
        if not payload:
            return
        if len(payload) > CHUNK:
            # WAV header is small, PCM chunks are CHUNK-sized.
            raise ValueError("oversized HTTP chunk")
        self.stream.write(("%X\r\n" % len(payload)).encode("ascii"))
        self.stream.write(payload)
        self.stream.write(b"\r\n")
        self.stream.flush()

    def finish(self):
        self.stream.write(b"0\r\n\r\n")
        self.stream.flush()


class DecoderServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, address, allow_ma=False, upstream_origin="", allow_insecure_private=False):
        if address[0] != BIND_HOST:
            raise ValueError("decoder must bind loopback only")
        self.upstream_origin = origin(upstream_origin) if upstream_origin else ""
        if self.upstream_origin.startswith("http://"):
            host = urllib.parse.urlsplit(self.upstream_origin).hostname
            try:
                address_value = ipaddress.ip_address(host)
            except ValueError:
                raise ValueError("cleartext upstream requires a literal private IP") from None
            if not allow_insecure_private or not (address_value.is_private or address_value.is_loopback):
                raise ValueError("cleartext upstream requires explicit private-development trust")
        self.allow_ma = allow_ma and bool(self.upstream_origin)
        self.limiter = threading.BoundedSemaphore(1)
        super().__init__(address, BridgeHandler)


class BridgeHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        # Do not log MA source URLs (which may include opaque stream IDs).
        return

    def do_GET(self):
        self.close_connection = True
        if len(self.path) > 4096:
            self.send_error(414, "request too long")
            return
        try:
            parts = urllib.parse.urlsplit(self.path)
        except ValueError:
            self.send_error(400, "bad query")
            return
        args = urllib.parse.parse_qs(parts.query, keep_blank_values=True)
        if parts.path != "/stream" or not self.server.allow_ma:
            self.send_error(404, "disabled")
            return
        if list(args) != ["url"] or len(args["url"]) != 1:
            self.send_error(400, "bad query")
            return
        try:
            url = validate_ma_url(args["url"][0], self.server.upstream_origin)
        except ValueError:
            self.send_error(400, "invalid upstream URL")
            return
        if not self.server.limiter.acquire(blocking=False):
            self.send_error(503, "decoder busy")
            return
        try:
            with open_source(url) as source:
                self.connection.settimeout(10)
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "close")
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                sink = ChunkedSink(self.wfile)
                decode_stream(source, sink)
                sink.finish()
        except (urllib.error.URLError, OSError, TimeoutError, ValueError, subprocess.TimeoutExpired) as exc:
            # No source URL or response bodies in logs.
            print("codec bridge request ended:", type(exc).__name__, flush=True)
        finally:
            self.server.limiter.release()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--allow-ma", action="store_true",
                        help="explicit opt-in to only pinned MA upstream, still loopback-only")
    parser.add_argument("--port", type=int, default=18097)
    parser.add_argument("--upstream-origin", default="",
                        help="explicit authorized upstream origin; no private installation address is built in")
    parser.add_argument("--allow-insecure-private-http", action="store_true",
                        help="explicit development-only trust for a literal private HTTP upstream")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port range 1024-65535")
    if not args.allow_ma:
        parser.error("no service started by default; use --allow-ma for manually scoped testing")
    if not args.upstream_origin:
        parser.error("--upstream-origin is required; no default upstream is configured")
    try:
        server = DecoderServer((BIND_HOST, args.port), allow_ma=True,
                               upstream_origin=args.upstream_origin,
                               allow_insecure_private=args.allow_insecure_private_http)
    except (CatalogError, ValueError):
        parser.error("invalid upstream origin or missing transport trust")
    try:
        print("development decoder bound to 127.0.0.1; stop with Ctrl+C", flush=True)
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
