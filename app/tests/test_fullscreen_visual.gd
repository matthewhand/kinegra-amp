extends SceneTree
var failures=[]
func check(ok,label):
    print("FULLSCREEN_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(0.4),"timeout")
    var ui=app.music_ui
    ui._enter_fullscreen()
    check(ui.fullscreen_visual and not ui.header_card.visible and not ui.player_card.visible and app.pose_visual.fullscreen_visual,"immersive_mode")
    check(ui.fullscreen_help.visible,"entry_help")
    check(ui.fullscreen_track.visible and ui.fullscreen_track_title.text != "" and ui.fullscreen_track_artist.text.find("Review artist") >= 0,"fullscreen_track_and_credit")
    check(ui.fullscreen_art.texture != null and ui.fullscreen_album.text=="ALBUM: Not provided","fullscreen_art_and_honest_album")
    ui.show_ma_selection("Example track", "Example artist", "Example album")
    check(ui.fullscreen_track_title.text=="Example track" and ui.fullscreen_track_artist.text.find("Example artist")>=0 and ui.fullscreen_album.text=="ALBUM: Example album" and ui.fullscreen_art.texture==load("res://assets/branding/icon_192.png") and ui.fullscreen_art_caption.text=="BRAND ART","fullscreen_metadata_updates")
    ui.fullscreen_help.hide()
    var key=InputEventKey.new()
    key.scancode=KEY_RIGHT
    key.pressed=true
    app._input(key)
    check(ui.fullscreen_help.visible,"key_reveals_help")
    ui.fullscreen_help.hide()
    var stick=InputEventJoypadMotion.new()
    stick.axis=0
    stick.axis_value=0.2
    app._input(stick)
    check(not ui.fullscreen_help.visible,"stick_deadzone_ignored")
    stick.axis_value=0.8
    app._input(stick)
    check(ui.fullscreen_help.visible,"stick_reveals_help")
    ui.fullscreen_help_until=0
    ui._process(0.1)
    check(not ui.fullscreen_help.visible,"help_expires")
    var event=InputEventJoypadButton.new()
    event.button_index=1
    event.pressed=true
    app._input(event)
    check(not ui.fullscreen_visual and ui.header_card.visible and ui.player_card.visible,"controller_b_restores_controls")
    check(ui.fullscreen_button.has_focus(),"focus_restored")
    ui._enter_fullscreen()
    app._handle_tv_back()
    check(not ui.fullscreen_visual,"android_back_returns")
    print("FULLSCREEN_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
