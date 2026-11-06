extends SceneTree
# Offline synthetic streaming contract: local codec bridge => Godot PCM generator => FFT
var engine = null
var analyzer = null
var started = false
var errors = []

func _init():
    call_deferred("_run")

func _on_playing(value):
    if value:
        started = true

func _on_message(value):
    print("STREAM_MESSAGE: ", value)
    if "failed" in value.to_lower() or "error" in value.to_lower() or "exceeded" in value.to_lower():
        errors.append(value)

func _run():
    var bus_index = AudioServer.get_bus_count()
    AudioServer.add_bus(bus_index)
    AudioServer.set_bus_name(bus_index, "Milkdrop")
    var effect = AudioEffectSpectrumAnalyzer.new()
    effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
    effect.buffer_length = 0.5
    AudioServer.add_bus_effect(bus_index, effect)
    analyzer = AudioServer.get_bus_effect_instance(bus_index, 0)
    engine = load("res://scripts/StreamPlayer.gd").new()
    get_root().add_child(engine)
    engine.connect("message", self, "_on_message")
    engine.connect("playing", self, "_on_playing")
    var codec = "mp3" if OS.get_cmdline_args().find("--use-ogg") < 0 else "ogg"
    engine.start("http://127.0.0.1:18097/stream?codec=" + codec)
    var peak = 0.0
    for _i in range(25):
        yield(create_timer(0.08), "timeout")
        if analyzer != null:
            var mag = analyzer.get_magnitude_for_frequency_range(420.0, 460.0)
            peak = max(peak, mag.x)
    print("STREAM_STATUS: active=", engine.active, " request_sent=", engine.request_sent, " http_status=", engine.client.get_status() if engine.client != null else -1)
    var queue = engine.pending.size() - engine.offset
    var bound = engine.max_pending_bytes
    engine.stop()
    print("E2E_PCM_FFT codec=", codec, " started=", started, " peak=", peak, " queue=", queue, " bound=", bound, " errors=", errors)
    if not started or peak <= 0.00001 or queue > bound or not errors.empty():
        printerr("FAIL: Godot streaming FFT E2E contract")
        quit(1)
    else:
        print("PASS: decoded streamed codec -> live Godot spectrum")
        quit(0)
