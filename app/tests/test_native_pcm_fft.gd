extends SceneTree
# Two-stage synthetic contract:
# (1) real native C decoder generated fixture PCM16LE, hash checked by runner
# (2) the same GDScript NativeDecoderPlayer PCM->AudioStreamGenerator->FFT code
#     used for Android plugin, against an explicit TEST ONLY adapter.
var node = null
var peak = 0.0
var saw_play = false
var errors = []
func _init():
    call_deferred("_run")
func _on_playing(value):
    if value:
        saw_play = true
func _on_error(msg):
    if msg != "Native source ended":
        errors.append(msg)
func _run():
    var index = AudioServer.get_bus_count()
    AudioServer.add_bus(index)
    AudioServer.set_bus_name(index, "Milkdrop")
    var effect = AudioEffectSpectrumAnalyzer.new()
    effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
    effect.buffer_length = 0.4
    AudioServer.add_bus_effect(index, effect)
    var analyzer = AudioServer.get_bus_effect_instance(index, 0)
    node = load("res://scripts/NativeDecoderPlayer.gd").new()
    node.set_test_backend(load("res://tests/FakeNativeCodec.gd").new())
    get_root().add_child(node)
    node.connect("playing", self, "_on_playing")
    node.connect("message", self, "_on_error")
    if not node.begin(1):
        printerr("FAIL: native PCM playback could not start")
        quit(1)
        return
    # A small fictional compressed chunk gates fake fixture for this test.
    var fixture_gate = PoolByteArray([1, 2, 3])
    if node.feed(fixture_gate) != 3:
        printerr("FAIL: bounded plugin push interface")
        quit(1)
        return
    node.end_stream()
    for _i in range(28):
        yield(create_timer(0.07), "timeout")
        if analyzer != null:
            var magnitude = analyzer.get_magnitude_for_frequency_range(420.0, 460.0)
            peak = max(peak, magnitude.x)
    var count = max(node.total_frames, node.last_completed_frames)
    node.stop()
    print("NATIVE_PCM_GODOT_FFT started=", saw_play, " peak=", peak, " frames=", count, " errors=", errors)
    if not saw_play or peak <= 0.00001 or count < 6000 or not errors.empty():
        printerr("FAIL: native-decoded PCM -> real Godot FFT fixture")
        quit(1)
    else:
        print("PASS: native C decoded PCM -> GDScript audio generator -> real Godot FFT")
        quit(0)
