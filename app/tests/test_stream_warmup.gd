extends SceneTree
var failures=[]
func check(ok,label):
    print("STREAM_WARMUP_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var policy=load("res://scripts/StreamWarmupBudget.gd").new()
    check(policy.prepare(0) and policy.observe(500,{}) and policy.holding,"preload_before_stream_suspends_visuals")
    check(not policy.observe(20000,{}),"failed_preload_has_bounded_wait")
    var audio={"active":true,"generation":4,"buffering":true,"queued_ms":680}
    check(policy.observe(100,audio),"cap_before_scheduled_audio")
    check(policy.observe(5100,audio),"elapsed_time_alone_not_ready")
    audio.buffering=false
    check(policy.observe(5120,audio),"hold_after_first_content")
    check(policy.observe(7000,audio),"hold_through_clock_settle")
    audio.queued_ms=80
    check(policy.observe(7100,audio),"low_queue_restarts_stability_window")
    audio.queued_ms=680
    check(policy.observe(7120,audio) and policy.observe(9100,audio),"new_full_stability_window")
    check(not policy.observe(9120,audio),"restore_after_two_healthy_seconds")
    audio.buffering=true
    check(not policy.observe(9200,audio),"same_generation_does_not_rearm")
    audio.generation=5
    check(policy.observe(9300,audio),"clear_or_restart_rearms")
    check(not policy.observe(9400,{}) and policy.generation==-1,"stop_clears_cap")
    check(not policy.observe(9500,{"active":true,"generation":"bad"}),"invalid_generation_ignored")
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.set_process(false)
    app._select_visual_quality(1)
    app.backing_dancers.pressed=true;app._set_backing_dancers(true)
    app.stream_warmup_budget.observe(100,audio)
    app._apply_visual_budget(app.visual_governor.snapshot())
    check(app.visual_quality_level==0 and app.visual_governor.mode=="full" and app.backing_dancers.pressed,"temporary_cap_keeps_quality_and_dancer_choices")
    check(app.visual.material==null and app.avatar_visual.render_budget_fps==0 and app.backing_avatars[0].render_budget_fps==0 and not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0),"cap_stops_shader_avatars_and_fft")
    app.set_visuals_enabled(false);app.stream_warmup_budget.reset();app._apply_visual_budget(app.visual_governor.snapshot())
    check(app.visual_quality_level==0,"visuals_off_survives_warmup")
    app.set_visuals_enabled(true)
    check(app.visual_quality_level==2 and app.backing_avatars[0].render_budget_fps==30 and AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0),"selected_visuals_restore")
    var sink=load("res://scripts/SendspinPcmOutput.gd").new();get_root().add_child(sink)
    check(sink.start_after_verified_session(8),"real_generator_start")
    var bytes=PoolByteArray();bytes.resize(4096)
    for i in range(17):check(sink.push_validated_pcm(bytes,8),"prefill_block_%d"%i)
    check(sink.buffering and sink.audio.stream_paused,"real_sink_keeps_362ms_paused")
    check(sink.push_validated_pcm(bytes,8) and not sink.buffering and not sink.audio.stream_paused,"real_sink_starts_at_384ms")
    check(not sink.push_validated_pcm(bytes,7),"stale_generation_rejected")
    sink.stop();sink.queue_free();app.queue_free()
    print("STREAM_WARMUP_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
