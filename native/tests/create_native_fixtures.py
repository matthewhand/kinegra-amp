"""Regenerate private synthetic signals and a real C-decoded PCM fixture."""
from pathlib import Path
import ctypes as C
import hashlib
import json
import subprocess
root = Path(__file__).resolve().parents[2]
target = root / 'app/tests/fixtures'
target.mkdir(parents=True, exist_ok=True)
for codec, encoder in [('mp3', 'libmp3lame'), ('ogg', 'libvorbis')]:
    subprocess.run(['/usr/bin/ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1.2', '-ar', '44100', '-ac', '2', '-c:a', encoder, '-y', str(target / ('synthetic.' + codec))], check=True, timeout=10)
lib = C.CDLL(str(root / 'native/build/libtegra_codec_host.so'))
lib.tm_create.argtypes = [C.c_int]
lib.tm_create.restype = C.c_void_p
lib.tm_push.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
lib.tm_pull.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
lib.tm_finish.argtypes = [C.c_void_p]
lib.tm_destroy.argtypes = [C.c_void_p]
context = lib.tm_create(1)
assert context
pcm = bytearray()
try:
    data = (target / 'synthetic.mp3').read_bytes()
    source = C.create_string_buffer(data)
    assert lib.tm_push(context, source, len(data)) == len(data)
    lib.tm_finish(context)
    output = (C.c_int16 * 2048)()
    for _ in range(1000):
        got = lib.tm_pull(context, output, 1024)
        assert got >= 0
        if not got:
            break
        pcm.extend(C.string_at(C.addressof(output), got * 4))
    assert len(pcm) > 120000
finally:
    lib.tm_destroy(context)
(target / 'native_decoded_pcm16le.raw').write_bytes(pcm)
(target / 'manifest.json').write_text(json.dumps({p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in target.iterdir() if p.suffix in ['.raw', '.mp3', '.ogg']}, indent=2) + '\n')
print('SYNTHETIC_NATIVE_FIXTURES frames=', len(pcm) // 4)
