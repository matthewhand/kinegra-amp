extends SceneTree
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    func status(): return {"paired":true,"client_id":"synthetic-client"}
class Sink:
    extends Node
    signal pcm_observed(epoch,rms,played,latency)
    signal analysis_invalidated
    var epoch=7
    var active=false
    var last_pcm_at=-1
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    var stopped=0
    func stop():
        stopped+=1
        runtime.active=false
var failures=[]
func check(ok,label):
    print("TV_RECOVERY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    var sink=Sink.new();get_root().add_child(sink)
    var facade=Facade.new();facade.sink=sink
    app.sendspin_facade=facade;app.analysis_owner=sink
    app.music_ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    app.tv_reconnect_waiting=true
    app.tv_reconnect_timer.start(20)
    app._on_sendspin_state("paired","fixture",facade)
    check(not app.tv_reconnect_waiting and app.tv_reconnect_timer.is_stopped() and not app.offline_music.is_playing(),"paired_reconnect_finishes_without_autoplay")
    app._start_sendspin_player("ws://10.1.2.3:8927/sendspin",true)
    check(app.sendspin_facade==facade and app.ma_panel.sendspin_paired and app.ma_panel.sendspin_player_id=="synthetic-client" and not app.offline_music.is_playing(),"repeated_connect_preserves_paired_session_without_autoplay")
    app.music_ui.queue_view="tv"
    app.music_ui.tv_queue_items=["Synthetic stale item"]
    app.music_ui.queue_drawer.show()
    app.music_ui._refresh_queue()
    app._on_sendspin_state("connecting","fixture",facade)
    check(app.music_ui.tv_queue_items.empty() and app.music_ui.queue_clear_button.disabled and app.music_ui.tv_queue_preview_status=="PLAYBACK DISCONNECTED / RECONNECT","disconnect_invalidates_read_only_preview")
    app._on_sendspin_state("paired","fixture",facade)
    check(app.music_ui.tv_queue_label.text=="TV CONNECTED / QUEUE INFO PENDING" and app.music_ui.tv_queue_preview_status=="TV CONNECTED / REFRESH QUEUE" and not app.tv_queue_timer.is_stopped(),"reconnect_clears_stale_queue_hint_and_schedules_read")
    app._watch_tv_audio()
    app._on_tv_audio_wait_timeout()
    check(app.music_ui.status_label.text=="NO AUDIO / CHOOSE PLAY TO RETRY" and not app.offline_music.is_playing(),"no_audio_reports_manual_retry")
    app._watch_tv_audio()
    app._on_pcm_observed(sink.epoch,0.1,0,0,sink)
    check(app.tv_audio_seen and app.tv_audio_wait_timer.is_stopped(),"current_pcm_cancels_audio_warning")
    app.tv_queue_last_action="pause";app.tv_queue_state="idle"
    check(app._tv_pause_waiting(),"idle_after_pause_is_not_reported_as_confirmed_paused")
    app.tv_reconnect_waiting=true
    app._on_tv_reconnect_timeout()
    check(app.sendspin_facade==null and facade.stopped==1 and not app.offline_music.is_playing(),"timeout_closes_session_without_fallback")
    check(app.music_ui.status_label.text=="PLAYBACK CONNECTION TIMED OUT / RETRY","timeout_is_visible")
    app._on_sendspin_state("paired","stale",facade)
    check(app.sendspin_facade==null and not app.tv_reconnect_waiting,"stale_session_cannot_reconnect")
    # Pause and focus notifications can arrive in either order. Polling stays
    # off until both resume and focus are restored, then the selected mode returns.
    app.pose_visual.set_mode("demo")
    app.notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    app.notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(not app.pose_visual.enabled and app.pose_suspended_mode=="demo","focus_loss_suspends_demo")
    app.notification(MainLoop.NOTIFICATION_WM_FOCUS_IN)
    check(not app.pose_visual.enabled,"focus_alone_does_not_resume_paused_app")
    app.notification(MainLoop.NOTIFICATION_APP_RESUMED)
    check(app.pose_visual.mode=="demo" and app.pose_visual.enabled and not app.offline_music.is_playing(),"resume_restores_demo_without_autoplay")
    app.pose_visual.set_mode("live")
    app.notification(MainLoop.NOTIFICATION_APP_PAUSED)
    app.notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    app.notification(MainLoop.NOTIFICATION_APP_RESUMED)
    check(not app.pose_visual.enabled,"resume_alone_does_not_restart_tracking_unfocused")
    app.notification(MainLoop.NOTIFICATION_WM_FOCUS_IN)
    check(app.pose_visual.mode=="live" and app.pose_visual.enabled,"focus_restores_selected_live_mode")
    app.pose_visual.set_mode("off")
    app.notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    app.notification(MainLoop.NOTIFICATION_WM_FOCUS_IN)
    check(app.pose_visual.mode=="off" and not app.pose_visual.enabled,"off_stays_off")
    var ui=app.music_ui
    ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    ui.show_tv_queue_snapshot({"current":"Old title","artist":"Old artist","album":"Old album","next":"Old next","state":"playing"})
    ui.show_tv_queue_snapshot({"current":"","artist":"Stale artist","album":"Stale album","next":"","state":"idle"})
    check(ui.now_title.text=="Queue is empty" and ui.fullscreen_track_title.text=="Queue is empty" and not "Old artist" in ui.fullscreen_track_artist.text and not "Stale artist" in ui.fullscreen_track_artist.text and ui.fullscreen_album.text=="ALBUM: Not provided","empty_queue_revokes_previous_title_and_credits")
    ui.show_tv_queue_snapshot({"current":"","next":"","state":"playing"})
    check(ui.now_title.text=="Waiting for track information","missing_playing_metadata_is_not_reported_as_empty_queue")
    sink.queue_free();app.queue_free();print("TV_RECOVERY_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
