extends Reference
# Pure offline reusable 16-band envelope. No microphone, stream or generated audio.
const COUNT = 16
const NOISE_FLOOR = 0.012
const ATTACK_PER_SECOND = 22.0
const RELEASE_PER_SECOND = 7.0
var bands = []
var sensitivity = 1.0

func set_sensitivity(value):
    if not typeof(value) in [TYPE_INT, TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)):
        return false
    if float(value) < 0.5 or float(value) > 2.0:
        return false
    sensitivity = float(value)
    return true


func _init():
    reset()

func reset():
    bands.clear()
    for _i in range(COUNT):
        bands.append(0.0)

func apply(spectrum, delta):
    if typeof(spectrum) != TYPE_ARRAY or spectrum.size() != COUNT or not typeof(delta) in [TYPE_INT, TYPE_REAL]:
        return bands.duplicate()
    if is_nan(float(delta)) or is_inf(float(delta)) or delta < 0.0 or delta > 0.25:
        return bands.duplicate()
    # Validate every band before changing state: bad data cannot partially update.
    for raw in spectrum:
        if not typeof(raw) in [TYPE_INT, TYPE_REAL] or is_nan(float(raw)) or is_inf(float(raw)) or raw < 0.0 or raw > 1.0:
            return bands.duplicate()
    for i in range(COUNT):
        var value = clamp(float(spectrum[i]) * sensitivity, 0.0, 1.0)
        if value < NOISE_FLOOR:
            value = 0.0
        var speed = ATTACK_PER_SECOND if value > bands[i] else RELEASE_PER_SECOND
        var coefficient = clamp(1.0 - exp(-speed * delta), 0.0, 1.0)
        bands[i] = clamp(lerp(bands[i], value, coefficient), 0.0, 1.0)
    return bands.duplicate()
