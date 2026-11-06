extends Node
# Bounded HTTP WAV/PCM playback; MP3, OGG, FLAC require a separate decoder.
signal message(text)
signal playing(is_playing)
signal state_changed(state)
signal pcm_observed(epoch, rms, playback_ms, latency_ms)

const RATE = 22050
const MAX_HEADER_BYTES = 65536
const MAX_CHUNK = 65536
const MAX_DECODE_PER_TICK = 4096
const CONNECT_TIMEOUT_MS = 8000
const HEADER_TIMEOUT_MS = 15000
const READ_IDLE_TIMEOUT_MS = 10000
var rate = RATE
var channels = 2
# One bounded read of lookahead permits a header ending at the 64KiB limit.
var max_pending_bytes = MAX_HEADER_BYTES + MAX_CHUNK
var client = null
var stream = null
var playback = null
var pending = PoolByteArray()
var offset = 0
var header_ok = false
var header_scanner = preload("res://scripts/WavHeader.gd").new()
var request_sent = false
var active = false
var endpoint_path = ""
var state = "stopped"
var opened_at = 0
var requested_at = 0
var last_read_at = 0
var eof = false
var data_size = -1
var received_pcm = 0
var decoded_frames = 0
var generator_capacity = 0
var epoch = 0
var paused = false
var pause_started_at = 0
var last_url = ""
var last_pcm_at = -1
var last_rms = 0.0
var playback_time_ms = 0.0
var queued_latency_ms = 0.0
var configured_origin = ""
var trust_private_cleartext = false
var policy = preload("res://scripts/ConnectionPolicy.gd").new()

func configure(origin, trust_cleartext=false):
    stop()
    configured_origin = str(origin).strip_edges().trim_suffix("/")
    trust_private_cleartext = trust_cleartext

func _now():
    return OS.get_ticks_msec()

func _state(value):
    state = value
    emit_signal("state_changed", state)

func _ready():
    stream = AudioStreamPlayer.new()
    stream.name = "Audio"
    add_child(stream)
    stream.bus = "Milkdrop"

func start(url):
    stop()
    var value = str(url).strip_edges()
    var installation = policy.origin(configured_origin, ["http", "https"], trust_private_cleartext)
    # Legacy loopback fixture transport is explicit development-only; never a LAN fallback.
    if configured_origin.empty() and value.begins_with("http://127.0.0.1:18097/"):
        installation = policy.origin("http://127.0.0.1:18097", ["http"], true)
    if installation.empty() or not value.begins_with(installation["prefix"] + "/"):
        _fail("Set the authorized stream origin and transport trust first")
        return
    if value.length() > 2048 or value.find("#") != -1 or value.find("@") != -1:
        _fail("Invalid stream URL")
        return
    for i in range(value.length()):
        if value.ord_at(i) < 32 or value.ord_at(i) == 127:
            _fail("Invalid stream URL")
            return
    endpoint_path = value.substr(installation["prefix"].length())
    if endpoint_path.begins_with("//") or "\\" in endpoint_path:
        _fail("Invalid stream path")
        return
    for secret in ["token=", "authorization=", "password=", "access_token="]:
        if secret in endpoint_path.to_lower():
            _fail("Credentials must not be placed in stream URLs")
            return
    last_url = value
    client = HTTPClient.new()
    client.read_chunk_size = MAX_CHUNK
    var err = client.connect_to_host(installation["host"], installation["port"], installation["secure"])
    if err != OK:
        _fail("HTTP connect failed; retry or cancel")
        return
    _begin_session()

func _begin_session():
    opened_at = _now()
    requested_at = opened_at
    last_read_at = opened_at
    active = true
    _state("connecting")
    emit_signal("message", "Opening PCM WAV; Stop cancels, Stream retries")

func set_paused(value):
    if not active or playback == null:
        return false
    if paused == bool(value):
        return true
    paused = bool(value)
    stream.stream_paused = paused
    if paused:
        last_pcm_at = -1
        last_rms = 0.0
    if paused:
        pause_started_at = _now()
        _state("paused")
    else:
        var elapsed_pause = _now() - pause_started_at
        opened_at += elapsed_pause
        requested_at += elapsed_pause
        last_read_at += elapsed_pause
        _state("playing")
    return true

func stop():
    paused = false
    epoch += 1
    last_pcm_at = -1
    last_rms = 0.0
    playback_time_ms = 0.0
    queued_latency_ms = 0.0
    active = false
    if client != null:
        client.close()
        client = null
    if stream != null:
        stream.stop()
        stream.stream_paused = false
        # Replace the generator to discard buffered frames from the old source.
        var gen = AudioStreamGenerator.new()
        gen.mix_rate = RATE
        gen.buffer_length = 0.30
        stream.stream = gen
    playback = null
    pending = PoolByteArray()
    offset = 0
    header_ok = false
    request_sent = false
    eof = false
    rate = RATE
    channels = 2
    max_pending_bytes = MAX_HEADER_BYTES + MAX_CHUNK
    data_size = -1
    received_pcm = 0
    decoded_frames = 0
    generator_capacity = 0
    endpoint_path = ""
    _state("stopped")
    emit_signal("playing", false)

func _notification(what):
    if what == MainLoop.NOTIFICATION_APP_PAUSED:
        stop()

func _exit_tree():
    if client != null:
        client.close()
    if stream != null:
        stream.stop()
    last_url = ""

