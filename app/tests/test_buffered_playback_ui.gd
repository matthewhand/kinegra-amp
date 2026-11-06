extends SceneTree
class Runtime:
    extends Reference
    var active=true
    var buffering=true
    var occupancy=750.0
    func queued_audio_snapshot():return {"generation":2,"queued_ms":occupancy,"measured_ms":OS.get_ticks_msec()}
class Client:
    extends Reference
    func status():return {"paired":true,"client_id":"synthetic-client"}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    func stop():runtime.active=false
var failures=[]
func ck(v,label):
    if not v:
        failures.append(label)
        print("BUFFER_UI_FAIL_",label)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.set_process(false);var ui=app.music_ui;ui.set_process(false)
    var facade=Facade.new();app.sendspin_facade=facade
    ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    ck(ui._sendspin_is_buffering(),"startup detail from actual runtime")
    var metadata={"timeline":true,"position":30.0,"duration":120.0,"state":"paused"}
    ui.playback_progress.value=25
    ui._update_buffer_progress(metadata)
    ck(ui.buffer_label.visible and ui.buffer_label.text=="Buffered ~0.8s" and abs(ui.buffered_progress.value-25.625)<.001,"paused actual local buffer")
    ck(ui.buffered_progress.get_parent()==ui.playback_progress.get_parent() and ui.buffered_progress.get_index()<ui.playback_progress.get_index(),"buffer behind played fill")
    for size in [Vector2(960,720),Vector2(1280,720),Vector2(1680,720),Vector2(720,1280)]:
        OS.window_size=size;app._apply_resolution_base();ui._sync_transport();ui._update_buffer_progress(metadata)
        yield(create_timer(.2),"timeout")
        ck(ui.root.get_global_rect().encloses(ui.buffer_label.get_global_rect()),"buffer label within %s"%size)
        if ui.progress_stack.visible:ck(ui.root.get_global_rect().encloses(ui.progress_stack.get_global_rect()),"stack within %s"%size)
    ui._update_buffer_progress({"timeline":false,"state":"playing"})
    ck(ui.buffer_label.visible and ui.buffered_progress.value==0,"radio neutral actual seconds no percent")
    facade.runtime.occupancy=0;ui._update_buffer_progress(metadata)
    ck(not ui.buffer_label.visible and ui.buffered_progress.value==0,"empty buffer clears")
    facade.runtime.occupancy=750;ui._update_buffer_progress(metadata);ui.invalidate_tv_queue()
    ck(not ui.buffer_label.visible and ui.buffered_progress.value==0,"disconnect immediately clears")
    app.sendspin_facade=null;ui._update_buffer_progress(metadata)
    ck(not ui.buffer_label.visible,"replaced session no old cache")
    app.queue_free()
    print("BUFFER_UI_FAILURES=",failures)
    quit(0 if failures.empty() else 1)
