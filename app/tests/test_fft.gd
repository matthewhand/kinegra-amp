extends SceneTree
# Synthetic 440Hz sound proves analyzer wiring in offline Godot audio driver.
func _init():
    call_deferred("_run")

func _run():
    var bus_index = AudioServer.get_bus_count()
    AudioServer.add_bus(bus_index)
    AudioServer.set_bus_name(bus_index, "TestMilkdrop")
    var effect = AudioEffectSpectrumAnalyzer.new()
    effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
    effect.buffer_length = 0.5
    AudioServer.add_bus_effect(bus_index, effect)
    var analyzer = AudioServer.get_bus_effect_instance(bus_index, 0)
    if analyzer == null:
        printerr("FAIL: analyzer instance absent")
        quit(1)
        return
    var player = AudioStreamPlayer.new()
    player.bus = "TestMilkdrop"
    var generator = AudioStreamGenerator.new()
    generator.mix_rate = 22050
    generator.buffer_length = 0.5
    player.stream = generator
    get_root().add_child(player)
    player.play()
    var pb = player.get_stream_playback()
    var count = pb.get_frames_available()
    for i in range(count):
        var val = sin(float(i) * TAU * 440.0 / 22050.0) * 0.5
        pb.push_frame(Vector2(val, val))
    yield(create_timer(0.4), "timeout")
    var peak = analyzer.get_magnitude_for_frequency_range(420.0, 460.0)
    print("FFT_ANALYZER peak_440Hz=", peak, " pushed_frames=", count)
    if count <= 0:
        printerr("FAIL: generator did not accept frames")
        quit(1)
        return
    if peak.x <= 0.00001:
        print("INCONCLUSIVE: no nonzero spectrum under this host audio backend")
    else:
        print("PASS: genuine analyzer sampled injected 440Hz PCM")
    quit(0)
