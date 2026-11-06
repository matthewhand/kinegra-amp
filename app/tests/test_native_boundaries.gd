extends SceneTree
var failures = []
var checks = 0
class BoundaryCodec:
    extends "res://tests/FakeNativeCodec.gd"
    var acceptance = null
    var error_value = 0
    var queue_value = 0
    var forced_bytes = -1
    # In-memory fictional decoder state; no PCM audio fixtures or generated tones.
    func open(codec):
        opened = codec == 1 or codec == 2
        eof = false
        pushed = 0
        cursor = 0
        return opened
    func push(bytes):
        return .push(bytes) if acceptance == null else acceptance
    func lastError():
        return error_value
    func queued():
        return queue_value
    func pull(frames):
        if forced_bytes >= 0:
            var bytes = PoolByteArray()
            bytes.resize(forced_bytes)
            return bytes
        return .pull(frames)
func check(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func make_player():
    var p = load("res://scripts/NativeDecoderPlayer.gd").new()
    p.set_test_backend(BoundaryCodec.new())
    get_root().add_child(p)
    check(p.begin(1), "fixture decoder starts")
    return p
func _init():
    call_deferred("run")
func run():
    var index = AudioServer.get_bus_count()
    AudioServer.add_bus(index)
    AudioServer.set_bus_name(index, "Milkdrop")
    for bad in [NAN, INF, -INF, 4.0, "4", false]:
        var p = make_player()
        p.backend.acceptance = bad
        check(p.feed(PoolByteArray([1,2,3,4])) == -1 and not p.active and not p.backend.opened, "malformed acceptance count closes owned session")
        p.queue_free()
    for bad_rate in [NAN, INF, -INF, "44100", 44100.0, 0, 192001]:
        var p = make_player()
        check(not p._initialize_audio(bad_rate) and not p.active, "invalid native sample rate rejected before generator creation")
        p.queue_free()
    for bad_error in [NAN, "0", false, 1]:
        var p = make_player()
        p.backend.error_value = bad_error
        p._process(.016)
        check(not p.active and p.playback == null, "malformed native error status cannot leave active session")
        p.queue_free()
    for byte_count in [3,4100]:
        var p = make_player()
        p.backend.forced_bytes = byte_count
        p._process(.016)
        check(not p.active and p.pending_pcm.empty(), "partial or oversized native PCM rejected")
        p.queue_free()
    for bad_queue in [NAN,"0",false,-1,131073]:
        var p = make_player()
        p.backend.forced_bytes = 0
        p.backend.queue_value = bad_queue
        p.end_stream()
        p._process(.016)
        check(not p.active, "invalid EOF queue cannot report clean completion")
        p.queue_free()
    print("NATIVE_BOUNDARY_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
