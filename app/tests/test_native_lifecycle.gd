extends SceneTree
var failures = []
var checks = 0
class ClockTransport:
    extends "res://scripts/NativeHTTPTransport.gd"
    var clock = 0
    func _now():
        return clock
class FakePlayback:
    extends Reference
    var available = 0
    func get_frames_available():
        return available
class FakeBackend:
    extends Reference
    var count = 0
    func queued():
        return count
class FakeDecoder:
    extends Reference
    var active = true
    var emitted_audio = true
    var backend = FakeBackend.new()
    var playback = FakePlayback.new()
    var total_frames = 0
    var blocked = false
    var tail = PoolByteArray()
    var finishes = 0
    var paused = false
    func set_paused(value):
        paused = value
        return true
    func feed(packet):
        if blocked:
            return -2
        tail.append_array(packet)
        return packet.size()
    func end_stream():
        finishes += 1
    func stop():
        active = false
class FakeClient:
    extends Reference
    var status = HTTPClient.STATUS_BODY
    var polls = 0
    var length = -1
    var response_code = 200
    var chunks = []
    func close():
        pass
    func poll():
        polls += 1
    func get_status():
        return status
    func request(_method, _path, _headers):
        return OK
    func get_response_code():
        return response_code
    func get_response_body_length():
        return length
    func read_response_body_chunk():
        return chunks.pop_front() if not chunks.empty() else PoolByteArray()

func make_transport():
    var t = ClockTransport.new()
    t.client = FakeClient.new()
    t.decoder = FakeDecoder.new()
    t.active = true
    t.requested = true
    return t
func check(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func _init():
    var t = make_transport()
    var decoder = t.decoder
    var client = t.client
    t.pending = PoolByteArray([1,2,3,4])
    decoder.blocked = true
    client.status = HTTPClient.STATUS_CONNECTED
    t._process(.016)
    check(t.active and t.pending.size() == 4 and client.polls == 0 and decoder.finishes == 0, "EOF tail retained while backpressured")
    decoder.blocked = false
    t.clock = 100
    t._process(.016)
    check(t.active and t.pending.empty() and decoder.tail == PoolByteArray([1,2,3,4]) and decoder.finishes == 1, "EOF tail retried unchanged before finishing")
    t.clock = 10101
    t._process(.016)
    check(not t.active and not decoder.active, "stalled EOF drain bounded")
    t.free()
    t = make_transport()
    decoder = t.decoder
    decoder.blocked = true
    t.pending = PoolByteArray([1])
    t._process(.016)
    t.clock = 10001
    t._process(.016)
    check(not t.active, "permanent local decoder backpressure bounded")
    t.free()
    t = make_transport()
    t.eof = true
    for at in [0,9000,18000,27000]:
        t.clock = at
        t.decoder.total_frames += 1024
        t._process(.016)
    check(t.active, "long but progressing EOF tail allowed")
    t.free()
    t = make_transport()
    t.decoder.emitted_audio = false
    t.eof = true
    t._process(.016)
    t.clock = 10001
    t._process(.016)
    check(not t.active, "empty noncooperative decoder EOF bounded")
    t.free()
    t = make_transport()
    t.requested = false
    t.client.status = HTTPClient.STATUS_CONNECTING
    t.clock = 8000
    t._process(.016)
    check(not t.active, "absolute connect deadline")
    t.free()
    t = make_transport()
    t.decoder.emitted_audio = false
    t.client.chunks = [PoolByteArray([1])]
    t.clock = 15000
    t._process(.016)
    check(not t.active, "trickle cannot bypass first audio deadline")
    t.free()
    t = make_transport()
    t.clock = 10000
    t._process(.016)
    check(not t.active, "read idle deadline")
    t.free()
    t = make_transport()
    t.client.length = 8
    t.client.chunks = [PoolByteArray([1,2,3,4])]
    t._process(.016)
    t.client.status = HTTPClient.STATUS_CONNECTION_ERROR
    t.clock = 100
    t._process(.016)
    check(not t.active, "finite HTTP truncation rejected")
    t.free()
    for invalid_queue in [NAN, -1, 131073, "0", false]:
        t = make_transport()
        t.decoder.backend.count = invalid_queue
        t._process(.016)
        check(not t.active, "invalid native queue rejected before network read")
        t.free()
    t = make_transport()
    var pause_client = t.client
    check(t.set_paused(true), "local native pause accepted")
    t.clock = 100000
    t._process(.016)
    check(t.active and pause_client.polls == 0, "paused native transport neither reads nor expires")
    check(t.set_paused(false), "local native resume accepted")
    t.clock = 100001
    t._process(.016)
    check(t.active and t.last_read == 100000, "native resume shifts timeout clock without restarting source")
    t.free()
    for status_code in [401, 404]:
        t = make_transport()
        decoder = t.decoder
        t.client.status = HTTPClient.STATUS_CONNECTED
        t.client.response_code = status_code
        t.client.length = 0
        t._process(.016)
        check(not t.active and t.state == "error" and decoder.finishes == 0, "empty error response rejected immediately")
        t.free()
    print("NATIVE_LIFECYCLE_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
