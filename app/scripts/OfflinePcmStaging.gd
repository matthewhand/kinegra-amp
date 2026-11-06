extends Reference
# Bounded local PCM staging. Backpressure retains exact bytes until the
# output sink accepts a whole block; decoding and device output live elsewhere.
const MAX_BYTES = 32768
const FRAME_BYTES = 4
const MAX_BLOCK_BYTES = 4096
var blocks = []
var buffered_bytes = 0
var committed_frames = 0

func reset():
    blocks.clear()
    buffered_bytes = 0
    committed_frames = 0

func enqueue(data):
    if not (data is PoolByteArray):
        return false
    if data.empty() or data.size() > MAX_BLOCK_BYTES or data.size() % FRAME_BYTES != 0:
        return false
    if buffered_bytes + data.size() > MAX_BYTES:
        return false
    blocks.append(PoolByteArray(data))
    buffered_bytes += data.size()
    return true

func flush_to(sink):
    if sink == null or blocks.empty():
        return false
    var front = blocks[0]
    var accepted = sink.push_validated_pcm(front)
    if not accepted:
        # Not even one frame consumed; caller may retry safely.
        return false
    buffered_bytes -= front.size()
    committed_frames += int(front.size() / FRAME_BYTES)
    blocks.pop_front()
    return true
