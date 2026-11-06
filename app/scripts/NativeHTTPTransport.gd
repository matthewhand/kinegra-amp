extends Node
# Bounded compressed transport using the same installation policy as PCM WAV.
signal message(text)
var decoder = null
var client = null
var policy = preload("res://scripts/ConnectionPolicy.gd").new()
var origin = ""
var trust = false
var path = ""
var active = false
var paused = false
var pause_started_at = 0
var state = "stopped"
signal state_changed(value)
var requested = false
var opened_at = 0
var requested_at = 0
var last_read = 0
var pending = PoolByteArray()
var eof = false
var expected_body_bytes = -1
var received_body_bytes = 0
var response_checked = false
var ma_preview_token = ""
var ma_preview_mode = false
const PREVIEW_MAX_BYTES = 12582912
const CHUNK = 8192
const CONNECT_TIMEOUT_MS = 8000
const FIRST_AUDIO_TIMEOUT_MS = 15000
const READ_IDLE_TIMEOUT_MS = 10000
const DRAIN_IDLE_TIMEOUT_MS = 10000
var last_progress_at = 0
var last_progress_frames = -1
var last_progress_input = -1
var last_progress_available = -1

func _state(value):
    if state != value:
        state = value
        emit_signal("state_changed", value)

func set_paused(value):
    if not active or not decoder.set_paused(value):
        return false
    if paused == bool(value):
        return true
    paused = bool(value)
    if paused:
        pause_started_at = _now()
        _state("paused")
    else:
        var elapsed_pause = _now() - pause_started_at
        opened_at += elapsed_pause
        requested_at += elapsed_pause
        last_read += elapsed_pause
        last_progress_at += elapsed_pause
        _state("playing")
    return true

func _now():
    return OS.get_ticks_msec()

func configure(player, address, trust_private):
    stop()
    decoder = player
    origin = str(address).strip_edges().trim_suffix("/")
    trust = trust_private

func start(url, codec):
    return _begin(url, codec, "", false)

func _valid_preview_path(value):
    var matcher = RegEx.new()
    if matcher.compile("^/preview\\?path=[A-Za-z0-9%._~-]+&provider=[A-Za-z0-9%._~-]+$") != OK:
        return false
    if matcher.search(value) == null:
        return false
    # A raw percent-encoded control value is never emitted by our safe route builder.
    var lowered = value.to_lower()
    for blocked in ["%0d", "%0a", "%00", "%7f"]:
        if blocked in lowered:
            return false
    return true

func start_authorized_preview(url, bearer):
    # Explicit owner-selected MA previews ONLY. This is not a full-track API.
    if typeof(bearer) != TYPE_STRING or bearer.length() < 10 or bearer.length() > 8192:
        return false
    for i in range(bearer.length()):
        if bearer.ord_at(i) < 33 or bearer.ord_at(i) > 126:
            return false
    return _begin(url, 1, bearer, true)

func _begin(url, codec, bearer, preview):
    stop()
    var address = policy.origin(origin, ["http", "https"], trust)
    if address.empty() or not str(url).begins_with(address["prefix"] + "/") or str(url).length() > 2048:
        _fail("Native source origin is not configured")
        return false
    for bad in ["@", "#", "\\", "token=", "password=", "authorization="]:
        if bad in str(url).to_lower():
            _fail("Native source URL rejected")
            return false
    for i in range(str(url).length()):
        if str(url).ord_at(i) < 32 or str(url).ord_at(i) == 127:
            _fail("Native source URL rejected")
            return false
    path = str(url).substr(address["prefix"].length())
    if preview and (codec != 1 or not _valid_preview_path(path)):
        _fail("MA preview path invalid")
        return false
    if path.begins_with("//") or decoder == null or not decoder.begin(codec):
        _fail("Native decoder unavailable or unsupported codec")
        return false
    client = HTTPClient.new()
    client.read_chunk_size = CHUNK
    if client.connect_to_host(address["host"], address["port"], address["secure"]) != OK:
        _fail("Native HTTP connection failed")
        return false
    ma_preview_token = bearer
    ma_preview_mode = preview
    opened_at = _now()
    requested_at = opened_at
    last_read = opened_at
    last_progress_at = opened_at
    active = true
    _state("connecting")
    emit_signal("message", "Opening native MP3 / Ogg Vorbis; Stop cancels")
    return true

func stop():
    ma_preview_token = ""
    ma_preview_mode = false
    path = ""
    paused = false
    active = false
    _state("stopped")
    requested = false
    eof = false
    expected_body_bytes = -1
    received_body_bytes = 0
    response_checked = false
    last_progress_frames = -1
    last_progress_input = -1
    last_progress_available = -1
    pending = PoolByteArray()
    if client != null:
        client.close()
        client = null
    if decoder != null:
        decoder.stop()

