extends SceneTree
var failures = []
func _init():
    call_deferred("run")
func run():
    var args = OS.get_cmdline_args()
    var port = args[args.find("--native-test-port") + 1]
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
        var transport = load("res://scripts/NativeHTTPTransport.gd").new()
        get_root().add_child(transport)
        var origin = "http://127.0.0.1:" + port
        transport.configure(player, origin, true)
        if not transport.start(origin + "/synthetic." + ("mp3" if codec == 1 else "ogg"), codec):
            failures.append("start failed")
        var peak = 0.0
        var max_frames = 0
        var rms = 0.0
        for _i in range(240):
            yield(create_timer(.01), "timeout")
            peak = max(peak, analyzer.get_magnitude_for_frequency_range(420.0, 460.0).x)
            max_frames = max(max_frames, max(player.total_frames, player.last_completed_frames))
            rms = max(rms, player.last_rms)
            if transport.pending.size() > 8192:
                failures.append("compressed transport bound")
        print("NATIVE_HTTP codec=", codec, " frames=", max_frames, " fft_peak=", peak, " rms=", rms)
        if max_frames < 30000 or peak <= .00001 or rms <= .00001:
            failures.append("native HTTP PCM FFT")
        transport.stop()
        transport.queue_free()
        player.queue_free()
    print("NATIVE_HTTP_FAILURES=", failures)
    quit(0 if failures.empty() else 1)
