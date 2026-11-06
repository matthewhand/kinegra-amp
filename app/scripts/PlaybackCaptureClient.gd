extends Reference
# Optional bridge. Constructing this client never requests capture.
var bridge = null

func _init(override_bridge=null):
    if override_bridge != null:
        bridge = override_bridge
    elif Engine.has_singleton("ShieldAmpPlaybackCapture"):
        bridge = Engine.get_singleton("ShieldAmpPlaybackCapture")

func request_start():
    if bridge == null: return false
    bridge.startCapture()
    return true # Request dispatched, not proof of consent or capture.

func request_stop():
    if bridge == null: return false
    bridge.stopCapture()
    return true

func status():
    return str(bridge.captureStatus()) if bridge != null else "unavailable"

func level():
    if bridge == null: return 0.0
    var value = float(bridge.captureLevel())
    return clamp(value, 0.0, 1.0) if not is_nan(value) and not is_inf(value) else 0.0
