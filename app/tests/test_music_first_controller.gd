extends SceneTree
# Fictional offline Godot event tests. No ADB, no physical controller injection.
var checks=0
var failures=[]
func verify(value,label):
    checks+=1
    if not value:
        failures.append(label)
        printerr("FAIL ",label)
func send_button(ui,index,down):
    var e=InputEventJoypadButton.new()
    e.device=0
    e.button_index=index
    e.pressed=down
    ui._input(e)
    if down:
        var release=e.duplicate()
        release.pressed=false
        ui._input(release)
func _init():
    call_deferred("run")
func run():
    var ui=load("res://Main.tscn").instance()
    get_root().add_child(ui)
    yield(create_timer(0.20),"timeout")
    verify(ui.music_ui.visible and not ui.page_scroller.visible,"TV starts in music-first stage")
    verify(ui.music_ui.library_button.has_focus(),"focus on Music Assistant")
    ui.music_ui._advanced()
    verify(ui.page_scroller.visible and not ui.music_ui.visible,"advanced view opened")
    send_button(ui,1,false)
    verify(ui.page_scroller.visible,"gamepad B release cannot navigate")
    send_button(ui,1,true)
    verify(ui.music_ui.visible and not ui.page_scroller.visible,"gamepad B returns from advanced")
    ui.music_ui._open_library()
    verify(ui.ma_panel.is_visible_in_tree(),"MA drawer open")
    ui.ma_panel.token_edit.text="fictional-secret-not-sent"
    send_button(ui,11,true)
    yield(create_timer(.04),"timeout")
    verify(not ui.ma_panel.is_visible_in_tree() and ui.music_ui.ma_drawer.visible,"first Back closes setup popup and keeps library open")
    verify(ui.ma_panel.token_edit.text.empty(),"closing setup clears unsent token")
    var opener=ui.music_ui.root.get_focus_owner()
    verify(opener!=null and ui.music_ui.ma_drawer.is_a_parent_of(opener),"popup Back restores an opener inside library")
    send_button(ui,11,true)
    yield(create_timer(.04),"timeout")
    verify(not ui.music_ui.ma_drawer.visible,"second distinct Back closes library")
    verify(ui.music_ui.library_button.has_focus(),"outer close restores Music Assistant button")
    ui.music_ui._open_library()
    ui.ma_panel.token_edit.text="fictional-secret-not-sent"
    ui.music_ui._advanced()
    verify(ui.ma_panel.token_edit.text.empty(),"switching to settings clears unsubmitted token")
    verify(not ui.ma_panel.is_visible_in_tree(),"switching to settings closes catalog")
    ui.music_ui.show_stage()
    ui.music_ui._open_library()
    ui.ma_panel.token_edit.text="fictional-secret-not-sent"
    ui.music_ui._open_offline_collection()
    verify(ui.ma_panel.token_edit.text.empty(),"switching to offline library clears unsubmitted token")
    verify(ui.music_ui.offline_drawer.visible,"offline library opens after catalog closes")
    ui.music_ui._close_offline_collection()
    ui._play_offline_music()
    yield(create_timer(0.13),"timeout")
    verify(ui.offline_music.is_playing(),"real private music playing on explicit action")
    send_button(ui,1,true)
    verify(not ui.offline_music.is_playing(),"gamepad B stops local music")
    verify(ui.music_ui.visible,"stopping music keeps visualizer open")
    ui.music_ui._advanced()
    ui.ha_endpoint_edit.grab_focus()
    send_button(ui,1,true)
    verify(ui.page_scroller.visible,"B releases a focused editor before leaving settings")
    verify(not ui.ha_endpoint_edit.has_focus(),"editor focus released")
    send_button(ui,1,true)
    verify(ui.music_ui.visible,"second B returns to music screen")
    ui._stop_all_music()
    print("MUSIC_CONTROLLER_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
