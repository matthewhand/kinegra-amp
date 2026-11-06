#!/usr/bin/env python3
"""Exercise the experimental GDNative client against a loopback-only rejection.
No MA server, user key, pairing, music, or device is touched.
"""
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time

if len(sys.argv) != 3:
    raise SystemExit('usage: test_sendspin_native.py <Godot binary> <host plugin>')
root = pathlib.Path(__file__).resolve().parent
server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen(1)
server.settimeout(8)
port = server.getsockname()[1]
received = []
listeners = []
pid_path = None
def serve():
    try:
        conn, _ = server.accept()
        server.close() # A second connect must fail promptly, not hang on backlog.
        conn.settimeout(3)
        with conn:
            data = conn.recv(8192)
            received.append(data.split(b'\r\n', 1)[0])
            # Linux procfs: find this Godot process's socket inodes, then
            # identify which of them are TCP LISTEN sockets (state 0A).
            for _ in range(50):
                if pid_path and pid_path.exists(): break
                time.sleep(.01)
            pid = int(pid_path.read_text())
            sockets = set()
            for fd in pathlib.Path(f'/proc/{pid}/fd').iterdir():
                try:
                    target = os.readlink(fd)
                    if target.startswith('socket:['): sockets.add(target[8:-1])
                except OSError:
                    pass
            for table in ('/proc/net/tcp', '/proc/net/tcp6'):
                for row in pathlib.Path(table).read_text().splitlines()[1:]:
                    fields = row.split()
                    if fields[3] == '0A' and fields[9] in sockets:
                        listeners.append(fields[1])
            conn.sendall(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
    except OSError:
        pass
worker = threading.Thread(target=serve)
worker.start()
try:
    with tempfile.TemporaryDirectory(prefix='shieldamp-sendspin-test-') as folder:
        work = pathlib.Path(folder)
        (work/'project.godot').write_text('config_version=4\n[application]\nconfig/name="Sendspin Native Test"\n')
        (work/'ShieldSendspin.gdnlib').write_text('[gd_resource type="GDNativeLibrary" format=2]\n[resource]\nsingleton=false\nload_once=true\nsymbol_prefix="godot_"\nreloadable=false\n[entry]\nX11.64="res://libshield_sendspin_x11.so"\n')
        (work/'ShieldSendspin.gdns').write_text('[gd_resource type="NativeScript" load_steps=2 format=2]\n[ext_resource path="res://ShieldSendspin.gdnlib" type="GDNativeLibrary" id=1]\n[resource]\nresource_name="ShieldSendspin"\nclass_name="ShieldSendspin"\nlibrary=ExtResource( 1 )\n')
        (work/'libshield_sendspin_x11.so').write_bytes(pathlib.Path(sys.argv[2]).read_bytes())
        (work/'test.gd').write_bytes((root/'test_sendspin_native.gd').read_bytes())
        pid_path = work/"godot.pid"
        env = dict(os.environ, SHIELDAMP_TEST_PID=str(pid_path), SHIELDAMP_TEST_URL=f'ws://127.0.0.1:{port}/sendspin', XDG_DATA_HOME=folder)
        result = subprocess.run(['xvfb-run','-a',sys.argv[1],'--path',folder,'--no-window','--script','res://test.gd'],env=env,text=True,capture_output=True,timeout=20)
        print(result.stdout)
        if "Provisioned Sendspin Pairing PSK" in result.stdout + result.stderr:
            raise SystemExit("SDK exposed pairing material in logs")
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            raise SystemExit(result.returncode)
finally:
    worker.join(9)
    server.close()
if received != [b'GET /sendspin HTTP/1.1']:
    raise SystemExit('loopback WebSocket upgrade was not attempted')
if listeners:
    raise SystemExit('unexpected SDK inbound listener')
print('NATIVE_GODOT_OUTBOUND_ONLY_PASS')
print('NATIVE_GODOT_LOOPBACK_HANDSHAKE_PASS')
