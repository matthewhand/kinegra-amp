extends SceneTree
var failures=[]
func check(ok,label):
    print("AUDIO_BUFFER_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    if AudioServer.get_bus_index("Milkdrop")<0:
        AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.get_bus_count()-1,"Milkdrop")
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var sink=load("res://scripts/SendspinPcmOutput.gd").new();get_root().add_child(sink)
    check(sink.start_after_verified_session(1) and sink.buffering and sink.audio.stream_paused,"starts_paused_for_prefill")
    var pcm=PoolByteArray();pcm.resize(4096)
    for _i in range(17): check(sink.push_validated_pcm(pcm,1),"prefill_accepts_block")
    check(sink.buffering and sink.audio.stream_paused,"does_not_start_on_a_thin_buffer")
    check(sink.push_validated_pcm(pcm,1) and not sink.buffering and not sink.audio.stream_paused,"resumes_after_384ms_prefill")
    check(sink.clear_after_verified_boundary(2) and sink.buffering and sink.mixer_feedback.queued==0,"seek_flushes_and_reprimes")
    check(not sink.push_validated_pcm(pcm,1),"old_track_pcm_rejected")
    sink.stop();check(not sink.buffering and not sink.active,"stop_discards_prefill")
    sink.queue_free()
    print("AUDIO_BUFFER_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
