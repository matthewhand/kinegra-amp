extends SceneTree
# Production Main + facade + runtime + sink; only the native I/O boundary is synthetic.
var failures=[]
var checks=0
var app=null
class Backend:
    extends Reference
    var opens=0
    var closes=0
    var confirms=0
    var tick_result=true
    var open_result=true
    var confirm_result=true
    var code=""
    var value={"active":false,"generation":0,"paired":false,"pairing_window":false,"client_id":"synthetic-own-client"}
    func open(_endpoint,_vault):
        opens+=1
        return open_result
    func close():closes+=1
    func tick():return tick_result
    func status():return value
    func pairing_code():return code
    func confirm_pairing():
        confirms+=1
        return confirm_result
    func reveal_pairing_token():return "synthetic-private-pairing-token"
    func command(_name):return false
func check(ok,label):
    checks+=1;print("PAIR_GUARD_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func install():
    var backend=Backend.new()
    var facade=load("res://scripts/SendspinExperienceFacade.gd").new()
    app.add_child(facade)
    check(facade.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin",true,backend,Reference.new()),"explicit_facade_start")
    facade.runtime.set_process(false)
    check(app.attach_sendspin_analysis(facade),"actual_main_owns_facade")
    facade.runtime.connect("state_changed",app,"_on_sendspin_state",[facade])
    facade.runtime.connect("pairing_code_changed",app,"_on_sendspin_pairing_code",[facade,facade.runtime])
    return facade
func _init():call_deferred("run")
func run():
    app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout");app.set_process(false);app.music_ui.set_process(false)
    AudioServer.set_bus_mute(0,true)
    app.ma_panel.catalog.token="synthetic-library-access"
    app._start_sendspin_player("ws://10.1.2.3:8927/sendspin",true)
    check(app.sendspin_facade==null and app.ma_panel.playback_state=="error" and not app.offline_music.is_playing(),"unavailable_native_start_is_recoverable_without_fallback")
    check(not app._confirm_sendspin_pairing() and app.ma_panel.playback_state=="idle","finish_without_session_does_not_claim_connecting")
    var facade=install();var backend=facade.client;var runtime=facade.runtime
    app._start_sendspin_player("ws://10.1.2.3:8927/sendspin",true)
    app._start_sendspin_player("ws://10.1.2.3:8927/sendspin",true)
    check(backend.opens==1 and app.sendspin_facade==facade,"repeat_connect_keeps_one_native_session")
    backend.value.paired=true;backend.code="012345";runtime.step()
    check(runtime.current_pairing_code.empty() and not app.ma_panel.pairing_code_dialog.visible,"paired_state_clears_late_native_private_code")
    check(app.ma_panel.sendspin_paired and app.ma_panel.sendspin_player_id=="synthetic-own-client","verified_paired_callback_sets_route")
    app._start_sendspin_player("ws://10.1.2.3:8927/sendspin",true)
    app._confirm_sendspin_pairing();app._confirm_sendspin_pairing()
    check(app.ma_panel.sendspin_paired and app.ma_panel.sendspin_player_id=="synthetic-own-client" and backend.confirms==0,"repeat_finish_preserves_paired_route_without_native_confirmation")
    runtime.connection_deadline_ms=OS.get_ticks_msec()-1
    check(runtime.step() and runtime.active and runtime.connection_deadline_ms==0,"paired_stream_never_killed_by_initial_timeout")
    app._stop_sendspin_player()
    check(backend.closes==1 and app.sendspin_facade==null,"explicit_disconnect_closes_once")
    backend.value.paired=false
    facade=install();backend=facade.client;runtime=facade.runtime
    backend.value.pairing_window=true;backend.code="012345"
    check(runtime.step() and runtime.pairing_started and runtime.connection_deadline_ms-OS.get_ticks_msec()>119000,"human_pairing_gets_separate_two_minute_window")
    check(app.ma_panel.pairing_code_dialog.visible,"valid_current_code_reaches_private_dialog")
    check(app._confirm_sendspin_pairing() and not app._confirm_sendspin_pairing() and backend.confirms==1,"repeated_finish_confirms_pending_window_once")
    backend.value.pairing_window=false;backend.code="";runtime.step()
    backend.value.pairing_window=true;runtime.step()
    check(app._confirm_sendspin_pairing() and backend.confirms==2,"new_pairing_window_can_be_confirmed_explicitly")
    app._reveal_sendspin_pairing()
    app._stop_sendspin_player()
    check(not app.ma_panel.pairing_code_dialog.visible and not app.ma_panel.sendspin_token_dialog.visible and app.ma_panel.pairing_code_label.text.empty() and app.ma_panel.sendspin_token_label.text.empty(),"disconnect_clears_all_private_pairing_dialogs")
    app._on_sendspin_state("paired","stale",facade)
    app._on_sendspin_pairing_code("012345",facade,runtime)
    check(not app.ma_panel.sendspin_paired and not app.ma_panel.pairing_code_dialog.visible,"late_callback_after_cancel_cannot_reopen_or_pair")
    for value in [null,"bad",{}, {"active":1,"generation":0,"paired":false},{"active":false,"generation":"0","paired":false},{"active":false,"generation":-1,"paired":false},{"active":false,"generation":0,"paired":"yes"},{"active":false,"generation":0,"paired":false,"pairing_window":1},{"active":true,"generation":0,"paired":false}]:
        facade=install();backend=facade.client;runtime=facade.runtime;backend.value=value
        check(not runtime.step() and not runtime.active and backend.closes==1 and runtime.state=="error" and not app.ma_panel.sendspin_paired,"malformed_native_status_fails_closed")
        app._stop_sendspin_player()
    facade=install();backend=facade.client;runtime=facade.runtime
    backend.value="invalid"
    app._on_sendspin_state("paired","invalid boundary",facade)
    check(not app.ma_panel.sendspin_paired and app.ma_panel.playback_state=="error","main_callback_rejects_non_dictionary_without_exception")
    backend.value={"paired":1,"client_id":"synthetic-own-client"}
    app._on_sendspin_state("paired","invalid bool",facade)
    check(not app.ma_panel.sendspin_paired and app._sendspin_controls().empty(),"integer_cannot_impersonate_native_paired_boolean")
    app._stop_sendspin_player()
    for value in [null,123456,"12345","1234567","12x456","+12345"," 12345"]:
        app.ma_panel.show_pairing_code(value)
        check(not app.ma_panel.pairing_code_dialog.visible,"malformed_private_code_never_opens_dialog")
    for opened in [false,1]:
        var rejected=Backend.new();rejected.open_result=opened
        var unavailable=load("res://scripts/SendspinExperienceFacade.gd").new();app.add_child(unavailable)
        check(not unavailable.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin",true,rejected,Reference.new()) and rejected.closes==1 and unavailable.runtime==null,"failed_or_malformed_open_closes_partial_session")
        unavailable.queue_free()
    for pairing in [false,true]:
        facade=install();backend=facade.client;runtime=facade.runtime
        if pairing:backend.code="012345";runtime.step()
        runtime.connection_deadline_ms=OS.get_ticks_msec()-1
        check(not runtime.step() and not runtime.active and backend.closes==1 and runtime.state=="error" and not app.ma_panel.pairing_code_dialog.visible,"bounded_connect_or_pair_timeout_is_recoverable")
        check(app.ma_panel.catalog.token=="synthetic-library-access","recoverable_failure_preserves_verified_library_access")
        runtime.current_pairing_code="012345"
        app._on_sendspin_pairing_code("012345",facade,runtime)
        app._on_sendspin_state("paired","late timeout reply",facade)
        check(not app.ma_panel.pairing_code_dialog.visible and not app.ma_panel.sendspin_paired,"late_same_runtime_callback_after_timeout_cannot_reopen_controls")
        app._stop_sendspin_player()
    facade=install();backend=facade.client;runtime=facade.runtime
    backend.tick_result=1
    check(not runtime.step() and not runtime.active,"malformed_native_tick_boolean_fails_closed")
    app._stop_sendspin_player()
    facade=install();backend=facade.client;runtime=facade.runtime
    backend.value.paired=true;runtime.step()
    check(app.ma_panel.sendspin_paired and not app.offline_music.is_playing(),"explicit_retry_after_errors_is_usable_without_autoplay")
    app._stop_sendspin_player();app.queue_free();yield(self,"idle_frame")
    print("PAIR_GUARD_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
