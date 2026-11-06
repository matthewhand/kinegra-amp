extends SceneTree
# Offline integration only: synthetic silent PCM and asserted fixture state.
# This does not test authentication, clock accuracy or a real MA connection.
var checks = 0
var errors = []
func check(ok, name):
    checks += 1
    if not ok:
        errors.append(name)
        printerr("FAIL ", name)
func packet(timestamp):
    var data = PoolByteArray([4])
    for i in range(7, -1, -1):
        data.append(int((timestamp >> (i * 8)) & 255))
    for _i in range(4):
        data.append(0)
    for _i in range(16):
        data.append(0)
    return data
func _init():
    call_deferred("run")
func run():
    if AudioServer.get_bus_index("Milkdrop") < 0:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "Milkdrop")
    var session = load("res://scripts/SendspinPcmSession.gd").new()
    var stage = load("res://scripts/OfflinePcmStaging.gd").new()
    var sink = load("res://scripts/SendspinPcmOutput.gd").new()
    get_root().add_child(sink)
    check(session.begin_authenticated_playback(true, true, true, true, true), "fixture session accepted")
    check(session.on_stream_start({"codec":"pcm", "sample_rate":48000, "channels":2, "bit_depth":16}), "fixture stream started")
    check(session.on_authenticated_audio(packet(1000000), 1000000), "silent fixture packet admitted")
    check(stage.take_due_from(session, 1000000), "due audio reaches staging")
    check(not stage.flush_to(sink) and stage.buffered_bytes == 16, "inactive output retains exact PCM")
    check(sink.start_after_verified_session(session.session_generation), "fixture output starts")
    check(stage.flush_to(sink) and stage.buffered_bytes == 0 and stage.committed_frames == 4, "actual generation-bound sink accepts staged bytes")
    check(session.on_authenticated_audio(packet(2000000), 2000000) and stage.take_due_from(session, 2000000), "old frames queued before seek")
    check(session.on_stream_clear(), "seek increments generation")
    check(not stage.flush_to(sink) and stage.buffered_bytes == 0, "seek discards old staged bytes")
    check(sink.clear_after_verified_boundary(session.session_generation), "seek clears output buffers")
    check(session.on_authenticated_audio(packet(3000000), 3000000) and stage.take_due_from(session, 3000000), "new generation queued")
    check(stage.flush_to(sink), "new generation plays after boundary")
    check(session.on_authenticated_audio(packet(4000000), 4000000) and stage.take_due_from(session, 4000000), "frames queued before disconnect")
    session.reset()
    check(not stage.flush_to(sink) and stage.buffered_bytes == 0, "disconnect discards staged bytes")
    sink.stop()
    check(not sink.active and not stage.take_due_from(session, 4000000), "disconnect leaves no replay")
    sink.queue_free()
    print("SENDSPIN_STAGE_OUTPUT_CHECKS=", checks, " FAILURES=", errors)
    quit(0 if errors.empty() else 1)
