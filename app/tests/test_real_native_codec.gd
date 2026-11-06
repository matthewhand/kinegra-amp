extends SceneTree
var failures = []
func _init():
    call_deferred("run")
func run():
    var index = AudioServer.get_bus_count()
    AudioServer.add_bus(index)
    AudioServer.set_bus_name(index, "Milkdrop")
    var effect = AudioEffectSpectrumAnalyzer.new()
    effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
    effect.buffer_length = 0.4
    AudioServer.add_bus_effect(index, effect)
    var analyzer = AudioServer.get_bus_effect_instance(index, 0)
    for codec in [1, 2]:
        var player = load("res://scripts/NativeDecoderPlayer.gd").new()
        get_root().add_child(player)
        if player.backend == null or not player.begin(codec):
            failures.append("real native binding unavailable")
            continue
        var file = File.new()
        file.open("res://tests/fixtures/synthetic." + ("mp3" if codec == 1 else "ogg"), File.READ)
        var compressed = file.get_buffer(file.get_len())
        file.close()
        var position = 0
        var peak = 0.0
        var max_rms = 0.0
        var max_frames = 0
        for _i in range(220):
            if position < compressed.size() and player.active:
                var packet = compressed.subarray(position, min(position + 997, compressed.size()) - 1)
                var accepted = player.feed(packet)
                if accepted > 0:
                    position += accepted
            elif player.active and not player.ended:
                player.end_stream()
            yield(create_timer(0.01), "timeout")
            peak = max(peak, analyzer.get_magnitude_for_frequency_range(420.0, 460.0).x)
            max_rms = max(max_rms, player.last_rms)
            max_frames = max(max_frames, max(player.total_frames, player.last_completed_frames))
        print("REAL_GDNATIVE codec=",codec," frames=",max_frames," fft_peak=",peak," rms=",max_rms," bytes=",position)
        if max_frames < 30000 or peak <= 0.00001 or max_rms <= 0.00001 or position != compressed.size():
            failures.append("real native compressed PCM FFT " + str(codec))
        player.stop()
        player.queue_free()
    print("REAL_GDNATIVE_FAILURES=", failures)
    quit(0 if failures.empty() else 1)
