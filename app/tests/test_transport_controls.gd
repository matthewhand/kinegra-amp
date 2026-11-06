extends SceneTree
var failures=[]
func check(ok,label):
    print("TRANSPORT_UI_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    var ui=app.music_ui
    check(ui.transport_grid.get_child(0)==ui.play_button and ui.play_button.text=="PLAY","play_first_simple_label")
    var icons=true
    for button in [ui.play_button,ui.previous_button,ui.tv_pause_button,ui.next_button,ui.stop_button]:
        icons=icons and button.icon!=null and button.icon.get_width()==28
    check(icons,"all_core_actions_have_icons")
    check(ui.tv_pause_button.visible and ui.tv_pause_button.disabled,"dedicated_pause_starts_inactive")
    ui._sync_transport();var ready=ui.play_button.get_stylebox("normal").bg_color
    ui._toggle();yield(create_timer(.2),"timeout");ui._sync_transport()
    check(app.offline_music.is_playing() and ui.play_button.text=="PLAY" and ui.play_button.get_stylebox("normal").bg_color!=ready,"playing_has_distinct_colour_and_stable_label")
    ui._toggle();check(app.offline_music.is_playing(),"play_is_idempotent_while_playing")
    ui._pause_tv();ui._sync_transport()
    check(not app.offline_music.is_playing() and ui.play_button.get_stylebox("normal").bg_color==ready,"pause_has_own_action_and_restores_ready_colour")
    ui._toggle();yield(create_timer(.1),"timeout")
    check(app.offline_music.is_playing(),"play_resumes_paused_local_audio")
    ui._stop();check(not app.offline_music.is_playing(),"stop_remains_independent")
    app.queue_free();print("TRANSPORT_UI_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