func _process(_delta):
    if not active or client == null or paused:
        return
    if not eof:
        client.poll()
        var status = client.get_status()
        if status == HTTPClient.STATUS_CONNECTED:
            if not request_sent:
                if client.request(HTTPClient.METHOD_GET, endpoint_path, ["Accept: audio/wav, audio/wave"]) != OK:
                    _fail("HTTP request failed; retry or cancel")
                    return
                request_sent = true
                requested_at = _now()
                last_read_at = requested_at
                _state("header")
            else:
                eof = true
        elif status == HTTPClient.STATUS_BODY:
            if client.get_response_code() != 200:
                _fail("HTTP source rejected request; retry or cancel")
                return
            # Header fragments must continue reading even when pending is nonempty.
            # Capacity is measured after compaction to bound the physical allocation.
            if offset > 32768 or pending.size() + MAX_CHUNK > max_pending_bytes:
                _compact_pending()
            if pending.size() <= max_pending_bytes - MAX_CHUNK:
                var chunk = client.read_response_body_chunk()
                if chunk.size() > MAX_CHUNK or pending.size() + chunk.size() > max_pending_bytes:
                    _fail("PCM read buffer exceeded bounded allocation")
                    return
                if chunk.size() > 0:
                    last_read_at = _now()
                    pending.append_array(chunk)
                    if header_ok:
                        received_pcm += chunk.size()
            else:
                # Local audio backpressure is not a silent remote server.
                last_read_at = _now()
        elif status == HTTPClient.STATUS_DISCONNECTED or (status == HTTPClient.STATUS_CONNECTION_ERROR and header_ok):
            # Godot 3 can report CONNECTION_ERROR when a chunked close-delimited
            # response ends. Finite WAV lengths and partial PCM frames still fail.
            # A live-size sentinel cannot prove that the remote intended to end.
            eof = true
        elif status in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_SSL_HANDSHAKE_ERROR]:
            _fail("WAV connection failed; retry or cancel")
            return
    if not header_ok:
        var bounded_header = pending if pending.size() <= MAX_HEADER_BYTES else pending.subarray(0, MAX_HEADER_BYTES - 1)
        var header = header_scanner.scan_header(bounded_header)
        if header.get("status") == "invalid":
            _fail("Unsupported or oversized WAV header")
            return
        if header.get("status") == "ok":
            offset = int(header["data_offset"])
            rate = int(header["sample_rate"])
            channels = int(header["channels"])
            data_size = int(header["data_size"])
            received_pcm = pending.size() - offset
            max_pending_bytes = int(rate * channels * 2 * 4.65)
            _compact_pending()
            var gen = AudioStreamGenerator.new()
            gen.mix_rate = rate
            gen.buffer_length = 0.30
            stream.stream = gen
            header_ok = true
            stream.play()
            playback = stream.get_stream_playback()
            generator_capacity = playback.get_frames_available()
            _state("playing")
            emit_signal("playing", true)
            emit_signal("message", "WAV playing: live spectrum enabled")
    if header_ok:
        if eof and ((data_size >= 0 and received_pcm < data_size) or (pending.size() - offset) % (channels * 2) != 0):
            _fail("Truncated PCM source; retry or cancel")
            return
        _fill_audio()
        if offset > 32768:
            _compact_pending()
        if data_size >= 0 and decoded_frames * channels * 2 == data_size:
            eof = true
        if eof and (pending.size() == offset or (data_size >= 0 and decoded_frames * channels * 2 == data_size)):
            _state("draining")
            if playback.get_frames_available() >= generator_capacity:
                stop()
                _state("ended")
                emit_signal("message", "PCM source ended")
            return
    if eof:
        if not header_ok:
            _fail("Truncated WAV header; retry or cancel")
        elif (data_size >= 0 and received_pcm < data_size) or (pending.size() - offset) % (channels * 2) != 0:
            _fail("Truncated PCM source; retry or cancel")
        return
    var now = _now()
    if not request_sent and now - opened_at >= CONNECT_TIMEOUT_MS:
        _fail("Connection timeout; Stream retries, Stop cancels")
    elif not header_ok and now - requested_at >= HEADER_TIMEOUT_MS:
        _fail("WAV header timeout; Stream retries, Stop cancels")
    elif header_ok and now - last_read_at >= READ_IDLE_TIMEOUT_MS:
        _fail("PCM read timeout; Stream retries, Stop cancels")

func _u16(i):
    return int(pending[i]) + (int(pending[i + 1]) << 8)

func _signed16(i):
    var x = _u16(i)
    return x - 65536 if x >= 32768 else x

func _fill_audio():
    var count = min(MAX_DECODE_PER_TICK, int((pending.size() - offset) / (channels * 2)))
    if data_size >= 0:
        count = min(count, int(data_size / (channels * 2)) - decoded_frames)
    count = min(count, playback.get_frames_available())
    var energy = 0.0
    for _i in range(count):
        var left = float(_signed16(offset)) / 32768.0
        var right = float(_signed16(offset + 2)) / 32768.0 if channels == 2 else left
        playback.push_frame(Vector2(left, right))
        energy += (left * left + right * right) * 0.5
        offset += channels * 2
        decoded_frames += 1
    if count > 0:
        last_pcm_at = _now()
        last_rms = sqrt(energy / count)
        var queued = max(0, generator_capacity - playback.get_frames_available())
        queued_latency_ms = float(queued) * 1000.0 / rate
        playback_time_ms = max(playback_time_ms, float(decoded_frames - queued) * 1000.0 / rate)
        emit_signal("pcm_observed", epoch, last_rms, playback_time_ms, queued_latency_ms)

func _compact_pending():
    if offset == 0:
        return
    pending = pending.subarray(offset, pending.size() - 1) if offset < pending.size() else PoolByteArray()
    offset = 0

func _fail(msg):
    stop()
    _state("error")
    emit_signal("message", msg)