func _response_ok():
    if not response_checked:
        if client.get_response_code() != 200:
            _fail("Native source rejected request")
            return false
        if ma_preview_mode:
            var audio_mime = ""
            for header in client.get_response_headers():
                if str(header).to_lower().begins_with("content-type:"):
                    audio_mime = str(header).split(":", false, 1)[1].strip_edges().split(";")[0].strip_edges().to_lower()
            if not audio_mime in ["audio/mpeg", "audio/mp3", "audio/x-mpeg"]:
                _fail("MA preview was not confirmed MP3")
                return false
        expected_body_bytes = client.get_response_body_length()
        if ma_preview_mode and expected_body_bytes > PREVIEW_MAX_BYTES:
            _fail("MA preview exceeded bounded clip size")
            return false
        if typeof(expected_body_bytes) != TYPE_INT or expected_body_bytes < -1:
            _fail("Native source returned an invalid response length")
            return false
        response_checked = true
    return true

func _queued():
    var count = decoder.backend.queued()
    if typeof(count) != TYPE_INT or count < 0 or count > 131072:
        _fail("Native decoder reported invalid queue")
        return -1
    return count

func _flush_pending():
    if pending.empty():
        return true
    var accepted = decoder.feed(pending)
    if typeof(accepted) == TYPE_INT and accepted == pending.size():
        pending = PoolByteArray()
        return true
    if typeof(accepted) == TYPE_INT and accepted == -2:
        return false
    _fail("Native compressed stream rejected")
    return false

func _deadlines(now, backpressured):
    if not requested and now - opened_at >= CONNECT_TIMEOUT_MS:
        _fail("Native connect timeout")
    elif not decoder.emitted_audio and now - requested_at >= FIRST_AUDIO_TIMEOUT_MS:
        _fail("Native audio header timeout")
    elif not eof and decoder.emitted_audio and not backpressured and now - last_read >= READ_IDLE_TIMEOUT_MS:
        _fail("Native read timeout")
    return active

func _watch_drain(now, queued):
    var available = decoder.playback.get_frames_available() if decoder.playback != null else -1
    if decoder.total_frames != last_progress_frames or queued != last_progress_input or available != last_progress_available:
        last_progress_at = now
        last_progress_frames = decoder.total_frames
        last_progress_input = queued
        last_progress_available = available
    elif now - last_progress_at >= DRAIN_IDLE_TIMEOUT_MS:
        _fail("Native decoder drain stalled")

func _process(_delta):
    if not active or client == null or decoder == null or paused:
        return
    if not decoder.active:
        var finished = decoder.last_completed_frames > 0
        stop()
        _state("ended" if finished else "error")
        return
    if decoder.emitted_audio and state in ["connecting", "header"]:
        _state("playing")
    var now = _now()
    var queued = _queued()
    if queued < 0:
        return
    var backpressured = not pending.empty() or queued > 131072 - CHUNK
    if not _deadlines(now, backpressured):
        return
    if backpressured:
        _watch_drain(now, queued)
        if not active:
            return
    # Retain the final packet until accepted, including when HTTP is already EOF.
    if not pending.empty():
        if not _flush_pending():
            if active:
                last_read = now
            return
    if eof:
        if not _response_ok():
            return
        if expected_body_bytes >= 0 and received_body_bytes != expected_body_bytes:
            _fail("Native source ended before its response completed")
            return
        _state("draining")
        decoder.end_stream()
        _watch_drain(now, queued)
        return
    client.poll()
    var status = client.get_status()
    if status == HTTPClient.STATUS_CONNECTED:
        if not requested:
            var headers = ["Accept: audio/mpeg"] if ma_preview_mode else ["Accept: audio/mpeg, audio/ogg"]
            if ma_preview_mode:
                headers.append("Authorization: Bearer " + ma_preview_token)
            if client.request(HTTPClient.METHOD_GET, path, headers) != OK:
                _fail("Native HTTP request failed")
                return
            requested = true
            _state("header")
            requested_at = now
            last_read = now
        else:
            eof = true
    elif status == HTTPClient.STATUS_BODY:
        if not _response_ok():
            return
        if queued <= 131072 - CHUNK:
            pending = client.read_response_body_chunk()
            if pending.size() > CHUNK:
                _fail("Native transport chunk exceeded limit")
                return
            if not pending.empty():
                received_body_bytes += pending.size()
                if ma_preview_mode and received_body_bytes > PREVIEW_MAX_BYTES:
                    _fail("MA preview exceeded bounded clip size")
                    return
                if expected_body_bytes >= 0 and received_body_bytes > expected_body_bytes:
                    _fail("Native source exceeded declared response size")
                    return
                last_read = now
                if not _flush_pending():
                    return
        else:
            last_read = now
    elif status == HTTPClient.STATUS_DISCONNECTED or (status == HTTPClient.STATUS_CONNECTION_ERROR and decoder.emitted_audio):
        eof = true
    elif status in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_SSL_HANDSHAKE_ERROR]:
        _fail("Native source connection failed")
        return
    if eof:
        if not _response_ok():
            return
        if expected_body_bytes >= 0 and received_body_bytes != expected_body_bytes:
            _fail("Native source ended before its response completed")
            return
        _state("draining")
        decoder.end_stream()
        _watch_drain(now, queued)

func _notification(what):
    if what == MainLoop.NOTIFICATION_APP_PAUSED:
        stop()

func _exit_tree():
    stop()

func _fail(reason):
    stop()
    _state("error")
    emit_signal("message", reason)
