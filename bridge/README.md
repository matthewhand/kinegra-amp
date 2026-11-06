# Optional development codec bridge

This opt-in Ubuntu-Max helper decodes MP3, Ogg Vorbis, FLAC, AAC/ADTS or WAV
through external FFmpeg into chunked PCM WAV for the Godot WAV path. It is
separate from the app's native MP3/Ogg Vorbis decoder. It is disabled by default,
binds only `127.0.0.1`, and does not install a persistent service.

Configure an authorized upstream origin explicitly; no installation-specific
upstream is built into this helper:

```sh
python3 bridge/codec_bridge.py --allow-ma --upstream-origin https://your-authorized-stream-origin
```

A literal private HTTP upstream also requires
`--allow-insecure-private-http`. That is explicit development transport trust,
not encrypted media delivery. A genuine existing stream URL must be obtained
through supported, authorized MA/provider behavior; the bridge never derives
one from a library/media identifier. It refuses other origins, credentials,
recognizable secret query names, redirects and inherited proxies. It never
forwards an MA API bearer to an audio endpoint.

The one-decoder session limit, bounded chunks and FFmpeg watchdog remain.
Opening upstream status/headers has separate connect and absolute header
deadlines. Output-idle/duration cancellation shuts down the HTTP source socket
before closing its buffered reader, so a drip-fed source cannot hold the input
thread's buffered read lock through cleanup. HTTP downstream writes have a
socket timeout. Partial failures close the response without appending a false
successful chunk terminator. Non-network custom sources supplied to the Python
function must provide a cooperative, nonblocking `close()` contract.

The Android app cannot directly reach Ubuntu-Max loopback. Use the app's native
decoder when supported; any temporary reverse/proxy transport must be designed
and documented separately. Do not expose this development helper on LAN or
assume it is an authenticated production media service.

Tests run with synthetic audio only:

```sh
python3 -m unittest discover -s bridge -p 'test*.py'
python3 bridge/run_local_e2e.py
```

The bridge roundtrip fixtures include actual MP3, Ogg Vorbis, WAV, FLAC and
AAC/ADTS generated and decoded by the installed FFmpeg. MP3/OGG also have a
real local HTTP-to-Godot generator/FFT test. These fixtures prove selected
synthetic codec cases; they do not prove arbitrary files, native AAC/FLAC
support or live MA playback. No private collection media is a test artifact.

Use `MA-CATALOG.md` and `ma_catalog.py` for the portable read-only catalog
contract. Older `discover_ma.py`/`real_stream_probe.py` remain installation-pinned
historical operator tools and do not silently become generic/public services.
