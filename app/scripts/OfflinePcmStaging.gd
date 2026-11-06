extends Reference
# Silent, source-only bridge between validated PCM scheduling and an output.
# Never instantiates AudioStreamPlayer or connects sockets. Backpressure
# retains EXACT BYTES until a future output sink accepts the whole block.
const MAX_BYTES = 32768
const FRAME_BYTES = 4
const MAX_BLOCK_BYTES = 4096
var blocks = []
var buffered_bytes = 0
var committed_frames = 0
var bound_session = null
var bound_generation = -1

func reset():
    blocks.clear()
    buffered_bytes = 0
    committed_frames = 0
    bound_session = null
    bound_generation = -1

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

func take_due_from(session, server_time_us):
    # Only the previously validated Sendspin session can produce due bytes.
    # Reserve capacity *before* dequeue so no bytes can disappear on pressure.
    if bound_session != null and (bound_session != session or not bound_session.active or not bound_session.streaming or bound_session.session_generation != bound_generation):
        reset()
    if session == null or not session.active or not session.streaming:
        return false
    if bound_session == null and not blocks.empty():
        return false
    if buffered_bytes + MAX_BLOCK_BYTES > MAX_BYTES:
        return false
    var due = session.dequeue_due(server_time_us, 1024)
    if due.empty():
        return false
    if bound_session == null:
        bound_session = session
        bound_generation = session.session_generation
    return enqueue(due)

func flush_to(sink):
    if bound_session != null and (not bound_session.active or not bound_session.streaming or bound_session.session_generation != bound_generation):
        reset()
        return false
    if sink == null or blocks.empty():
        return false
    var front = blocks[0]
    # A network session's generation must reach the real sink: it uses this
    # value to reject audio left over from a seek, restart, or disconnect.
    # Local PCM has no session generation and retains its one-argument API.
    var accepted = sink.push_validated_pcm(front, bound_generation) if bound_session != null else sink.push_validated_pcm(front)
    if not accepted:
        # Not even one frame consumed; caller may retry safely.
        return false
    buffered_bytes -= front.size()
    committed_frames += int(front.size() / FRAME_BYTES)
    blocks.pop_front()
    return true
