extends SceneTree
class Runtime:
    extends Reference
    var active=true
    var buffer_invalidations=0
    func invalidate_buffer_measurement(): buffer_invalidations+=1
class Client:
    extends Reference
    func status(): return {"paired":true,"client_id":"synthetic-client"}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    func stop(): runtime.active=false
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    # Origin/trust changes intentionally revoke an existing session. Complete
    # this synthetic library setup before installing the already-paired player.
    app.ma_panel.endpoint_edit.text=OS.get_environment("TVQ_URL")
    app.ma_panel.lan_trust.pressed=true
    if not app.ma_panel.catalog.configure(app.ma_panel.endpoint_edit.text,"synthetic-credential",[],true):
        print("MAIN_QUEUE_SYNTHETIC_SETUP_FAILED");quit(1);return
    app.ma_panel.library_disconnected=false # Fixture represents explicitly configured access.
    var facade=Facade.new();app.sendspin_facade=facade
    app.ma_panel.sendspin_paired=true
    app.ma_panel.sendspin_player_id="synthetic-client"
    app.music_ui.set_playback_context("ma")
    app.music_ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    app.music_ui._sync_transport()
    if app.music_ui.tv_pause_button.disabled:
        print("MAIN_QUEUE_CONTROL_DISABLED");quit(1);return
    var mode=OS.get_environment("TVQ_MODE")
    var preemption_ok=true
    if mode in ["main-preempt-read-pause","main-preempt-items-next"]:
        if mode=="main-preempt-items-next": app.music_ui._open_queue()
        else: app._request_tv_queue("read")
        yield(create_timer(.2),"timeout")
        var previous=app.tv_queue_request
        app.music_ui._sync_transport()
        preemption_ok=previous!=null and not app.music_ui.tv_pause_button.disabled
        var accepted=app._sendspin_command("next" if mode=="main-preempt-items-next" else "pause")
        preemption_ok=preemption_ok and accepted and app.tv_queue_request!=previous and not previous.active
        app.music_ui.now_title.text="Known title"
        app._on_tv_queue_result(true,"read",{"current":"Stale cancelled read","next":"Stale next","state":"playing"},"",previous)
        preemption_ok=preemption_ok and app.music_ui.now_title.text=="Known title"
    elif mode=="main-busy-mutation":
        app.music_ui._pause_tv()
        var previous=app.tv_queue_request
        preemption_ok=previous!=null and not app._sendspin_command("next") and app.tv_queue_request==previous and previous.active
    elif OS.get_environment("TVQ_MODE") in ["main-read","main-raw-read"]:
        if not app._request_tv_queue("read"):
            quit(1)
            return
    elif OS.get_environment("TVQ_MODE") in ["main-items","main-raw-items","main-busy-items","main-busy-close"]:
        if OS.get_environment("TVQ_MODE") in ["main-busy-items","main-busy-close"]:
            if not app._request_tv_queue("read"):
                quit(1)
                return
        app.music_ui._open_queue()
        if OS.get_environment("TVQ_MODE")=="main-busy-close": app.music_ui._close_queue()
    elif OS.get_environment("TVQ_MODE")=="main-play":
        app._on_library_credentials_authorized(app.ma_panel.catalog.token,app.ma_panel._credential_endpoint())
        app.ma_panel.catalog.close()
        app.music_ui._toggle()
        preemption_ok=app.music_ui.source_label.text=="MUSIC ASSISTANT  •  WAITING FOR AUDIO" and not app.tv_audio_wait_timer.is_stopped()

    else:
        app.music_ui._pause_tv()
    for _i in range(240):
        if app.tv_queue_request==null and app.tv_queue_pending_session==null: break
        yield(create_timer(.025),"timeout")
    var ok=app.tv_queue_request==null and preemption_ok
    if mode=="main-preempt-read-pause":
        ok=ok and app.music_ui.status_label.text.begins_with("QUEUE REQUEST ACCEPTED")
    elif mode=="main-preempt-items-next":
        ok=ok and app.music_ui.tv_queue_items.size()==2 and app.music_ui.queue_drawer.visible
    elif mode=="main-busy-mutation":
        ok=ok and app.music_ui.status_label.text.begins_with("QUEUE REQUEST ACCEPTED")
    elif OS.get_environment("TVQ_MODE") in ["main-read","main-raw-read"]:
        ok=ok and app.music_ui.now_title.text=="Synthetic Track" and app.music_ui.tv_queue_label.text=="NEXT: Synthetic Next"
    elif OS.get_environment("TVQ_MODE")=="main-busy-close":
        yield(create_timer(.2),"timeout")
        ok=ok and app.tv_queue_request==null and not app.music_ui.queue_drawer.visible and app.music_ui.tv_queue_items.empty()
    elif OS.get_environment("TVQ_MODE") in ["main-items","main-raw-items","main-busy-items"]:
        var original=app.offline_music.upcoming_queue.duplicate()
        app.music_ui._queue_clear()
        ok=ok and app.music_ui.queue_view=="tv" and app.music_ui.tv_queue_items.size()==2 and not app.music_ui.queue_clear_button.disabled and app.music_ui.queue_clear_button.visible and app.music_ui.tv_clear_dialog.visible and app.music_ui.queue_close_button.visible and app.music_ui.queue_button.text=="QUEUE" and app.offline_music.upcoming_queue==original
        app.music_ui.tv_clear_dialog.hide()
        ok=ok and not app.music_ui.queue_toggle_button.is_visible_in_tree() and app.music_ui.queue_view=="tv"
    elif mode=="main-play":
        ok=ok and app.tv_queue_last_action=="play" and app._tv_playback_status()=="waiting" and not app.offline_music.is_playing()
    elif OS.get_environment("TVQ_MODE")=="main-eof-command":
        ok=ok and app.music_ui.status_label.text=="PLAYBACK COMMAND RESULT UNKNOWN / CHECK QUEUE" and not app.offline_music.is_playing()
    else:
        ok=ok and app.music_ui.status_label.text.begins_with("QUEUE REQUEST ACCEPTED")
    if mode=="main-preempt-items-next":ok=ok and facade.runtime.buffer_invalidations==1
    elif mode in ["main-preempt-read-pause","main-pause","main-play"]:ok=ok and facade.runtime.buffer_invalidations==0
    print("MAIN_QUEUE_OK=",ok)
    if app.tv_queue_timer!=null: app.tv_queue_timer.stop()
    app.sendspin_facade=null;app.queue_free();quit(0 if ok else 1)
