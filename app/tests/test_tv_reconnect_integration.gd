extends SceneTree
class Runtime:
    extends Reference
    var active=true
    var current_pairing_code=""
class Client:
    extends Reference
    var paired=false
    func status(): return {"paired":paired,"client_id":"synthetic-client"}
class Sink:
    extends Node
    signal pcm_observed(epoch,rms,played,latency)
    signal analysis_invalidated
class Facade:
    extends Node
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=Sink.new()
    var stops=0
    func _init(): add_child(sink)
    func stop():
        stops+=1
        runtime.active=false
class TestMain:
    extends "res://scripts/Main.gd"
    var starts=0
    func _start_sendspin_player(_endpoint,_trusted):
        starts+=1
        sendspin_facade=Facade.new()
        add_child(sendspin_facade)
var failures=[]
func check(ok,label):
    print("TV_RECONNECT_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var app=TestMain.new();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.music_ui.set_playback_context("ma")
    app.ma_panel.library_disconnected=false
    app.ma_panel.sendspin_endpoint.text="ws://10.1.2.3:8927/sendspin"
    app.ma_panel.sendspin_trust.pressed=true
    app.music_ui._sync_transport()
    check(app.music_ui.play_button.text=="PLAY" and not app.music_ui.play_button.disabled,"disconnected_keeps_play_accessible")
    app._reconnect_tv()
    check(app.starts==1 and app.tv_reconnect_waiting and not app.tv_reconnect_timer.is_stopped(),"reconnect_starts_once_with_bounded_timer")
    check(not app.offline_music.is_playing(),"reconnect_never_starts_offline")
    app.music_ui._sync_transport()
    check(not app._reconnect_tv() and app.starts==1,"reconnect_rejects_duplicate_intent")
    if app.sendspin_facade==null:
        quit(1)
        return
    app.sendspin_facade.client.paired=true
    app._on_sendspin_state("paired","fixture",app.sendspin_facade)
    check(not app.tv_reconnect_waiting and app.tv_reconnect_timer.is_stopped(),"paired_cancels_timeout")
    app._stop_audio()
    app._reconnect_tv()
    check(app.starts==2 and app.tv_reconnect_waiting,"reconnect_can_be_retried")
    app._on_tv_reconnect_timeout()
    check(app.sendspin_facade==null and not app.offline_music.is_playing(),"timeout_is_recoverable_without_fallback")
    check(app.music_ui.status_label.text=="PLAYBACK CONNECTION TIMED OUT / RETRY","timeout_explains_retry")
    app.queue_free()
    yield(self,"idle_frame")
    print("TV_RECONNECT_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
