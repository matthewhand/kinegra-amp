extends SceneTree
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    func status():return {"paired":true,"client_id":"own-client"}
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
        sent.append([command,argument]);return true
var failures=[]
func check(ok,label):
    print("SEEK_POINTER_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func tap(button,touch=false):
    var at=button.get_global_rect().position+button.rect_size/2
    var physical=get_root().get_final_transform().xform(at)
    print("SEEK_POINTER_POINT=",at," physical=",physical)
    var move=InputEventMouseMotion.new();move.position=physical;move.global_position=physical;Input.parse_input_event(move)
    for down in [true,false]:
        if touch:
            var event=InputEventScreenTouch.new();event.index=0;event.pressed=down;event.position=physical
            Input.parse_input_event(event)
        else:
            var event=InputEventMouseButton.new();event.button_index=BUTTON_LEFT;event.pressed=down;event.position=physical;event.global_position=physical
            Input.parse_input_event(event)
func run():
    var app=TestMain.new();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.sendspin_facade=Facade.new();app.ma_panel.sendspin_paired=true;app.ma_panel.sendspin_player_id="own-client"
    app.ma_panel.endpoint_edit.text="https://ma.invalid";app.ma_panel.catalog.endpoint="https://ma.invalid";app.ma_panel.catalog.token="synthetic-credential"
    var ui=app.music_ui;ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    ui.show_tv_queue_snapshot({"current":"Synthetic current","next":"Synthetic next","current_id":"current","next_id":"next"})
    for size in [Vector2(3440,1440),Vector2(1720,720),Vector2(480,800)]:
        OS.window_size=size;app._apply_resolution_base();yield(create_timer(.3),"timeout")
        app.tv_queue_timing={"active":true,"state":"playing","current_id":"current","duration":120,"elapsed":20,"elapsed_updated":OS.get_unix_time()}
        app.tv_queue_timing_read_at=OS.get_ticks_msec();ui._sync_transport();yield(create_timer(.1),"timeout")
        print("SEEK_POINTER_SIZE=",size," root=",ui.root.get_global_rect())
        for pair in [[ui.tv_pause_button,"pause"],[ui.forward_button,"seek_forward"],[ui.rewind_button,"seek_backward"]]:
            var button=pair[0];var before=app.sent.size();var ancestor=button
            while ancestor!=null:
                if ancestor is Control:print("SEEK_POINTER_ANCESTOR=",ancestor.get_class()," rect=",ancestor.get_global_rect()," filter=",ancestor.mouse_filter," clip=",ancestor.rect_clip_content)
                ancestor=ancestor.get_parent()
            for touch in [false,true]:
                before=app.sent.size()
                tap(button,touch);yield(create_timer(.05),"timeout")
                var label=str(size)+"_"+pair[1]+("_touch" if touch else "_mouse")
                check(app.sent.size()==before+1 and app.sent.back()[0]==pair[1],label+"_delivered")
                check(ui.root.get_focus_owner()==button,label+"_focus")
    app.queue_free();print("SEEK_POINTER_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
