extends SceneTree
var failures=[]
var background_presses=0
func background_pressed():background_presses+=1
func ck(ok,label):
    print(("PASS " if ok else "FAIL ")+label)
    if not ok:failures.append(label)
func direction(app,action):
    var event=InputEventAction.new()
    event.action=action
    event.pressed=true
    app._input(event)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.3),"timeout")
    var ui=app.music_ui
    ui._open_library()
    yield(create_timer(.1),"timeout")
    ck(ui.ma_drawer.is_set_as_toplevel(),"Library is an actual top-level modal")
    ui.library_button.connect("pressed",self,"background_pressed")
    for pressed in [true,false]:
        var click=InputEventMouseButton.new()
        click.position=ui.library_button.get_global_rect().get_center()
        click.button_index=BUTTON_LEFT
        click.pressed=pressed
        Input.parse_input_event(click)
        yield(create_timer(.02),"timeout")
    ck(background_presses==0,"Pointer cannot click controls behind the drawer")
    var panel=app.ma_panel
    panel.list.add_item("Fictional test track")
    panel.list.select(0)
    panel.play_button.disabled=false
    panel.list.grab_focus()
    direction(app,"ui_right")
    ck(panel.play_button.has_focus(),"Right from library list reaches Play inside the drawer")
    ck(not app.offline_music.is_playing(),"Moving focus does not start music")
    for action in ["ui_left","ui_up","ui_right","ui_down"]:
        for i in range(12):
            direction(app,action)
            var focus=ui.root.get_focus_owner()
            ck(focus!=null and ui.ma_drawer.is_a_parent_of(focus),"Library focus stays inside: "+action+str(i))
    ui.library_button.grab_focus()
    ck(ui.ma_drawer.is_a_parent_of(ui.root.get_focus_owner()),"Background cannot take focus while library is open")
    panel._close()
    ck(not ui.ma_drawer.visible and ui.library_button.has_focus(),"Close restores library opener")
    ui._open_offline_collection()
    yield(create_timer(.1),"timeout")
    ui._cue_offline_0()
    ck(ui.offline_play_button.has_focus(),"Choosing an offline track highlights Play selected")
    ck(not app.offline_music.is_playing(),"Choosing an offline track stays silent")
    for action in ["ui_left","ui_right","ui_up","ui_down"]:
        for i in range(8):
            direction(app,action)
            ck(ui.offline_drawer.is_a_parent_of(ui.root.get_focus_owner()),"Offline drawer traps "+action+str(i))
    ui._close_offline_collection()
    ck(ui.offline_button.has_focus(),"Offline close restores its opener")
    for size in [Vector2(960,1280),Vector2(1280,720)]:
        set_screen_stretch(SceneTree.STRETCH_MODE_DISABLED,SceneTree.STRETCH_ASPECT_IGNORE,Vector2.ZERO)
        OS.window_size=size
        get_root().size=size
        yield(create_timer(.2),"timeout")
        ui._apply_compact_layout()
        yield(create_timer(.2),"timeout")
        for control in [ui.library_button,ui.offline_button,ui.queue_button,ui.settings_button,ui.play_button,ui.avatar_button,ui.forward_button]:
            var box=control.get_global_rect()
            ck(box.position.x>=0 and box.end.x<=size.x+1 and box.position.y>=0 and box.end.y<=size.y+1,"Stage control fits "+str(size)+": "+control.text+" "+str(box))
    app._stop_all_music()
    print("MODAL_FOCUS_FAILURES=",failures.size())
    quit(0 if failures.empty() else 41)
