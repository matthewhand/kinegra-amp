extends SceneTree
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    var id="own-client"
    func status():return {"paired":true,"client_id":id}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    func stop():runtime.active=false
class TestMain:
    extends "res://scripts/Main.gd"
    var sent=[]
    func _sendspin_command(command,argument=null):
        sent.append([command,argument])
        return true
var failures=[]
func check(ok,label):
    print("QUEUE_EDIT_UI_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var app=TestMain.new();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.sendspin_facade=Facade.new();app.ma_panel.sendspin_paired=true;app.ma_panel.sendspin_player_id="own-client"
    app.ma_panel.endpoint_edit.text="https://ma.invalid";app.ma_panel.catalog.endpoint="https://ma.invalid";app.ma_panel.catalog.token="synthetic-credential"
    var ui=app.music_ui;ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    app.tv_queue_timing={"active":true,"state":"playing","current_id":"current","duration":120,"elapsed":20,"elapsed_updated":OS.get_unix_time()}
    app.tv_queue_timing_read_at=OS.get_ticks_msec();ui._sync_transport()
    check(ui.timeline_row.visible and ui.rewind_button.visible and not ui.rewind_button.disabled and not ui.playback_progress.visible,"server_seek_has_controls_without_fabricated_timeline")
    ui._seek_forward();check(app.sent==[["seek_forward",null]],"seek_is_explicit_bounded_action")
    app.tv_queue_timing.state="paused";ui._sync_transport();ui._seek_backward()
    check(not ui.timeline_row.visible and app.sent.size()==1,"paused_timing_cannot_trigger_playback")
    ui.queue_view="tv";ui.queue_drawer.show_modal(true)
    ui.show_tv_queue_items([{"name":"Synthetic upcoming","item_id":"opaque-future-id","index":2}],true,"")
    ui._queue_select_index(0);ui._queue_remove()
    check(app.sent.back()==["remove","opaque-future-id"],"remove_uses_item_identity_not_index")
    var before=app.sent.size();ui._queue_clear()
    check(ui.tv_clear_dialog.visible and app.sent.size()==before,"clear_requires_confirmation")
    ui.tv_clear_dialog.hide();ui._confirm_tv_queue_clear()
    check(app.sent.back()==["clear",null],"confirmed_clear_targets_current_session")
    ui._queue_clear();before=app.sent.size();app.sendspin_facade=Facade.new();ui._confirm_tv_queue_clear()
    check(app.sent.size()==before,"session_change_expires_clear_confirmation")
    ui._close_queue();app.queue_free();print("QUEUE_EDIT_UI_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
