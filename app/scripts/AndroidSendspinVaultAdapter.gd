extends Reference
# Godot 3 Android plugins do not reliably return Java byte[] as PoolByteArray.
# Strings cross that boundary; native code continues to receive bounded bytes.
var plugin=null
var status="error"
const MAX_BYTES=4096
const MAX_TEXT=5464
func bind(value):
    # Android JNISingleton dispatch does not advertise Java methods through
    # Object.has_method(). Validate return values and package the required API.
    if value==null: return false
    plugin=value
    return true
func loadSendspinSnapshot():
    status="error"
    if plugin==null: return PoolByteArray()
    var text=plugin.loadSendspinSnapshotBase64()
    if typeof(text)!=TYPE_STRING or text.length()>MAX_TEXT: return PoolByteArray()
    var state=plugin.sendspinSnapshotStatus()
    if state=="missing" and text.empty():
        status="missing"
        return PoolByteArray()
    if state!="secure" or text.empty(): return PoolByteArray()
    var bytes=Marshalls.base64_to_raw(text)
    if bytes.empty() or bytes.size()>MAX_BYTES or Marshalls.raw_to_base64(bytes)!=text:
        return PoolByteArray()
    status="secure"
    return bytes
func replaceSendspinSnapshot(bytes):
    status="error"
    if plugin==null or typeof(bytes)!=TYPE_RAW_ARRAY or bytes.empty() or bytes.size()>MAX_BYTES:
        return false
    if plugin.replaceSendspinSnapshotBase64(Marshalls.raw_to_base64(bytes))!=true:
        return false
    status="secure"
    return true
func sendspinSnapshotStatus(): return status
