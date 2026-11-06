extends Node
# Godot 3.6 GDNative PCM16 stereo -> AudioStreamGenerator -> Milkdrop FFT.
# This node deliberately has no network client and no MA authorization.
# Caller supplies bounded compressed chunks from an independently approved source.
signal message(text)
signal playing(is_playing)
signal pcm_observed(epoch, rms, playback_ms, latency_ms)

const MAX_COMPRESSED_CHUNK = 8192
const MAX_PCM_FRAMES = 1024
const MAX_FRAMES_PER_TICK = 4096
const MAX_RATE = 192000

var backend = null
var audio = null
var playback = null
var pending_pcm = PoolByteArray()
var pending_index = 0
var active = false
var emitted_audio = false
var ended = false
var decode_error = 0
var total_frames = 0
var native_rate = 0
var epoch = 0
var paused = false
var last_pcm_at = -1
var last_rms = 0.0
var playback_time_ms = 0.0
var queued_latency_ms = 0.0
var generator_capacity = 0
var last_completed_frames = 0

func _ready():
    if backend == null and Engine.has_singleton("TegraNativeCodec"):
        backend = Engine.get_singleton("TegraNativeCodec")
    if backend == null:
        var binding = load("res://native/TegraCodec.gdns")
        if binding != null:
            backend = binding.new()
    audio = AudioStreamPlayer.new()
    audio.name = "NativePCM"
    add_child(audio)
    audio.bus = "Milkdrop"
    set_process(true)

# Injected only by the offline fixture test. Never a source of credentials.
func set_test_backend(fixture):
    if not active:
        backend = fixture

func begin(codec):
    stop()
    if backend == null:
        emit_signal("message", "TegraNativeCodec not installed; no native audio")
        return false
    if codec != 1 and codec != 2:
        emit_signal("message", "Unsupported native codec")
        return false
    if not backend.open(codec):
        emit_signal("message", "Native decoder allocation failed")
        return false
    last_completed_frames = 0
    active = true
    ended = false
    return true

func feed(packet):
    if not active or ended or not (packet is PoolByteArray):
        return -1
    if packet.size() == 0 or packet.size() > MAX_COMPRESSED_CHUNK:
        return -1
    # -2 means BACKPRESSURE: caller must RETAIN and RETRY unchanged bytes.
    var accepted = backend.push(packet)
    if typeof(accepted) != TYPE_INT:
        _fail("Native plugin returned invalid acceptance count")
        return -1
    if accepted < -2 or (accepted != packet.size() and accepted != -2):
        _fail("Native compressed audio decode failed")
    return accepted

func end_stream():
    if active and not ended:
        ended = true
        backend.finish()

func set_paused(value):
    if not active or playback == null:
        return false
    paused = bool(value)
    audio.stream_paused = paused
    if paused:
        last_pcm_at = -1
        last_rms = 0.0
    return true

func stop():
    paused = false
    epoch += 1
    last_pcm_at = -1
    last_rms = 0.0
    playback_time_ms = 0.0
    queued_latency_ms = 0.0
    generator_capacity = 0
    # This node must not destroy a decoder session it did not open.
    if backend != null and active:
        backend.close()
    active = false
    ended = false
    emitted_audio = false
    pending_pcm = PoolByteArray()
    pending_index = 0
    native_rate = 0
    decode_error = 0
    total_frames = 0
    playback = null
    if audio != null:
        audio.stop()
        audio.stream_paused = false
        var cleared = AudioStreamGenerator.new()
        cleared.mix_rate = 22050
        cleared.buffer_length = 0.30
        audio.stream = cleared
    emit_signal("playing", false)

func _initialize_audio(rate):
    if typeof(rate) != TYPE_INT or rate < 8000 or rate > MAX_RATE:
        _fail("Unsupported native audio rate")
        return false
    # Godot/Android may provide the playback handle only after one audio
    # thread tick. Never recreate the generator merely because handle is null.
    if native_rate == 0:
        var gen = AudioStreamGenerator.new()
        gen.mix_rate = rate
        gen.buffer_length = 0.30
        audio.stream = gen
        native_rate = rate
        audio.play()
    elif native_rate != rate:
        _fail("Native codec rate changed midstream")
        return false
    playback = audio.get_stream_playback()
    if playback != null and generator_capacity == 0:
        generator_capacity = playback.get_frames_available()
    return playback != null

func _process(_delta):
    if not active or backend == null or paused:
        return
    decode_error = backend.lastError()
    if typeof(decode_error) != TYPE_INT or decode_error != 0:
        _fail("Native decoder error")
        return
    var budget = MAX_FRAMES_PER_TICK
    for _round in range(4):
        if not active or budget <= 0:
            return
        if pending_index >= pending_pcm.size():
            var result = backend.pull(MAX_PCM_FRAMES)
            if not (result is PoolByteArray):
                _fail("Native plugin returned invalid PCM payload")
                return
            pending_pcm = result
            pending_index = 0
            if pending_pcm.size() == 0:
                var error = backend.lastError()
                var remaining = backend.queued()
                if typeof(error) != TYPE_INT or error != 0:
                    _fail("Native decoder returned an error")
                elif typeof(remaining) != TYPE_INT or remaining < 0 or remaining > 131072:
                    _fail("Native decoder reported invalid queue")
                elif ended and remaining == 0 and playback != null and playback.get_frames_available() >= generator_capacity:
                    last_completed_frames = total_frames
                    stop()
                    emit_signal("message", "Native source ended")
                return
            if pending_pcm.size() > MAX_PCM_FRAMES * 4 or pending_pcm.size() % 4 != 0:
                _fail("Native PCM frame bound exceeded")
                return
        # A codec change after the first PCM frame is an error even
        # while an earlier playback handle is still available.
        var rate = backend.rate()
        if playback == null or (native_rate != 0 and rate != native_rate):
            if not _initialize_audio(rate):
                return
        var frames = min(budget, min(playback.get_frames_available(), int((pending_pcm.size()-pending_index)/4)))
        if frames <= 0:
            return
        var energy = 0.0
        for _i in range(frames):
            var l = _signed16(pending_pcm, pending_index)
            var r = _signed16(pending_pcm, pending_index + 2)
            playback.push_frame(Vector2(float(l)/32768.0, float(r)/32768.0))
            energy += (float(l) * float(l) + float(r) * float(r)) / (2.0 * 32768.0 * 32768.0)
            pending_index += 4
        total_frames += frames
        last_pcm_at = OS.get_ticks_msec()
        last_rms = sqrt(energy / max(1, frames))
        var queued = max(0, generator_capacity - playback.get_frames_available())
        queued_latency_ms = float(queued) * 1000.0 / native_rate
        playback_time_ms = max(playback_time_ms, float(total_frames - queued) * 1000.0 / native_rate)
        emit_signal("pcm_observed", epoch, last_rms, playback_time_ms, queued_latency_ms)
        budget -= frames
        if not emitted_audio:
            emitted_audio = true
            emit_signal("playing", true)

func _signed16(bytes, index):
    var raw = int(bytes[index]) + (int(bytes[index+1]) << 8)
    return raw - 65536 if raw >= 32768 else raw

func _fail(message):
    stop()
    emit_signal("message", message)

func _notification(what):
    if what == MainLoop.NOTIFICATION_APP_PAUSED:
        stop()

func _exit_tree():
    if backend != null and active:
        backend.close()
    active = false
    if audio != null:
        audio.stop()
