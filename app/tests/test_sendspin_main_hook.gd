extends SceneTree
var failures=[]
func check(ok,label):
    print("MAIN_SENDSPIN_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class FakeRuntime:
    extends Reference
    var active=true
    var current_pairing_code=""
class Facade:
    extends Reference
    var runtime=FakeRuntime.new()
    var sink=null
    var stopped=0
    func stop():
        stopped+=1
        runtime.active=false
        sink.stop()
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.25),"timeout")
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var sink=load("res://scripts/SendspinPcmOutput.gd").new()
    get_root().add_child(sink)
    var facade=Facade.new()
    facade.sink=sink
    check(sink.start_after_verified_session(1),"sink_started")
    check(app.attach_sendspin_analysis(facade) and not app.live_audio,"explicit_attachment_starts_idle")
    check(not app.attach_sendspin_analysis(facade) and facade.stopped==0,"duplicate_does_not_stop_current_player")
    facade.runtime.current_pairing_code="012345"
    app._on_sendspin_pairing_code(facade.runtime.current_pairing_code,facade,facade.runtime)
    check(app.ma_panel.pairing_code_dialog.visible and app.ma_panel.pairing_code_label.text.ends_with(facade.runtime.current_pairing_code),"private_dialog_shows_current")
    var stale=Facade.new()
    stale.runtime.current_pairing_code="999999"
    app._on_sendspin_pairing_code(stale.runtime.current_pairing_code,stale,stale.runtime)
    check(app.ma_panel.pairing_code_label.text.ends_with(facade.runtime.current_pairing_code),"stale_facade_rejected")
    app._on_sendspin_pairing_code("999999",facade,facade.runtime)
    check(app.ma_panel.pairing_code_label.text.ends_with(facade.runtime.current_pairing_code),"stale_code_rejected")
    facade.runtime.current_pairing_code=""
    app._on_sendspin_pairing_code("",facade,facade.runtime)
    check(not app.ma_panel.pairing_code_dialog.visible and app.ma_panel.pairing_code_label.text.empty(),"sdk_clear_hides_dialog")
    facade.runtime.current_pairing_code="012345"
    app._on_sendspin_pairing_code(facade.runtime.current_pairing_code,facade,facade.runtime)
    app._on_pcm_observed(sink.epoch-1,0.5,0,0,sink)
    check(not app.live_audio,"stale_epoch_rejected")
    check(sink.push_validated_pcm(PoolByteArray([0,0,0,0]),1) and not app.live_audio,"priming_silence_not_live")
    var data=PoolByteArray()
    for i in range(960):
        data.append_array(PoolByteArray([244,1,12,254] if i%64<32 else [12,254,244,1]))
    check(sink.push_validated_pcm(data,1) and app.live_audio,"real_pcm_enables_live")
    yield(create_timer(.1),"timeout")
    check(app.analysis_frame.snapshot(OS.get_ticks_msec()).source=="live_pcm","analysis_frame_is_fresh")
    check(app.fft.max()>0.0,"real_spectrum_reaches_visualizer")
    app._on_stream_active(false)
    app._on_offline_state(false)
    check(app.live_audio,"unrelated_idle_callbacks_do_not_override")
    check(sink.clear_after_verified_boundary(2) and not app.live_audio,"clear_invalidates_immediately")
    check(app.analysis_frame.snapshot(OS.get_ticks_msec()).source=="stale","clear_discards_frame")
    check(sink.push_validated_pcm(data,2) and app.live_audio,"post_clear_real_pcm_resumes")
    app._stop_all_music()
    check(not app.live_audio and facade.stopped==1 and not facade.runtime.active,"stop_disconnects_source")
    check(not app.ma_panel.pairing_code_dialog.visible and app.ma_panel.pairing_code_label.text.empty(),"stop_clears_dialog")
    sink.queue_free(); app.queue_free()
    print("MAIN_SENDSPIN_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
