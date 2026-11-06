extends SceneTree
var failures=[]
var activated=0
func check(ok,label):
    print("CONTROLLER_UI_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func pressed():activated+=1
func button(slot,index,down):
    var event=InputEventJoypadButton.new();event.device=slot;event.button_index=index;event.pressed=down
    return event
func _init():call_deferred("run")
func run():
    AudioServer.set_bus_mute(0,true)
    var app=load("res://Main.tscn").instance();app.set_script(load("res://tests/FakePresentationMain.gd"));get_root().add_child(app)
    yield(create_timer(.3),"timeout")
    var ui=app.music_ui
    var target=Button.new();target.text="Synthetic controller target";target.rect_position=Vector2(300,200);target.rect_size=Vector2(240,60);target.focus_mode=Control.FOCUS_ALL
    ui.root.add_child(target);target.connect("pressed",self,"pressed");target.grab_focus()
    for slot in [0,1,5,15]:
        var count=activated
        Input.parse_input_event(button(slot,0,true))
        yield(self,"idle_frame")
        Input.parse_input_event(button(slot,0,true)) # Repeated down must not double-activate.
        yield(self,"idle_frame")
        Input.parse_input_event(button(slot,0,false))
        yield(self,"idle_frame")
        check(activated==count+1,"native_gui_accept_once_slot_"+str(slot))
    var count=activated
    var enter=InputEventKey.new();enter.scancode=KEY_ENTER;enter.pressed=true
    Input.parse_input_event(enter);yield(self,"idle_frame")
    enter=enter.duplicate();enter.echo=true
    Input.parse_input_event(enter);yield(self,"idle_frame")
    enter=enter.duplicate();enter.echo=false;enter.pressed=false
    Input.parse_input_event(enter);yield(self,"idle_frame")
    check(activated==count+1,"keyboard_echo_guard_unchanged")
    target.queue_free()
    # Exercise the configured library drawer, not its separate setup popup.
    app.ma_panel.endpoint_edit.text="https://ma.invalid"
    app.ma_panel.catalog.configure("https://ma.invalid","synthetic-library-token",[],false)
    app.ma_panel.library_disconnected=false
    app.ma_panel.setup_box.hide()
    ui._open_library();yield(create_timer(.1),"timeout")
    var previous=ui.root.get_focus_owner()
    check(ui.route_drawer_input(button(5,13,true)),"slot_five_dpad_routes_inside_library")
    var focus=ui.root.get_focus_owner()
    check(focus!=null and ui.ma_drawer.is_a_parent_of(focus) and focus!=previous,"slot_five_dpad_moves_modal_focus")
    check(ui.route_drawer_input(button(5,1,true)) and not ui.ma_drawer.visible,"slot_five_cancel_closes_modal")
    ui.route_drawer_input(button(5,1,false))
    ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    app.fixture_fresh=false
    ui._enter_fullscreen()
    var commands=app.fixture_commands.size()
    check(ui.route_drawer_input(button(5,0,true)) and app.fixture_commands.size()==commands+1 and app.fixture_commands.back()=="play","slot_five_fullscreen_accept")
    commands=app.fixture_commands.size()
    check(not ui.route_drawer_input(button(5,0,false)) and app.fixture_commands.size()==commands,"release_never_runs_fullscreen_command")
    check(ui.route_drawer_input(button(5,1,true)) and not ui.fullscreen_visual and ui.fullscreen_button.has_focus(),"slot_five_fullscreen_back_restores_focus")
    print("CONTROLLER_UI_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
