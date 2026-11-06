extends SceneTree
var failures = []
var checks = 0

class ClockReader:
    extends "res://scripts/StreamPlayer.gd"
    var clock = 0
    func _now():
        return clock

class FakePlayback:
    extends Reference
    var available = 20000
    var pushed = 0
    func get_frames_available():
        return available
    func push_frame(_frame):
        available -= 1
        pushed += 1

class FakeAudio:
    extends Reference
    var stream = null
    var pb = FakePlayback.new()
    func play():
        pb = FakePlayback.new()
    func stop():
        pass
    func get_stream_playback():
        return pb

class FakeClient:
    extends Reference
    var chunks = []
    var reads = 0
    var status = HTTPClient.STATUS_BODY
    var end = true
    func poll():
        if chunks.empty() and end and reads > 0:
            status = HTTPClient.STATUS_CONNECTED
    func close():
        pass
    func get_status():
        return status
    func get_response_code():
        return 200
    func read_response_body_chunk():
        reads += 1
        return chunks.pop_front() if not chunks.empty() else PoolByteArray()

func check(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)

func u16(n):
    return PoolByteArray([n & 255, (n >> 8) & 255])

func u32(n):
    return PoolByteArray([n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255])

func wav(rate=22050, channels=2, metadata=false, live=false, count=128):
    var b = "RIFF".to_utf8()
    b.append_array(u32(4294967295 if live else 36 + count * channels * 2 + (12 if metadata else 0)))
    b.append_array("WAVE".to_utf8())
    if metadata:
        b.append_array("JUNK".to_utf8())
        b.append_array(u32(3))
        b.append_array(PoolByteArray([1, 2, 3, 0]))
    b.append_array("fmt ".to_utf8())
    b.append_array(u32(16))
    b.append_array(u16(1))
    b.append_array(u16(channels))
    b.append_array(u32(rate))
    b.append_array(u32(rate * channels * 2))
    b.append_array(u16(channels * 2))
    b.append_array(u16(16))
    b.append_array("data".to_utf8())
    b.append_array(u32(4294967295 if live else count * channels * 2))
    for _i in range(count * channels * 2):
        b.append(0)
    return b

func reader(chunks, end=true):
    var r = ClockReader.new()
    r.stream = FakeAudio.new()
    r.client = FakeClient.new()
    r.client.chunks = chunks.duplicate()
    r.client.end = end
    r._begin_session()
    r.request_sent = true
    return r

func tick(r, n=1):
    for _i in range(n):
        r._process(0.016)
        check(r.pending.size() <= r.max_pending_bytes, "physical buffer bounded")

func _init():
    call_deferred("run")

func run():
    for metadata in [false, true]:
        var b = wav(22050, 2, metadata)
        for split in range(1, 56 if metadata else 44):
            var r = reader([b.subarray(0, split-1), PoolByteArray(), b.subarray(split, b.size()-1)], false)
            tick(r, 3)
            check(r.header_ok and r.decoded_frames == 128 and r.client.reads == 3, "split %d metadata %s" % [split, metadata])
            r.free()
    for rate in [22050, 44100, 48000]:
        for channels in [1, 2]:
            var payload = wav(rate, channels, true, true, 20000)
            var r = reader([payload.subarray(0, min(60000, payload.size()) - 1)], false)
            tick(r)
            check(r.decoded_frames == 4096, "decode tick cap")
            check(r.max_pending_bytes == int(rate * channels * 2 * 4.65), "rate queue bound")
            var old = r.stream.stream
            r.stop()
            check(r.pending.empty() and r.playback == null and r.stream.stream != old, "stop discards all audio")
            r.free()
    var r = reader([wav(96000)])
    tick(r)
    check(r.state == "error", "unsupported rate")
    r.free()
    r = reader([PoolByteArray([1, 2, 3])])
    tick(r, 2)
    check(r.state == "error", "truncated header EOF")
    r.free()
    var b = wav()
    r = reader([b.subarray(0, b.size()-3)])
    tick(r, 2)
    check(r.state == "error", "declared PCM truncation")
    r.free()
    r = reader([wav(22050, 2, false, true).subarray(0, 44)])
    tick(r, 2)
    check(r.state == "error", "partial frame EOF")
    r.free()
    r = reader([wav()])
    tick(r)
    r.stream.pb.available = 20000
    tick(r)
    check(r.state == "ended", "clean finite EOF drains")
    r.free()
    r = reader([], false)
    r.request_sent = false
    r.client.status = HTTPClient.STATUS_CONNECTING
    r.clock = 8001
    tick(r)
    check(r.state == "error", "connect deadline")
    r.free()
    r = reader([PoolByteArray()], false)
    r.clock = 15001
    tick(r)
    check(r.state == "error", "silent header deadline")
    r.free()
    r = reader([wav(22050, 2, false, true)], false)
    tick(r)
    r.clock = 10001
    tick(r)
    check(r.state == "error", "idle deadline")
    r.free()
    b = PoolByteArray()
    b.resize(65537)
    r = reader([b])
    tick(r)
    check(r.state == "error", "oversized transport chunk")
    r.free()
    r = reader([wav(22050, 2, false, true)], false)
    tick(r)
    r._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(r.pending.empty() and r.playback == null and not r.active, "suspend clears stream")
    r.free()
    for rate in [22050, 44100, 48000]:
        for channels in [1, 2]:
            r = reader([wav(rate, channels, false, true)], false)
            tick(r)
            r.stream.pb.available = 0
            var block = PoolByteArray()
            block.resize(65536)
            for _i in range(30):
                r.client.chunks.append(block)
            tick(r, 30)
            var reads = r.client.reads
            r.clock = 100000
            tick(r, 10)
            check(r.client != null and r.client.reads == reads and r.active, "backpressure pauses network without idle timeout")
            r.stop()
            check(r.pending.empty() and r.offset == 0, "full queue stop reset")
            r.free()
    # Header at the limit with odd padded metadata must make incremental progress.
    b = wav(22050, 2, true, true)
    b[16] = 239
    b[17] = 255
    b[18] = 0
    b[19] = 0
    r = reader([b])
    tick(r)
    check(r.state == "error", "oversized metadata header rejected")
    r.free()
    b = wav(22050, 2, false, true)
    var large = b.subarray(0, 11)
    large.append_array("JUNK".to_utf8())
    large.append_array(u32(65484))
    var padding = PoolByteArray()
    padding.resize(65484)
    large.append_array(padding)
    large.append_array(b.subarray(12, b.size()-1))
    r = reader([large.subarray(0, 59999), large.subarray(60000, large.size()-1)], false)
    tick(r, 2)
    check(r.header_ok and r.decoded_frames == 128, "header exactly 64KiB with PCM lookahead")
    r.free()
    var with_list = b.subarray(0, 35)
    with_list.append_array("LIST".to_utf8())
    with_list.append_array(u32(3))
    with_list.append_array(PoolByteArray([1, 2, 3, 0]))
    with_list.append_array(b.subarray(36, b.size()-1))
    var fragments = []
    for i in range(with_list.size()):
        fragments.append(with_list.subarray(i, i))
    r = reader(fragments, false)
    tick(r, with_list.size())
    check(r.header_ok and r.decoded_frames == 128, "one-byte chunks across fmt LIST and padding")
    r.free()
    b[20] = 3
    r = reader([b])
    tick(r)
    check(r.state == "error", "compressed WAV rejected through reader")
    r.free()
    print("READER_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
