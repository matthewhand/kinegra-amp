extends SceneTree
# Independent Root/Panel/UI boundary checks; synthetic credentials and no network.
class Sink:
    extends Reference
    signal pcm_observed(epoch,rms,playback,latency)
    signal analysis_invalidated
    var active=true
    var last_pcm_at=0
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    func status():return {"paired":true,"client_id":"synthetic-own-client"}
class Facade:
    extends Reference
    var sink=Sink.new()
    var runtime=Runtime.new()
    var client=Client.new()
    var stops=0
    func stop():
        stops+=1;sink.active=false;runtime.active=false
class Request:
    extends Node
    var action="read"
    var failure_reason=""
    var cancelled=false
    func cancel():cancelled=true
class LocalSource:
    extends Reference
    var active=true
    var stops=0
    func stop():
        stops+=1
        active=false
    func is_playing():return active
class Vault:
    extends Reference
    var loads=0
    var forgotten=0
    var writes=0
    var pairing="synthetic-pairing-preserved"
    func tokenEndpoint():return "https://one.invalid"
    func storageStatus():return "secure_no_legacy"
    func loadTokenForEndpoint(_endpoint):
        loads+=1
        return "synthetic-bound-owner-token"
    func storeTokenForEndpoint(_token,_endpoint):
        writes+=1
        return true
    func forgetToken():
        forgotten+=1
        return true
