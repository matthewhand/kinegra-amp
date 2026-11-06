extends Reference
# Portable tegra.analysis.v1. Spectral energy is NOT a musical beat detector.
const VERSION = "tegra.analysis.v1"
const MAX_AGE_MS = 500
const MAX_SAFE_INTEGER = 9007199254740991
const MAX_LATENCY_MS = 10000
var epoch = 0
var sequence = 0
var bands = []
var rms = 0.0
var sampled_at_ms = -1
var playback_ms = 0.0
var latency_ms = 0.0
var bpm = 0.0
var last_snapshot_ms = -1

func _now():
    return OS.get_ticks_msec()

func _safe_integer(value, minimum=0):
    return typeof(value) == TYPE_INT and value >= minimum and value <= MAX_SAFE_INTEGER

func _finite_number(value, minimum, maximum):
    return typeof(value) in [TYPE_INT, TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= minimum and float(value) <= maximum

func _init():
    _clear()

func _clear():
    last_snapshot_ms = -1
    bands = []
    for _i in range(16):
        bands.append(0.0)
    rms = 0.0
    sampled_at_ms = -1
    playback_ms = 0.0
    latency_ms = 0.0

func begin_epoch(value):
    if not _safe_integer(value, 1) or value <= epoch:
        return false
    epoch = value
    _clear()
    return true

func configure_metronome(value):
    bpm = 0.0
    if _finite_number(value, 30.0, 240.0):
        bpm = float(value)
        return true
    return _finite_number(value, 0.0, 0.0)

func publish(source_epoch, normalized_bands, source_rms, source_sampled_at_ms, time_ms, queued_ms):
    if not _safe_integer(source_epoch, 1) or source_epoch != epoch or typeof(normalized_bands) != TYPE_ARRAY or normalized_bands.size() != 16:
        return false
    var now = _now()
    if not _safe_integer(now) or not _safe_integer(source_sampled_at_ms) or source_sampled_at_ms > now:
        return false
    if not _finite_number(time_ms, 0.0, float(MAX_SAFE_INTEGER)) or not _finite_number(queued_ms, 0.0, MAX_LATENCY_MS):
        return false
    if source_sampled_at_ms < sampled_at_ms or time_ms < playback_ms or sequence >= MAX_SAFE_INTEGER:
        return false
    for value in normalized_bands:
        if not _finite_number(value, 0.0, 1.0):
            return false
    if not _finite_number(source_rms, 0.0, 1.0):
        return false
    bands = normalized_bands.duplicate()
    rms = float(source_rms)
    sampled_at_ms = int(source_sampled_at_ms)
    playback_ms = float(time_ms)
    latency_ms = float(queued_ms)
    sequence += 1
    return true

func snapshot(now_ms):
    var clock_valid = _safe_integer(now_ms) and now_ms >= sampled_at_ms and now_ms >= last_snapshot_ms
    var age = int(now_ms) - sampled_at_ms if clock_valid and sampled_at_ms >= 0 else MAX_AGE_MS + 1
    var fresh = clock_valid and sampled_at_ms >= 0 and age <= MAX_AGE_MS
    if clock_valid:
        last_snapshot_ms = now_ms
    var audible = fresh and rms > 0.00001
    var values = bands.duplicate()
    if not audible:
        for i in range(16):
            values[i] = 0.0
    var beat = {"kind": "none", "bpm": 0.0, "phase": 0.0, "confidence": 0.0}
    if bpm > 0 and fresh:
        beat = {"kind": "configured_metronome", "bpm": bpm, "phase": fposmod(playback_ms * bpm / 60000.0, 1.0), "confidence": 0.0}
    return {"version": VERSION, "epoch": epoch, "sequence": sequence, "bands": values,
        "rms": rms if audible else 0.0, "source_age_ms": age,
        "playback_ms": playback_ms, "estimated_output_latency_ms": latency_ms,
        "source": "live_pcm" if audible else ("silent_pcm" if fresh else "stale"), "beat": beat}
