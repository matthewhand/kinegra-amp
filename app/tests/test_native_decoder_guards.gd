extends SceneTree
var errors = []
func _init():
    call_deferred("_run")
func _on_message(msg):
    errors.append(msg)
func _run():
    var bus = AudioServer.get_bus_count()
    AudioServer.add_bus(bus)
    AudioServer.set_bus_name(bus, "Milkdrop")
    var fake = load("res://tests/FakeNativeCodec.gd").new()
    var player = load("res://scripts/NativeDecoderPlayer.gd").new()
    player.set_test_backend(fake)
    get_root().add_child(player)
    player.connect("message", self, "_on_message")
    if not player.begin(1):
        printerr("GUARD FAIL: cannot open fake")
        quit(1)
        return
    var other = load("res://scripts/NativeDecoderPlayer.gd").new()
    other.set_test_backend(fake)
    get_root().add_child(other)
    other.stop()
    if fake.close_count != 0 or not fake.opened:
        printerr("GUARD FAIL: inactive node hijacked active decoder")
        quit(1)
        return
    fake.forced_backpressure = true
    var packet = PoolByteArray([1, 2, 3, 4])
    if player.feed(packet) != -2 or not player.active or player.total_frames != 0:
        printerr("GUARD FAIL: backpressure mutated player")
        quit(1)
        return
    fake.forced_backpressure = false
    if player.feed(packet) != 4:
        printerr("GUARD FAIL: recovered backpressure retry")
        quit(1)
        return
    fake.forced_bad_pcm = true
    player._process(0.016)
    if player.active or errors.empty() or errors.back().find("invalid PCM") == -1:
        printerr("GUARD FAIL: malformed PCM was not rejected")
        quit(1)
        return
    if player.total_frames != 0 or fake.opened:
        printerr("GUARD FAIL: malformed PCM decoder teardown")
        quit(1)
        return
    print("PASS: backpressure retention; inactive owner isolation; malformed PCM fail-closed; counters reset")
    quit(0)