var failures=[]
func check(ok,label):
    print("MAIN_RAM_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func seed_session(app):
    var panel=app.ma_panel
    panel.endpoint_edit.text="https://one.invalid"
    panel.library_disconnected=false
    panel.catalog.endpoint="https://one.invalid";panel.catalog.token="synthetic-bound-owner-token"
    panel.pending_session_token="synthetic-bound-owner-token"
    panel.pending_session_origin="https://one.invalid"
    panel.pending_session_epoch=panel.catalog.epoch
    panel.remember_access.pressed=false
    panel._credential_state("ready","Synthetic authenticated server response")
    panel.sendspin_paired=true;panel.sendspin_player_id="synthetic-own-client"
    var facade=Facade.new();app.sendspin_facade=facade
    app.music_ui.set_playback_context("ma");app.music_ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    app.music_ui.artwork_controller.configure("https://one.invalid","synthetic-bound-owner-token",false,1)
    app.music_ui.artwork_controller._cache["synthetic"]=ImageTexture.new()
    var request=Request.new();app.add_child(request);app.tv_queue_request=request
    app.tv_queue_pending_session=facade
    app.tv_queue_timing={"synthetic":true};app.tv_queue_timing_read_at=OS.get_ticks_msec()
    return {"facade":facade,"request":request}
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.3),"timeout")
    app.set_process(false);app.music_ui.set_process(false)
    var real_local=app.local_pcm;var real_offline=app.offline_music
    var local=LocalSource.new();var offline=LocalSource.new();app.local_pcm=local;app.offline_music=offline
    var vault=Vault.new();app.ma_panel.credential_store_override=vault
    app.ma_panel.endpoint_edit.text="https://one.invalid";app.ma_panel.library_disconnected=false
    app.ma_panel.catalog.configure("https://one.invalid","synthetic-bound-owner-token",[],false)
    check(app._library_session_token.empty(),"configure_ready_alone_does_not_authorize_retained_ram")
    var session=seed_session(app);app.analysis_owner=session.facade.sink;app.live_audio=true
    check(app._library_session_token=="synthetic-bound-owner-token" and app._library_session_origin=="https://one.invalid" and vault.writes==0,"accepted_unremembered_access_is_origin_bound_ram_without_vault_write")
    app.ma_panel._close()
    check(app.sendspin_facade==session.facade and session.facade.runtime.active and session.facade.stops==0 and not session.request.cancelled,"closing_library_drawer_preserves_playback_and_pending_own_command")
    check(not app.music_ui.artwork_controller.is_configured() and app.music_ui.artwork_controller._cache.empty(),"drawer_close_discards_copied_art_credentials_and_cache")
    var reads_before=vault.loads
    check(app.ma_panel.catalog.token.empty() and app._library_credential(false)=="synthetic-bound-owner-token" and app._queue_controls_available() and vault.loads==reads_before,"closed_drawer_keeps_transport_authorized_from_ram_without_vault_read")
    app._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    app.ma_panel._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    check(app.sendspin_facade==session.facade and session.facade.stops==0 and app._library_session_token=="synthetic-bound-owner-token" and app._library_credential(false)=="synthetic-bound-owner-token","focus_loss_preserves_authorized_ram_and_own_player")
    check(local.active and offline.active and local.stops==0 and offline.stops==0,"focus_loss_does_not_stop_local_or_offline_sources")
    app._notification(MainLoop.NOTIFICATION_WM_FOCUS_IN)
    app._close_sendspin_analysis()
    for reason in ["disconnect","forget","server_change","trust_change","auth_failed"]:
        for owner in ["own","local","offline"]:
            session=seed_session(app)
            session.request.action="next"
            app.analysis_owner=session.facade.sink if owner=="own" else (local if owner=="local" else null)
            app.live_audio=owner!="offline"
            var previous_epoch=app.analysis_epoch
            if reason=="disconnect":app.ma_panel._disconnect_library()
            elif reason=="forget":app.ma_panel._confirm_forget_saved_access()
            elif reason=="server_change":
                app.ma_panel.endpoint_edit.text="https://two.invalid";app.ma_panel.endpoint_edit.emit_signal("text_changed",app.ma_panel.endpoint_edit.text)
            elif reason=="trust_change":app.ma_panel.lan_trust.emit_signal("toggled",false)
            else:app.ma_panel._credential_state("auth_expired","Synthetic access rejection")
            var label=reason+"_"+owner
            check(session.request.cancelled and app.tv_queue_request==null and app.tv_queue_pending_session==null and app.tv_queue_timing.empty() and app.sendspin_facade==null and session.facade.stops==1,label+"_clears_root_requests_and_only_own_sdk")
            check(app._library_session_token.empty() and app._library_session_origin.empty() and app.ma_panel.library_disconnected,label+"_wipes_retained_ram_and_blocks_reuse")
            check(not app.music_ui.artwork_controller.is_configured() and app.music_ui.artwork_controller._credential.empty() and app.music_ui.artwork_controller._cache.empty(),label+"_clears_artwork_session")
            check(local.active and offline.active and local.stops==0 and offline.stops==0,label+"_preserves_local_and_offline_sources")
            check((app.analysis_owner==null and not app.live_audio and app.analysis_epoch>previous_epoch) if owner=="own" else (app.analysis_owner==(local if owner=="local" else null) and app.analysis_epoch==previous_epoch and app.live_audio==(owner=="local")),label+"_resets_analysis_only_if_owned_by_sdk")
    session=seed_session(app);app.analysis_owner=session.facade.sink
    session.request.action="next";session.request.failure_reason="auth_failed"
    app._on_tv_queue_result(false,"next",{},"Synthetic server rejection",session.request)
    check(app._library_session_token.empty() and app.ma_panel.library_disconnected and app.sendspin_facade==null and app.tv_queue_request==null and app.tv_queue_pending_session==null,"structured_queue_auth_rejection_wipes_ram_before_pending_retry")
    # Whole-app pause retains access but keeps the existing stop-all-media
    # behavior. Source-preservation checks above cover credential revocation.
    session=seed_session(app);app.analysis_owner=session.facade.sink
    app._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    app.ma_panel._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(session.facade.stops==1 and app.sendspin_facade==null and app._library_session_token=="synthetic-bound-owner-token" and app._library_credential(false)=="synthetic-bound-owner-token" and not app.ma_panel.library_disconnected,"app_pause_stops_own_sdk_but_keeps_authorized_ram_for_explicit_return")
    app._notification(MainLoop.NOTIFICATION_APP_RESUMED)
    check(app.sendspin_facade==null and app._library_session_token=="synthetic-bound-owner-token","app_resume_does_not_autoplay_retained_session")
    session=seed_session(app);app.ma_panel.library_disconnected=true
    var reads=vault.loads
    check(not app._queue_controls_available() and not app._sendspin_command("play") and vault.loads==reads,"explicit_disconnect_blocks_main_commands_even_with_stale_copied_token")
    app.ma_panel.catalog.token=""
    check(not app._reconnect_tv() and vault.loads==reads and app.music_ui.ma_drawer.visible,"explicit_disconnect_reconnect_opens_library_without_vault_autoload")
    app.music_ui._sync_art_session()
    check(vault.loads==reads and not app.music_ui.artwork_controller.is_configured(),"disconnected_artwork_cannot_reuse_saved_access")
    check(vault.writes==0 and vault.pairing=="synthetic-pairing-preserved","credential_actions_preserve_pairing_record")
    app._close_sendspin_analysis();app.analysis_owner=null
    app.local_pcm=real_local;app.offline_music=real_offline
    app.queue_free();print("MAIN_RAM_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
