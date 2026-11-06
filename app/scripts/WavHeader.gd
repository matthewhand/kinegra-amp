extends Reference
# Pure, bounded incremental PCM WAV header scanner. Does not decode compressed media.
const HEADER_LIMIT = 65536
const MAX_CHUNKS = 1024

func _u16(b, p):
    return int(b[p]) | (int(b[p + 1]) << 8)

func _u32(b, p):
    return _u16(b, p) | (_u16(b, p + 2) << 16)

func _tag(b, p):
    return char(b[p]) + char(b[p + 1]) + char(b[p + 2]) + char(b[p + 3])

func _incomplete(n):
    return {"status": "invalid"} if n >= HEADER_LIMIT else {"status": "need_more"}

func scan_header(data):
    var n = data.size()
    if n > HEADER_LIMIT:
        return {"status": "invalid"}
    if n < 12:
        return _incomplete(n)
    if _tag(data, 0) != "RIFF" or _tag(data, 8) != "WAVE":
        return {"status": "invalid"}
    var riff_size = _u32(data, 4)
    # 0xffffffff is a common sentinel for unbounded live WAV data.
    if riff_size != 4294967295 and riff_size < 36:
        return {"status": "invalid"}
    var riff_end = -1 if riff_size == 4294967295 else 8 + riff_size
    var pos = 12
    var got_fmt = false
    var rate = 0
    var channels = 0
    for _i in range(MAX_CHUNKS):
        if pos + 8 > HEADER_LIMIT:
            return {"status": "invalid"}
        if pos + 8 > n:
            return _incomplete(n)
        if riff_end != -1 and pos + 8 > riff_end:
            return {"status": "invalid"}
        var tag = _tag(data, pos)
        var size = _u32(data, pos + 4)
        var payload = pos + 8
        # Only bounds-check the size, NEVER wait for the data payload.
        if riff_end != -1 and payload + size > riff_end:
            return {"status": "invalid"}
        if tag == "data":
            if not got_fmt:
                return {"status": "invalid"}
            if size != 4294967295 and size % (channels * 2) != 0:
                return {"status": "invalid"}
            return {"status": "ok", "data_offset": payload, "sample_rate": rate, "channels": channels, "data_size": -1 if size == 4294967295 else size}
        if tag == "fmt ":
            if got_fmt or size < 16:
                return {"status": "invalid"}
            if payload + 16 > n:
                return _incomplete(n)
            rate = _u32(data, payload + 4)
            channels = _u16(data, payload + 2)
            if _u16(data, payload) != 1 or (channels != 1 and channels != 2):
                return {"status": "invalid"}
            if (rate != 22050 and rate != 44100 and rate != 48000):
                return {"status": "invalid"}
            var block_align = channels * 2
            if _u32(data, payload + 8) != rate * block_align or _u16(data, payload + 12) != block_align or _u16(data, payload + 14) != 16:
                return {"status": "invalid"}
            got_fmt = true
        # For fmt/metadata, skip the entire bounded chunk including RIFF padding.
        var next_pos = payload + size + (size & 1)
        if next_pos + 8 > HEADER_LIMIT:
            return {"status": "invalid"}
        if next_pos > n:
            return _incomplete(n)
        pos = next_pos
    return {"status": "invalid"}
