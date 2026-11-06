extends SceneTree
class Catalog:
    extends Node
    var policy=preload("res://scripts/ConnectionPolicy.gd").new()
    var token=""
    var endpoint=""
    var epoch=0
    var browsed=0
    var trusted_private_http=false
    var request_node=null
    var current_page={}
    func resolve_local_player(_id):return ""
    func selection():return {}
    func configure(origin,credential,_streams,_trust):
        close();endpoint=origin.strip_edges().trim_suffix("/");token=credential
        return true
    func browse(_kind):browsed+=1
    func cancel():epoch+=1
    func close():
        cancel();token="";endpoint=""
class Vault:
    extends Reference
    var reads=0
    var writes=0
    func tokenEndpoint():return "https://fictional-ma.invalid"
    func storageStatus():return "not_configured"
    func loadTokenForEndpoint(_origin):
        reads+=1
        return ""
    func storeTokenForEndpoint(_token,_origin):
        writes+=1
        return true
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    func status():return {"paired":true,"client_id":"fictional-client"}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    var stops=0
    func stop():
        stops+=1
        runtime.active=false
class Operation:
    extends Node
    var failure_reason="auth_failed"
    var action="read"
var failures=[]
func check(ok,label):
    print("EPHEMERAL_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    AudioServer.set_bus_mute(0,true)
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.set_process(false);app.music_ui.set_process(false)
    var panel=app.ma_panel
    var original=panel.catalog
    var catalog=Catalog.new();panel.add_child(catalog);panel.catalog=catalog
    var vault=Vault.new();panel.credential_store_override=vault
    panel.settings_path="user://ephemeral-session-test.cfg"
    panel.endpoint_edit.text="https://fictional-ma.invalid"
    panel.token_edit.text="fictional-nonremember-token";panel.remember_access.pressed=false
    check(panel._connect_catalog() and app._library_session_token.empty() and vault.writes==0,"unchecked_configure_is_not_yet_authorized_or_saved")
    panel._credential_state("ready","fictional authenticated result")
    check(app._library_session_token=="fictional-nonremember-token" and app._library_session_origin=="https://fictional-ma.invalid" and vault.writes==0,"successful_auth_retains_origin_bound_ram_without_remember")
    var facade=Facade.new();app.sendspin_facade=facade;panel.sendspin_paired=true
    panel._close()
    check(catalog.token.empty() and app._library_credential(false)=="fictional-nonremember-token" and app._queue_controls_available() and facade.stops==0,"drawer_close_keeps_nonremember_controls_and_player")
    check(panel._connect_catalog() and catalog.token=="fictional-nonremember-token" and vault.reads==0,"reopening_library_reuses_authorized_ram_without_saving_or_vault")
    panel._credential_state("ready","accepted again")
    panel._close()
    panel._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    app._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    check(facade.runtime.active and facade.stops==0 and app._library_credential(false)=="fictional-nonremember-token","focus_loss_preserves_player_and_authorized_ram")
    panel._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(not facade.runtime.active and app.sendspin_facade==null and app._library_credential(false)=="fictional-nonremember-token","real_pause_stops_player_but_ram_available_on_return")
    panel.endpoint_edit.text="https://other-fictional-ma.invalid"
    check(app._library_credential(false).empty() and app._library_session_token.empty(),"ram_token_never_reaches_changed_origin")
    panel.endpoint_edit.text="https://fictional-ma.invalid"
    panel.token_edit.text="fictional-current-session-token";panel._connect_catalog();panel._credential_state("ready","accepted")
    app._play_offline_music()
    panel._disconnect_library("forget")
    var reads=vault.reads
    check(app._library_credential().empty() and app._library_session_token.empty() and vault.reads==reads and app.offline_music.is_playing(),"forget_blocks_fallback_and_preserves_separate_offline_audio")
    app.offline_music.stop()
    panel.token_edit.text="fictional-auth-rejected-token";panel._connect_catalog();panel._credential_state("ready","accepted")
    facade=Facade.new();app.sendspin_facade=facade;panel.sendspin_paired=true
    var operation=Operation.new();app.add_child(operation);app.tv_queue_request=operation
    app.tv_queue_pending_session=facade
    app._on_tv_queue_result(false,"read",{},"fixed internal auth error",operation)
    check(panel.library_disconnected and app._library_session_token.empty() and app.sendspin_facade==null and facade.stops==1 and app.tv_queue_pending_session==null,"queue_auth_rejection_wipes_session_before_retry")
    var sink=load("res://scripts/SendspinPcmOutput.gd").new();get_root().add_child(sink)
    check(sink.start_after_verified_session(19),"real_sink_starts_paused_for_prefill")
    sink._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    check(sink.active and sink.stream_generation==19,"focus_loss_preserves_real_pcm_sink_generation")
    sink._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(not sink.active and sink.stream_generation==-1,"actual_pause_stops_real_pcm_sink")
    sink.queue_free()
    app._play_offline_music()
    yield(create_timer(.05),"timeout")
    app.offline_music._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    check(app.offline_music.is_playing(),"focus_loss_preserves_real_offline_player")
    app.offline_music._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(not app.offline_music.is_playing(),"actual_pause_stops_real_offline_player")
    panel.catalog=original;catalog.queue_free()
    app._clear_library_session();app.queue_free()
    print("EPHEMERAL_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
