extends Reference
# Offline only. Replays PCM16LE bytes output by actual host native decoder.
# Does not decode MP3/OGG and must never ship as runtime fallback.
var pcm = PoolByteArray()
var cursor = 0
var opened = false
var eof = false
var pushed = 0
var forced_backpressure = false
var forced_bad_pcm = false
var forced_rate = 0
var close_count = 0

func open(codec):
    if codec != 1 and codec != 2:
        return false
    pcm = PoolByteArray()
    var f = File.new()
    if f.open("res://tests/fixtures/native_decoded_pcm16le.raw", File.READ) != OK:
        return false
    pcm = f.get_buffer(f.get_len())
    f.close()
    cursor = 0
    pushed = 0
    opened = true
    eof = false
    return true

func push(bytes):
    if not opened or eof or bytes.size() == 0 or bytes.size() > 8192:
        return -1
    if forced_backpressure:
        return -2
    pushed += bytes.size()
    return bytes.size()

func pull(frames):
    var out = PoolByteArray()
    if forced_bad_pcm:
        return 123
    if not opened or pushed == 0 or frames < 1 or frames > 1024:
        return out
    var end = min(cursor + frames*4, pcm.size())
    for i in range(cursor, end):
        out.append(pcm[i])
    cursor = end
    return out

func rate():
    return (forced_rate if forced_rate > 0 else 44100) if opened else 0
func channels():
    return 2 if opened else 0
func queued():
    return 0
func finish():
    eof = true
func close():
    close_count += 1
    opened = false
    cursor = 0
func lastError():
    return 0
