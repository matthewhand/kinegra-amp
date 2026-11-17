extends Node
# Bridge one Android-owned session into Amp's existing paired-output checks.
# No Godot PCM sink is created. Android reports actual presentation state.
signal state_changed(state, detail)
signal pairing_code_changed(code)

const STATES = ["idle", "connecting", "paired", "buffering", "playing", "paused", "error"]
const CONTROLS = ["can_play", "can_pause", "can_stop", "can_next", "can_previous"]
const COMMANDS = ["play", "pause", "stop", "next", "previous", "seek", "permit", "confirm"]

var runtime = null
var client = null
var sink = null
var active = false
var state = "idle"
var buffering = false
var current_pairing_code = ""
var endpoint = ""
var _platform = null
var _snapshot = {}
var _poll_wait = 0.0
var _start_at = 0
var _analysis_requested = false
var _analysis_wait = 0.0
var _analysis = {}

func _supports(platform):
    if not is_instance_valid(platform):
        return false
    # This is a packaged Android JNISingleton with a verified Java ABI.
    var supported = platform.backgroundPlaybackAvailable()
    return typeof(supported) == TYPE_BOOL and supported

func start(endpoint_value, trust_private, platform):
    if active or not _supports(platform):
        return false
    var gate = preload("res://scripts/SendspinExperienceFacade.gd").new()
    var permitted = gate._valid_endpoint(endpoint_value, trust_private)
    gate.free()
    if not permitted:
        return false
    var accepted = platform.connectBackgroundSendspin(endpoint_value)
    if typeof(accepted) != TYPE_BOOL or not accepted:
        return false
    _platform = platform
    endpoint = endpoint_value
    runtime = self
    client = self
    state = "connecting"
    _start_at = OS.get_ticks_msec()
    active = true
    _poll_wait = 0.0
    set_process(true)
    return true

func _process(delta):
    _poll_wait = max(0.0, _poll_wait - delta)
    if active and _poll_wait <= 0.0:
        _poll_wait = 0.15
        refresh()
    if active and _analysis_requested:
        _analysis_wait -= delta
        if _analysis_wait <= 0.0:
            _analysis_wait = 0.05
            _read_analysis()

func set_analysis_enabled(enabled):
    if enabled == _analysis_requested:
        return
    var accepted = _platform.setBackgroundPlaybackAnalysisEnabled(enabled) if is_instance_valid(_platform) else false
    _analysis_requested = enabled and typeof(accepted) == TYPE_BOOL and accepted
    _analysis_wait = 0.0
    _analysis.clear()

func _read_analysis():
    _analysis = {}
    if not active or not _analysis_requested or not _snapshot.get("presenting", false) or not is_instance_valid(_platform):
        return
    _analysis = preload("res://scripts/AndroidPlaybackAnalysis.gd").read(
        _platform.backgroundPlaybackAnalysis(), _snapshot.generation, OS.get_ticks_msec())

func analysis_sample(now_ms):
    if not _snapshot.get("presenting", false) or _analysis.get("generation", -1) != _snapshot.get("generation", -1):
        return {}
    var age = now_ms - _analysis.get("sample_at", -1000)
    return _analysis if age >= 0 and age <= 500 else {}

