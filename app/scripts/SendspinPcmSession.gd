extends Reference
# Source-only, offline Sendspin player@v1 data-plane validator.
# INPUT MUST ALREADY BE AEAD-AUTHENTICATED by an independent Noise KKpsk2
# transport and mapped to a paired server identity. NO transport is wired.
# A caller setting a boolean is NOT proof of cryptographic authentication.
# Never connect this class directly to raw WebSocket frames.
#
# Fixed PCM stereo 48000/16 ensures MA can resample and this bridge can
# reject mid-stream format changes. No automatic player registration or queue.
const RATE = 48000
const CHANNELS = 2
const BIT_DEPTH = 16
const FRAME_BYTES = 4
const CHUNK_ID = 4
const HEADER_SIZE = 13
const MAX_AUDIO_BYTES = 16384
const BUFFER_CAPACITY = 262144
const FUTURE_WINDOW_US = 2000000
const LATE_WINDOW_US = 250000
const MAX_TIME_US = 9007199254740991
var active = false
var streaming = false
var queued = []
var queued_bytes = 0
var accounted_bytes = 0
var outstanding = []
var last_timestamp = -1
var last_chunk_end = -1
var failure = ""
var session_generation = 0

func advertised_player_support():
    return {"supported_formats": [{"codec":"pcm", "sample_rate":RATE,
        "channels":CHANNELS, "bit_depth":BIT_DEPTH}],
        "buffer_capacity": BUFFER_CAPACITY}

func reset():
    active = false
    streaming = false
    queued.clear()
    queued_bytes = 0
    accounted_bytes = 0
    outstanding.clear()
    last_timestamp = -1
    last_chunk_end = -1
    failure = ""
    session_generation += 1

func reject(reason):
    reset()
    failure = reason
    return false

func begin_authenticated_playback(authenticated_transport, paired_identity,
        role_active, time_synchronized, client_available_reported):
    # This is a data-plane assertion gate, NOT an authentication API.
    # The absent cryptographic transport must verify ALL predicates.
    reset()
    if not authenticated_transport or not paired_identity or not role_active:
        return reject("authenticated player role required")
    if not time_synchronized or not client_available_reported:
        return reject("clock synchronization and state required")
    active = true
    return true

func on_stream_start(player):
    if not active or typeof(player) != TYPE_DICTIONARY:
        return reject("player role not active")
    if player.get("codec") != "pcm" or typeof(player.get("sample_rate")) != TYPE_INT or player["sample_rate"] != RATE:
        return reject("unsupported audio codec or sample rate")
    if typeof(player.get("channels")) != TYPE_INT or player["channels"] != CHANNELS:
        return reject("unsupported channel layout")
    if typeof(player.get("bit_depth")) != TYPE_INT or player["bit_depth"] != BIT_DEPTH or player.has("codec_header"):
        return reject("unsupported bit depth or codec header")
    # Server may issue an in-place stream/start with the SAME fixed
    # advertised format; preserve existing buffered chunks on that event.
    if streaming:
        return true
    queued.clear()
    queued_bytes = 0
    accounted_bytes = 0
    outstanding.clear()
    last_timestamp = -1
    last_chunk_end = -1
    streaming = true
    return true

func on_stream_clear():
    # Clear is a control event: stop old frames before new song/seek.
    if not active:
        return false
    queued.clear()
    queued_bytes = 0
    accounted_bytes = 0
    outstanding.clear()
    last_timestamp = -1
    last_chunk_end = -1
    session_generation += 1
    return true

func on_stream_end():
    if not active:
        return false
    streaming = false
    queued.clear()
    queued_bytes = 0
    accounted_bytes = 0
    outstanding.clear()
    last_timestamp = -1
    last_chunk_end = -1
    session_generation += 1
    return true

func _big_endian(bytes, first, count):
    var value = 0
    for i in range(first, first + count):
        value = (value << 8) | int(bytes[i])
    return value

