extends SceneTree
var failures=[]
func check(ok,label):
    print("TV_TRANSPORT_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    var capabilities={"paired":true,"can_play":true,"can_pause":true,"can_stop":true,"can_previous":false,"can_next":true}
    func status(): return capabilities
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    var commands=[]
    var accept=true
    func command(name):
        commands.append(name)
        return accept
    func stop(): runtime.active=false
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    var facade=Facade.new()
    app.sendspin_facade=facade
    var ui=app.music_ui
    ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    ui._sync_transport()
    check(ui.play_button.text=="PLAY" and ui.tv_pause_button.visible,"experimental_queue_controls_visible")
    check(ui.previous_button.disabled and ui.next_button.disabled and ui.tv_pause_button.disabled,"missing_credential_fails_closed")
    check(not ui.playback_progress.visible and ui.rewind_button.disabled and ui.forward_button.disabled,"no_fake_tv_seek")
    ui._toggle();ui._pause_tv();ui._next();ui._stop()
    check(facade.commands.empty(),"no_native_fallback_when_queue_unavailable")
    check(not app.offline_music.is_playing() and facade.runtime.active,"unavailable_queue_does_not_start_offline_or_disconnect")
    check(ui.status_label.text.begins_with("TV QUEUE UNAVAILABLE"),"unavailable_queue_is_reported")
    facade.client.capabilities={"paired":true}
    ui._sync_transport()
    check(ui.play_button.disabled and ui.tv_pause_button.disabled and ui.stop_button.disabled,"unknown_capabilities_fail_closed")
    ui._progress_elapsed=.2;ui._process(0.0)
    check(ui.clock_label.text=="WAITING","no_fabricated_elapsed_time")
    app.sendspin_facade=null
    ui._sync_transport()
    ui._toggle()
    check(ui.play_button.text=="RECONNECT" and not app.offline_music.is_playing(),"disconnected_tv_offers_reconnect_not_offline")
    ui.source_label.text="OFFLINE MUSIC  •  PRIVATE TRACKS"
    ui._sync_transport()
    check(ui.play_button.text=="PLAY" and ui.tv_pause_button.visible and ui.playback_progress.visible,"offline_controls_restored")
    app.queue_free()
    print("TV_TRANSPORT_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
