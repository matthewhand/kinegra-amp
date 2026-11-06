extends Reference
# Deterministic, bounded offline frame-time monitor; no networking or telemetry.
const CAPACITY = 120
const SLOW_FRAME_MS = 33.334
var samples = []
var total = 0.0
var late_frames = 0

func reset():
    samples.clear()
    total = 0.0
    late_frames = 0

func observe(delta):
    if not typeof(delta) in [TYPE_REAL, TYPE_INT] or is_nan(float(delta)) or is_inf(float(delta)):
        return false
    if delta <= 0.0 or delta > 1.0:
        return false
    var duration = float(delta) * 1000.0
    if samples.size() == CAPACITY:
        var removed = samples.pop_front()
        total -= removed
        if removed > SLOW_FRAME_MS:
            late_frames -= 1
    samples.append(duration)
    total += duration
    if duration > SLOW_FRAME_MS:
        late_frames += 1
    return true

func snapshot():
    if samples.empty():
        return {"count":0,"mean_ms":0.0,"p95_ms":0.0,"late_ratio":0.0,"fps_estimate":0.0}
    var ordered = samples.duplicate()
    ordered.sort()
    var p95_index = int(ceil(float(ordered.size()) * 0.95)) - 1
    var mean = total / float(samples.size())
    return {
        "count":samples.size(),
        "mean_ms":mean,
        "p95_ms":ordered[p95_index],
        "late_ratio":float(late_frames) / float(samples.size()),
        "fps_estimate":1000.0 / mean
    }
