extends SceneTree

var parser = preload("res://scripts/WavHeader.gd").new()
var checks = 0

func _u16(n):
    return PoolByteArray([n & 255, (n >> 8) & 255])

func _u32(n):
    return PoolByteArray([n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255])

func _chunk(name, body):
    var b = name.to_utf8()
    b.append_array(_u32(body.size()))
    b.append_array(body)
    if body.size() % 2 == 1:
        b.append(0)
    return b

func _format(rate=22050, channels=2):
    var b = _u16(1)
    b.append_array(_u16(channels))
    b.append_array(_u32(rate))
    b.append_array(_u32(rate * channels * 2))
    b.append_array(_u16(channels * 2))
    b.append_array(_u16(16))
    return _chunk("fmt ", b)

func _wave(chunks, live=false):
    var b = "RIFF".to_utf8()
    b.append_array(_u32(4294967295 if live else chunks.size() + 4))
    b.append_array("WAVE".to_utf8())
    b.append_array(chunks)
    return b

func _expect(label, actual, wanted):
    checks += 1
    if actual != wanted:
        printerr("FAIL ", label, ": ", actual, " expected ", wanted)
        quit(1)
        return false
    return true

func _init():
    call_deferred("_run")

func _run():
    var chunks = _format()
    chunks.append_array(_chunk("data", PoolByteArray()))
    var plain = _wave(chunks)
    if not _expect("minimal", parser.scan_header(plain).get("data_offset"), 44): return
    if not _expect("minimal status", parser.scan_header(plain).get("status"), "ok"): return
    for supported in [22050, 44100, 48000]:
        var valid_chunks = _format(supported)
        valid_chunks.append_array(_chunk("data", PoolByteArray([1, 2, 3, 4])))
        var parsed = parser.scan_header(_wave(valid_chunks))
        if not _expect("rate %d" % supported, parsed.get("sample_rate"), supported): return
        if not _expect("stereo %d" % supported, parsed.get("channels"), 2): return
    var mono_chunks = _format(44100, 1)
    mono_chunks.append_array(_chunk("data", PoolByteArray([1, 2])))
    var mono = parser.scan_header(_wave(mono_chunks))
    if not _expect("mono 44.1 rate", mono.get("sample_rate"), 44100): return
    if not _expect("mono channel", mono.get("channels"), 1): return
    var extra = _chunk("JUNK", PoolByteArray([1, 2, 3]))
    extra.append_array(_format())
    extra.append_array(_chunk("LIST", PoolByteArray([6, 7])))
    extra.append_array(_chunk("data", PoolByteArray([1, 2, 3, 4])))
    if not _expect("metadata + padding", parser.scan_header(_wave(extra)).get("data_offset"), 66): return
    if not _expect("partial", parser.scan_header(plain.subarray(0, 27)).get("status"), "need_more"): return
    var bad = _format(96000)
    bad.append_array(_chunk("data", PoolByteArray()))
    if not _expect("reject 96000", parser.scan_header(_wave(bad)).get("status"), "invalid"): return
    var stream = _format()
    stream.append_array("data".to_utf8())
    stream.append_array(_u32(4294967295))
    if not _expect("unknown live length", parser.scan_header(_wave(stream, true)).get("status"), "ok"): return
    var wrong = _wave(chunks)
    wrong[0] = 88
    if not _expect("bad magic", parser.scan_header(wrong).get("status"), "invalid"): return
    if not _expect("metadata header incomplete", parser.scan_header(_wave(extra).subarray(0, 60)).get("status"), "need_more"): return
    print("PASS: ", checks, " real Godot WAV header test assertions")
    quit(0)
