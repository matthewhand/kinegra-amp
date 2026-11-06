extends Reference
# Quality follows measured frame/audio pressure. CPU is app-only, not idle GPU.
const MODES = ["auto", "full", "light", "audio_first"]
const LABELS = ["AUDIO FIRST", "LIGHT", "FULL"]
var mode = "auto"
var level = 2
var reason = "Normal frame budget"
var previous_ms = -1
var changed_ms = 0
var healthy_since = -1
var pressure_samples = 0
var previous_generation = -1
var previous_underruns = -1
var previous_rebuffers = -1
var generation_since = -1
var thermal_latched = false
var thermal_cool_since = -1

func set_mode(value, now_ms=0):
    if not value in MODES: return false
    mode = value
    level = {"auto":2, "full":2, "light":1, "audio_first":0}[value]
    if thermal_latched: level=0
    reason = "Automatic" if value == "auto" else "Selected in Settings"
    changed_ms = now_ms
    healthy_since = -1
    pressure_samples = 0
    return true

func _finite(value):
    return typeof(value) in [TYPE_REAL, TYPE_INT] and not is_nan(float(value)) and not is_inf(float(value))

func _select(value, why, now_ms):
    if level != value:
        level = value
        changed_ms = now_ms
    reason = why
    healthy_since = -1
    pressure_samples = 0

func observe(now_ms, p95_ms, late_ratio, audio={}, cpu_percent=-1.0, thermal=-1, refresh_hz=60.0):
    if typeof(now_ms) != TYPE_INT or now_ms < 0: return snapshot()
    if previous_ms >= 0 and now_ms <= previous_ms: return snapshot()
    if not _finite(p95_ms) or p95_ms < 0 or not _finite(late_ratio): return snapshot()
    var gap = previous_ms >= 0 and now_ms - previous_ms > 5000
    previous_ms = now_ms
    if gap:
        thermal_cool_since = -1
        healthy_since = -1
        pressure_samples = 0
    var audio_pressure = false
    var audio_healthy = true
    if typeof(audio) == TYPE_DICTIONARY and audio.get("active", false):
        var generation = int(audio.get("generation", -1))
        var skips = int(audio.get("underruns", 0))
        var rebuffers = int(audio.get("rebuffers", 0))
        if generation != previous_generation or previous_underruns < 0:
            previous_generation = generation
            generation_since = now_ms
        elif now_ms - generation_since >= 3000:
            audio_pressure = skips > previous_underruns or rebuffers > previous_rebuffers
            audio_pressure = audio_pressure or (not audio.get("buffering", true) and int(audio.get("queued_ms", 0)) < 96)
        previous_underruns = skips
        previous_rebuffers = rebuffers
        audio_healthy = not audio.get("buffering", true) and int(audio.get("queued_ms", 0)) >= 200
    else:
        previous_generation = -1
        previous_underruns = -1
        previous_rebuffers = -1
        generation_since = -1
    # Thermal status is an Android severity, not a temperature or CPU percent.
    if thermal >= 3:
        thermal_latched=true
        thermal_cool_since=-1
        _select(0, "Device is hot", now_ms)
        return snapshot()
    if thermal_latched:
        if thermal in [0,1]:
            if thermal_cool_since<0: thermal_cool_since=now_ms
            if now_ms-thermal_cool_since>=30000: thermal_latched=false
        else: thermal_cool_since=-1
        if thermal_latched:
            _select(0,"Cooling down",now_ms)
            return snapshot()
    if mode != "auto":
        _select({"full":2, "light":1, "audio_first":0}[mode], "Selected in Settings", now_ms)
        return snapshot()
    if audio_pressure:
        _select(0, "Audio buffer recovery", now_ms)
        return snapshot()
    if thermal == 2:
        _select(min(level, 1), "Device is warm", now_ms)
        return snapshot()
    if not _finite(refresh_hz) or refresh_hz < 24 or refresh_hz > 240: refresh_hz = 60.0
    var budget_ms = 1000.0 / float(refresh_hz)
    var pressure = p95_ms > budget_ms * 1.5 or (refresh_hz >= 45 and late_ratio > 0.10)
    pressure = pressure or (_finite(cpu_percent) and cpu_percent > 75.0)
    if pressure:
        pressure_samples += 1
        healthy_since = -1
        if pressure_samples >= 2 and now_ms - changed_ms >= 2000:
            _select(max(0, level - 1), "Frame budget is tight", now_ms)
    else:
        pressure_samples = 0
        var healthy = p95_ms <= budget_ms * 1.15 and (refresh_hz < 45 or late_ratio <= 0.03) and audio_healthy
        healthy = healthy and (not _finite(cpu_percent) or cpu_percent < 0 or cpu_percent < 60.0)
        if healthy:
            if healthy_since < 0: healthy_since = now_ms
            if level < 2 and now_ms - healthy_since >= 30000 and now_ms - changed_ms >= 30000:
                _select(level + 1, "Headroom recovered", now_ms)
        else: healthy_since = -1
    return snapshot()

func snapshot():
    return {"mode":mode, "level":level, "label":LABELS[level], "reason":reason}
