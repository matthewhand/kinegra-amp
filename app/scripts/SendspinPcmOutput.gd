extends Node
# Authenticated Sendspin PCM sink. Output timing is an estimate, not a DAC timestamp.
signal pcm_observed(epoch, rms, playback_ms, latency_ms)
signal analysis_invalidated

const RATE = 48000
const MAX_PUSH_FRAMES = 1024
const PREFILL_FRAMES = 18432 # 384 ms at 48 kHz, before starting/resuming the mixer.
var buffering = false
var underruns = 0
var rebuffer_count = 0
var last_skips = 0
var audio = null
var generator = null
var playback = null
var active = false
var stream_generation = -1
var epoch = 0
var last_pcm_at = -1
var last_data_at = -1
var last_rms = 0.0
var playback_time_ms = 0.0
var queued_latency_ms = 0.0
var reported_frames = 0
var mixer_feedback = preload("res://scripts/SendspinMixerFeedback.gd").new()
var cached_output_latency_us = 0
var latency_measured_at_us = 0

func _ready():
    audio = AudioStreamPlayer.new()
    audio.name = "AuthenticatedSendspinPCM"
    add_child(audio)
    # Same bus as the existing real-audio FFT visualizer.
    audio.bus = "Milkdrop"

func stop():
    var was_active=active
    epoch += 1
    last_pcm_at = -1
    last_data_at = -1
    last_rms = 0.0
    playback_time_ms = 0.0
    queued_latency_ms = 0.0
    reported_frames = 0
    mixer_feedback.reset()
    stream_generation = -1
    active = false
    playback = null
    if audio != null:
        audio.stop()
        audio.stream_paused = false
        audio.stream = null
    generator = null
    buffering = false
    if was_active: emit_signal("analysis_invalidated")

func start_after_verified_session(generation = 0):
    # Only the authenticated generation-checked bridge calls this.
    stop()
    if typeof(generation) != TYPE_INT or generation < 0:
        return false
    if audio == null or AudioServer.get_bus_index("Milkdrop") < 0:
        return false
    generator = AudioStreamGenerator.new()
    generator.mix_rate = RATE
    generator.buffer_length = 0.5
    audio.stream = generator
    audio.play()
    audio.stream_paused = true
    buffering = true
    playback = audio.get_stream_playback()
    active = playback != null
    if active:
        stream_generation = generation
        last_skips = playback.get_skips()
        if not mixer_feedback.begin(generation,playback.get_frames_available()):
            stop()
            return false
        var latency=AudioServer.get_output_latency()
        if is_nan(latency) or is_inf(latency) or latency<0.0 or latency>2.0:
            stop()
            return false
        cached_output_latency_us=int(latency*1000000.0)
        latency_measured_at_us=OS.get_ticks_usec()
    if not active:
        stop()
    return active

func _signed16(data, index):
    var value = int(data[index]) | (int(data[index + 1]) << 8)
    return value - 65536 if value >= 32768 else value

func clear_after_verified_boundary(generation):
    # Replace the generator to discard backend-buffered frames as well as
    # caller staging. The authenticated adapter supplies monotonic generations.
    if not active or typeof(generation) != TYPE_INT or generation <= stream_generation:
        return false
    return start_after_verified_session(generation)

func push_validated_pcm(bytes, generation = -1):
    if typeof(generation) != TYPE_INT or generation != stream_generation:
        return false
    if not active or playback == null or not (bytes is PoolByteArray):
        return false
    if bytes.empty() or bytes.size() % 4 != 0 or bytes.size() > 4 * MAX_PUSH_FRAMES:
        return false
    var frames = int(bytes.size() / 4)
    # Reject rather than silently dropping audio; caller must retain frames.
    if playback.get_frames_available() < frames:
        return false
    if not mixer_feedback.pushed(generation,frames):
        return false
    var energy=0.0
    var converted=PoolVector2Array()
    converted.resize(frames)
    for i in range(frames):
        var off = 4 * i
        var left = float(_signed16(bytes, off)) / 32768.0
        var right = float(_signed16(bytes, off + 2)) / 32768.0
        converted[i]=Vector2(left, right)
        energy+=(left*left+right*right)*0.5
    if not playback.push_buffer(converted):
        mixer_feedback.queued-=frames
        return false
    last_data_at=OS.get_ticks_msec() # Digital silence is still valid transport data.
    if buffering and mixer_feedback.queued>=PREFILL_FRAMES:
        buffering=false
        last_skips=playback.get_skips()
        audio.stream_paused=false
    var rms=sqrt(energy/float(frames))
    # Startup/underflow silence must not be labelled as live content.
    # Retain the previous timestamp so ordinary freshness expiry still works.
    if rms>0.00001:
        last_rms=rms
        last_pcm_at=OS.get_ticks_msec()
        playback_time_ms=float(reported_frames)*1000.0/float(RATE)
        queued_latency_ms=float(mixer_feedback.queued)*1000.0/float(RATE)+float(cached_output_latency_us)/1000.0
        emit_signal("pcm_observed",epoch,last_rms,playback_time_ms,queued_latency_ms)
    return true

# Estimate consumed mixer frames and their output finish time. This is not a
# measured hardware timestamp and needs device/latency validation.
func report_mixer_feedback(adapter):
    if not active or playback==null or adapter==null:
        return false
    var skips=playback.get_skips()
    var low_water=mixer_feedback.capacity-playback.get_frames_available()<2400 and last_data_at>=0 and OS.get_ticks_msec()-last_data_at>=120
    if not buffering and (skips>last_skips or low_water):
        underruns+=max(0,skips-last_skips)
        rebuffer_count+=1
        mixer_feedback.reanchor_clock()
        buffering=true
        audio.stream_paused=true
    last_skips=skips
    if mixer_feedback.queued==0:
        return true
    var clock=adapter.clock_now_us()
    var elapsed=AudioServer.get_time_since_last_mix()
    if is_nan(elapsed) or is_inf(elapsed) or elapsed<0.0:
        return false
    if OS.get_ticks_usec()-latency_measured_at_us>=2000000:
        var latency=AudioServer.get_output_latency()
        if is_nan(latency) or is_inf(latency) or latency<0.0 or latency>2.0:
            return false
        cached_output_latency_us=int(latency*1000000.0)
        latency_measured_at_us=OS.get_ticks_usec()
    var report=mixer_feedback.sample(stream_generation,playback.get_frames_available(),clock,int(elapsed*1000000.0),cached_output_latency_us)
    if report.empty(): return false
    if report["frames"]==0: return true
    if not adapter.report_output_played(stream_generation,report["frames"],report["finish_us"]): return false
    if not mixer_feedback.committed(stream_generation,report): return false
    reported_frames+=report["frames"]
    return true

func buffer_stats():
    return {"queued_ms":int(float(mixer_feedback.queued)*1000.0/float(RATE)),"underruns":underruns,"rebuffers":rebuffer_count,"buffering":buffering,"data_age_ms":OS.get_ticks_msec()-last_data_at if last_data_at>=0 else -1}

func _notification(what):
    if what == MainLoop.NOTIFICATION_APP_PAUSED:
        stop()

func _exit_tree():
    stop()

# Current generator occupancy only; excludes hardware latency and SDK lookahead.
func queued_audio_frames(generation):
    if not active or playback==null or stream_generation!=generation or mixer_feedback.generation!=generation:return -1
    var free=playback.get_frames_available()
    if free<0 or free>mixer_feedback.capacity:return -1
    return mixer_feedback.capacity-free
