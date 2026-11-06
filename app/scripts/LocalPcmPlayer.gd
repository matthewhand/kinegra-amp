extends Node
# Explicit local PCM16 stereo 48 kHz -> Godot speaker + original Milkdrop FFT bus.
# Does not connect to MA, sockets, Sendspin, or a clock scheduler.
# No generated tones. The caller provides its own legally available PCM source.
const RATE = 48000
const MAX_BLOCK = 4096
const STAGING = preload("res://scripts/OfflinePcmStaging.gd")
var stage = STAGING.new()
var audio = null
var generator = null
var playback = null
var active = false
var accepted_frames = 0

func _ready():
    audio = AudioStreamPlayer.new()
    audio.name = "ExplicitLocalPCM"
    audio.bus = "Milkdrop"
    add_child(audio)
    set_process(false)

func begin_local_pcm():
    stop()
    if audio == null or AudioServer.get_bus_index("Milkdrop") < 0:
        return false
    generator = AudioStreamGenerator.new()
    generator.mix_rate = RATE
    generator.buffer_length = 0.25
    audio.stream = generator
    audio.play()
    playback = audio.get_stream_playback()
    active = playback != null
    if active:
        set_process(true)
    else:
        stop()
    return active

func _signed16(bytes, at):
    var value = int(bytes[at]) | (int(bytes[at + 1]) << 8)
    return value - 65536 if value >= 32768 else value

func push_validated_pcm(bytes):
    if not active or playback == null or not (bytes is PoolByteArray):
        return false
    if bytes.empty() or bytes.size() > MAX_BLOCK or bytes.size() % 4 != 0:
        return false
    var count = int(bytes.size() / 4)
    if playback.get_frames_available() < count:
        return false
    for i in range(count):
        var at = i * 4
        var left = float(_signed16(bytes, at)) / 32768.0
        var right = float(_signed16(bytes, at + 2)) / 32768.0
        playback.push_frame(Vector2(left, right))
    accepted_frames += count
    return true

func queue_local_pcm(bytes):
    if not active:
        return false
    if not stage.enqueue(bytes):
        return false
    drain()
    return true

func drain():
    if not active:
        return false
    var delivered = false
    # Bounded per-tick drain; failed push leaves exact block untouched.
    for _i in range(4):
        if not stage.flush_to(self):
            break
        delivered = true
    return delivered

func _process(_delta):
    if active:
        drain()

func stop():
    active = false
    set_process(false)
    playback = null
    stage.reset()
    accepted_frames = 0
    if audio != null:
        audio.stop()
        audio.stream_paused = false
        audio.stream = null
    generator = null

func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED:
        stop()

func _exit_tree():
    stop()
