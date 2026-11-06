#!/usr/bin/env python3
"""Optional, explicitly started read-only exporter for an owner's local music.

No Music Assistant credentials, discovery, remote URLs or provider downloads.
MP4/M4A/FLAC/WAV are converted to MP3 on this host, never on the Shield.
"""
import argparse
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

MAX_BYTES = 64 * 1024 * 1024
FORMATS = {'.mp3', '.ogg', '.m4a', '.mp4', '.aac', '.flac', '.wav'}


class Source:
    def __init__(self, root, cache, key, allowed):
        self.root = Path(root).resolve(strict=True)
        self.cache = Path(cache).resolve()
        self.cache.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.key = key
        self.allowed = {str(ipaddress.ip_address(x)) for x in allowed}
        self.lock = threading.Lock()

    def resolve(self, relative):
        if not isinstance(relative, str) or len(relative) > 1024 or not relative:
            raise ValueError('Unsupported local path')
        if relative.startswith(('/', '\\')) or any(ord(c) < 32 for c in relative) or '\\' in relative or ':' in relative:
            raise ValueError('Unsupported local path')
        if any(x in ('', '.', '..') for x in relative.split('/')):
            raise ValueError('Unsupported local path')
        path = (self.root / relative).resolve(strict=True)
        if not path.is_relative_to(self.root) or not path.is_file() or path.suffix.lower() not in FORMATS:
            raise ValueError('Local audio file unavailable')
        return path

    def prepare(self, relative):
        with self.lock:
            path = self.resolve(relative)
            stat = path.stat()
            if stat.st_size < 4 or stat.st_size > MAX_BYTES * 8:
                raise ValueError('Source file exceeds limit')
            identity = hashlib.sha256((relative + ':' + str(stat.st_size) + ':' + str(stat.st_mtime_ns)).encode()).hexdigest()
            suffix = path.suffix.lower() if path.suffix.lower() in ('.mp3', '.ogg') else '.mp3'
            receipt = self.cache / (identity + '.json')
            if receipt.is_file():
                value = json.loads(receipt.read_text())
                candidate = self.cache / value['file']
                if re.fullmatch(r'[a-f0-9]{64}\.(mp3|ogg)', value['file']) and candidate.is_file() and candidate.stat().st_size == value['bytes']:
                    return value
            if shutil.disk_usage(self.cache).free < MAX_BYTES + 256 * 1024 * 1024:
                raise ValueError('Exporter storage is full')
            temporary = self.cache / (identity + '.part' + suffix)
            try:
                if path.suffix.lower() in ('.mp3', '.ogg'):
                    if stat.st_size > MAX_BYTES:
                        raise ValueError('Audio exceeds per-track limit')
                    shutil.copyfile(path, temporary)
                else:
                    # Protocol restrictions prevent playlists/containers opening remote resources.
                    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-protocol_whitelist', 'file,pipe',
                                    '-i', str(path), '-map', '0:a:0', '-vn', '-map_metadata', '-1',
                                    '-threads', '1', '-c:a', 'libmp3lame', '-b:a', '192k',
                                    '-fs', str(MAX_BYTES + 1), '-y', str(temporary)],
                                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
                count = temporary.stat().st_size
                if not 4 <= count <= MAX_BYTES:
                    raise ValueError('Audio exceeds per-track limit')
                with temporary.open('rb') as f:
                    header = f.read(4)
                    f.seek(0)
                    digest = hashlib.file_digest(f, 'sha256').hexdigest()
                if suffix == '.ogg' and header != b'OggS' or suffix == '.mp3' and not (header.startswith(b'ID3') or header[0] == 255 and header[1] & 224 == 224):
                    raise ValueError('Unsupported audio content')
                name = digest + suffix
                temporary.replace(self.cache / name)
                value = {'sha256': digest, 'bytes': count, 'file': name}
                receipt.write_text(json.dumps(value))
                return value
            finally:
                temporary.unlink(missing_ok=True)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 4
    def __init__(self, address, source):
        self.source = source
        self.slots = threading.BoundedSemaphore(4)
        super().__init__(address, Handler)

    def process_request(self, request, address):
        if not self.slots.acquire(False):
            request.close()
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    server_version = 'LocalAudioSource/1'
    def setup(self):
        super().setup()
        self.connection.settimeout(135)

    def log_message(self, *_):
        pass  # Paths, keys and titles never enter server logs.

    def authenticated(self):
        source = self.server.source
        return self.client_address[0] in source.allowed and hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + source.key)

    def reply(self, code, value):
        data = json.dumps(value).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if not self.authenticated():
            self.reply(403, {'error': 'Access denied'})
            return
        if self.path != '/prepare' or self.headers.get('Transfer-Encoding'):
            self.reply(400, {'error': 'Invalid request'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 2 <= size <= 2048:
                raise ValueError()
            body = json.loads(self.rfile.read(size))
            result = self.server.source.prepare(body.get('path'))
            self.reply(200, result)
        except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError):
            self.reply(422, {'error': 'Local audio unavailable, unsupported, too large or conversion failed'})

    def do_GET(self):
        if not self.authenticated():
            self.reply(403, {'error': 'Access denied'})
            return
        name = urlsplit(self.path).path.removeprefix('/audio/')
        if self.path != '/audio/' + name or not re.fullmatch(r'[a-f0-9]{64}\.(mp3|ogg)', name):
            self.reply(404, {'error': 'Audio unavailable'})
            return
        try:
            with (self.server.source.cache / name).open('rb') as f:
                size = os.fstat(f.fileno()).st_size
                if not 4 <= size <= MAX_BYTES:
                    raise ValueError()
                self.send_response(200)
                self.send_header('Content-Type', 'audio/mpeg' if name.endswith('.mp3') else 'audio/ogg')
                self.send_header('Content-Length', str(size))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                shutil.copyfileobj(f, self.wfile, 65536)
        except (OSError, ValueError):
            self.close_connection = True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True)
    p.add_argument('--cache', required=True)
    p.add_argument('--key-file', required=True)
    p.add_argument('--bind', default='127.0.0.1')
    p.add_argument('--allow', action='append', required=True, help='Exact client IPv4; repeat for each client')
    p.add_argument('--port', type=int, default=8766)
    a = p.parse_args()
    address = ipaddress.IPv4Address(a.bind)
    if not (address.is_loopback or address in ipaddress.ip_network((0x0a000000, 8)) or address in ipaddress.ip_network('172.16.0.0/12') or address in ipaddress.ip_network('192.168.0.0/16')):
        p.error('Bind to a private IPv4 address')
    key_path = Path(a.key_file)
    key = key_path.read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', key) or key_path.stat().st_mode & 0o077:
        p.error('Key file must be private and contain a 32–128 character random key')
    Server((str(address), a.port), Source(a.root, a.cache, key, a.allow)).serve_forever()


if __name__ == '__main__':
    main()
