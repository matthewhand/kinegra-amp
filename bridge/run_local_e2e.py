"""One-shot bounded synthetic MP3/OGG -> loopback HTTP -> real Godot FFT test."""
import http.server
import io
import pathlib
import subprocess
import os
import threading
from codec_bridge import decode_stream, ChunkedSink

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENGINE = os.environ['GODOT_BIN']


def sample_for(codec):
    cmd = [
        "/usr/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=2.0",
        "-ar", "48000", "-ac", "2",
        "-f", "mp3" if codec == "mp3" else "ogg",
        "-c:a", "libmp3lame" if codec == "mp3" else "libvorbis", "pipe:1"
    ]
    return subprocess.run(cmd, capture_output=True, timeout=12, check=True).stdout


class SyntheticHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path not in ("/stream?codec=mp3", "/stream?codec=ogg"):
            self.send_error(404)
            return
        codec = self.path.split("=")[-1]
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Connection", "close")
        self.end_headers()
        sink = ChunkedSink(self.wfile)
        sent = decode_stream(io.BytesIO(self.server.fixtures[codec]), sink, max_seconds=6)
        sink.finish()


def main():
    # Fail closed if port already in use, don't disturb other processes.
    server = http.server.HTTPServer(("127.0.0.1", 18097), SyntheticHandler)
    server.fixtures = {codec: sample_for(codec) for codec in ("mp3", "ogg")}
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for codec in ("mp3", "ogg"):
            cmd = [ENGINE, "--path", str(ROOT / "app"), "--script",
                   "res://tests/test_network_fft.gd"]
            if codec == "ogg":
                cmd.append("--use-ogg")
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=12,
                                  cwd=str(ROOT))
            print(proc.stdout + proc.stderr, flush=True)
            if proc.returncode != 0 or "PASS: decoded streamed codec" not in proc.stdout:
                raise RuntimeError("synthetic E2E failed: " + codec)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


if __name__ == "__main__":
    main()
