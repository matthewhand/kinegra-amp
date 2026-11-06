extends Reference
# Source-stage handoff from an SDK PCM adapter to the existing Godot FFT bus.
# No networking or authentication occurs here. Do not instantiate for a
# live source until the SDK pairing and latency contracts are integrated.
# The adapter supplies status() -> {active: bool, generation: int} and
# acknowledge_generation(generation) and
# read(max_bytes) -> {generation: int, bytes: PoolByteArray} from an atomic
# native queue read. The generation must advance at every start/clear/end.
const MAX_READ_BYTES = 4096
const MAX_BLOCKS_PER_POLL = 4
var adapter = null
var sink = null
var generation = -1
var pending = PoolByteArray()
var failure = ""

func bind(source, output):
    stop()
    if source == null or output == null:
        failure = "Missing adapter or output"
        return false
    adapter = source
    sink = output
    failure = ""
    return true

func stop():
    if sink != null:
        sink.stop()
    adapter = null
    sink = null
    generation = -1
    pending = PoolByteArray()

func _fail(reason):
    stop()
    failure = reason
    return false

func _status():
    var status = adapter.status()
    if typeof(status) != TYPE_DICTIONARY or typeof(status.get("active")) != TYPE_BOOL or typeof(status.get("generation")) != TYPE_INT or status["generation"] < 0:
        return {}
    return status

func poll():
    if adapter == null or sink == null:
        return false
    var status = _status()
    if status.empty():
        return _fail("Invalid adapter status")
    if not status["active"]:
        if generation >= 0:
            sink.stop()
        generation = -1
        pending = PoolByteArray()
        return true
    if generation != status["generation"]:
        # Replacing the output generator drops audio already in its buffer.
        pending = PoolByteArray()
        sink.stop()
        generation = status["generation"]
        if not sink.start_after_verified_session(generation):
            return _fail("Audio output unavailable")
        # Release the SDK's ordered-clear barrier only after old generator
        # buffers are gone. A changed generation rejects this acknowledgement.
        if not adapter.acknowledge_generation(generation):
            sink.stop()
            generation = -1
            return true
    for _i in range(MAX_BLOCKS_PER_POLL):
        if pending.empty():
            var block = adapter.read(MAX_READ_BYTES)
            if typeof(block) != TYPE_DICTIONARY or typeof(block.get("generation")) != TYPE_INT or not (block.get("bytes") is PoolByteArray):
                return _fail("Invalid adapter block")
            var data = block["bytes"]
            if block["generation"] != generation:
                # A concurrent clear/end happened while reading: the next
                # poll will replace the backend before submitting new audio.
                sink.stop()
                generation = -1
                return true
            if data.size() > MAX_READ_BYTES or data.size() % 4 != 0:
                return _fail("Invalid PCM block")
            if data.empty():
                return true
            pending = data
        var fresh = _status()
        if fresh.empty():
            return _fail("Invalid adapter status")
        if not fresh["active"] or fresh["generation"] != generation:
            sink.stop()
            generation = -1
            pending = PoolByteArray()
            return true
        if not sink.push_validated_pcm(pending, generation):
            return true # Keep the same bytes under output backpressure.
        pending = PoolByteArray()
    return true