func refresh():
    if not active:
        return
    if not is_instance_valid(_platform):
        _set_error("Android playback service unavailable")
        return
    var raw = _platform.backgroundPlaybackSnapshot()
    if typeof(raw) != TYPE_STRING or raw.length() > 4096:
        _set_error("Invalid Android playback state")
        return
    var parsed = JSON.parse(raw)
    if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
        _set_error("Invalid Android playback state")
        return
    var r = parsed.result
    var native_state = r.get("state", "")
    var source = r.get("source", "")
    if not native_state in STATES or not source in ["ma", "none", "local"]:
        _set_error("Invalid Android playback state")
        return
    if source != "ma":
        if state == "connecting" and OS.get_ticks_msec() - _start_at < 2000 and source == "none" and native_state == "idle":
            return
        _platform = null
        _set_error("Android playback session changed")
        return
    var paired = r.get("paired", false) == true and typeof(r.get("paired")) == TYPE_BOOL
    var id = r.get("client_id", "")
    if paired and (typeof(id) != TYPE_STRING or not _valid_client_id(id)):
        _set_error("Invalid paired playback identity")
        return
    if native_state == "error":
        _set_error("Android playback failed")
        return
    if native_state == "idle" and not paired:
        _set_error("Android playback disconnected")
        return
    var playing = paired and native_state == "playing"
    var connection_state = "receiving" if playing else ("paired" if paired else "connecting")
    var old_id = _snapshot.get("client_id", "")
    _snapshot = {"paired": paired, "client_id": id if paired else "", "active": playing or (paired and native_state == "paused"),
        "presenting": playing, "generation": _nonnegative_int(r.get("generation"), -1),
        "queued_ms": _nonnegative_int(r.get("queued_ms"), -1), "sample_at": OS.get_ticks_msec()}
    for name in CONTROLS:
        _snapshot[name] = paired and typeof(r.get(name)) == TYPE_BOOL and r[name]
    _snapshot["stream_active"] = paired and typeof(r.get("stream_active")) == TYPE_BOOL and r.stream_active
    _snapshot["underruns"] = _nonnegative_int(r.get("underruns"), 0)
    _snapshot["rebuffers"] = _nonnegative_int(r.get("rebuffers"), 0)
    buffering = paired and native_state == "buffering"
    var pairing_code = r.get("pairing_code", "")
    _set_pairing_code(pairing_code if not paired and _valid_pairing_code(pairing_code) else "")
    if state != connection_state or old_id != _snapshot.client_id:
        state = connection_state
        emit_signal("state_changed", state, "Playing through Android" if playing else ("Ready to play" if paired else "Waiting for Music Assistant"))

func _valid_client_id(value):
    if value.empty() or value.length() > 128:
        return false
    for character in value:
        if not character in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_.:":
            return false
    return true

func _valid_pairing_code(value):
    if typeof(value) != TYPE_STRING or value.length() != 6:
        return false
    for character in value:
        if not character in "0123456789":
            return false
    return true

func _nonnegative_int(value, fallback):
    if not typeof(value) in [TYPE_INT, TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)):
        return fallback
    return int(value) if value >= 0 and value <= 2147483647 and value == floor(value) else fallback

func _set_pairing_code(code):
    if current_pairing_code == code:
        return
    current_pairing_code = code
    emit_signal("pairing_code_changed", code)

func _set_error(message):
    set_analysis_enabled(false)
    active = false
    set_process(false)
    _snapshot.clear()
    buffering = false
    _set_pairing_code("")
    state = "error"
    emit_signal("state_changed", state, message)

func status():
    return _snapshot.duplicate() if active else {}

func queued_audio_snapshot():
    if not active or not _snapshot.get("presenting", false) or _snapshot.get("generation", -1) < 0 or _snapshot.get("queued_ms", -1) < 0:
        return {}
    return {"generation": _snapshot.generation, "queued_ms": _snapshot.queued_ms, "measured_ms": _snapshot.sample_at}

func buffer_stats(now_ms):
    var age = now_ms - _snapshot.get("sample_at", -1000)
    if not active or not _snapshot.get("stream_active", false) or age < 0 or age > 750:
        return {}
    return {"active": true, "generation": _snapshot.generation, "queued_ms": _snapshot.queued_ms,
        "buffering": buffering, "underruns": _snapshot.underruns, "rebuffers": _snapshot.rebuffers}

func invalidate_buffer_measurement():
    _snapshot["queued_ms"] = -1

func command(name, position=-1):
    if not active or not is_instance_valid(_platform) or not name in COMMANDS:
        return false
    if name != "confirm" and not _snapshot.get("paired", false):
        return false
    var argument = _nonnegative_int(position, -1) if name == "seek" else 0
    if name == "seek" and argument < 0:
        return false
    var result = _platform.backgroundPlaybackCommand(name, argument)
    return typeof(result) == TYPE_BOOL and result

func confirm_pairing():
    return not current_pairing_code.empty() and command("confirm")

func reveal_pairing_token():
    return ""

func stop():
    set_analysis_enabled(false)
    if is_instance_valid(_platform):
        _platform.backgroundPlaybackCommand("stop", 0)
    _platform = null
    active = false
    set_process(false)
    runtime = null
    client = null
    _snapshot.clear()
    buffering = false
    _set_pairing_code("")
    state = "idle"