func on_authenticated_audio(packet, authenticated_server_now_us):
    if not active or not streaming:
        return reject("audio outside authenticated active stream")
    if not (packet is PoolByteArray) or packet.size() <= HEADER_SIZE or packet.size() > HEADER_SIZE + MAX_AUDIO_BYTES:
        return reject("malformed audio length")
    if packet[0] != CHUNK_ID or packet[1] >= 128:
        return reject("wrong role or invalid timestamp sign")
    var length = packet.size() - HEADER_SIZE
    if length % FRAME_BYTES != 0:
        return reject("unaligned PCM frames")
    if typeof(authenticated_server_now_us) != TYPE_INT or authenticated_server_now_us < 0 or authenticated_server_now_us > MAX_TIME_US - FUTURE_WINDOW_US:
        return reject("missing authenticated clock estimate")
    var timestamp = _big_endian(packet, 1, 8)
    var send_ahead = _big_endian(packet, 9, 4)
    if timestamp > MAX_TIME_US or timestamp > authenticated_server_now_us + FUTURE_WINDOW_US:
        return reject("packet timestamp too far in future")
    if timestamp < authenticated_server_now_us - LATE_WINDOW_US:
        return reject("expired audio packet")
    if last_timestamp >= 0 and timestamp < last_timestamp:
        return reject("reordered timestamp")
    if last_chunk_end >= 0 and timestamp < last_chunk_end:
        return reject("overlapping PCM")
    # Sendspin counts the 13-byte header and full encoded payload until
    # scheduled completion, even when the renderer has dequeued bytes.
    _release_completed(authenticated_server_now_us)
    if accounted_bytes + HEADER_SIZE + length > BUFFER_CAPACITY:
        return reject("audio wire accounting bound exceeded")
    # Also cap undrained memory even if playback deadlines have elapsed.
    if queued_bytes + length > BUFFER_CAPACITY:
        return reject("undrained PCM memory bound exceeded")
    var data = PoolByteArray()
    for i in range(HEADER_SIZE, packet.size()):
        data.append(packet[i])
    queued.append({"timestamp":timestamp, "data":data, "frame_cursor":0,
        "send_ahead_valid":send_ahead > 0 and send_ahead < 4294967295})
    queued_bytes += length
    last_timestamp = timestamp
    last_chunk_end = timestamp + int(ceil(float(length / FRAME_BYTES) * 1000000.0 / float(RATE)))
    outstanding.append({"finish_at":last_chunk_end, "accounted_bytes":HEADER_SIZE+length})
    accounted_bytes += HEADER_SIZE+length
    return true

func _release_completed(authenticated_server_now_us):
    while not outstanding.empty() and outstanding[0]["finish_at"] <= authenticated_server_now_us:
        accounted_bytes -= outstanding[0]["accounted_bytes"]
        outstanding.pop_front()

func dequeue_due(authenticated_server_now_us, max_frames=1024):
    # Pure buffer scheduling: RETURN ACTUAL PCM ONLY. No fabricated samples.
    # Caller will require a calibrated output latency/time filter before wiring.
    if not active or not streaming or typeof(authenticated_server_now_us) != TYPE_INT:
        return PoolByteArray()
    if typeof(max_frames) != TYPE_INT or max_frames < 1 or max_frames > 4096:
        return PoolByteArray()
    _release_completed(authenticated_server_now_us)
    if queued.empty() or queued[0]["timestamp"] > authenticated_server_now_us:
        return PoolByteArray()
    var entry = queued[0]
    var total_frames = int(entry["data"].size() / FRAME_BYTES)
    var frames = min(max_frames, total_frames - entry["frame_cursor"])
    var start = entry["frame_cursor"] * FRAME_BYTES
    var data = PoolByteArray()
    for i in range(start, start + frames * FRAME_BYTES):
        data.append(entry["data"][i])
    entry["frame_cursor"] += frames
    queued_bytes -= frames * FRAME_BYTES
    if entry["frame_cursor"] >= total_frames:
        queued.pop_front()
    else:
        entry["timestamp"] += int(round(float(frames) * 1000000.0 / float(RATE)))
        queued[0] = entry
    return data
