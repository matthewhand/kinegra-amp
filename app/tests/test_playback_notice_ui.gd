extends SceneTree
var failures=[]
var checks=0
func ck(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.1),"timeout")
    app.set_process(false)
    app.visuals_enabled=true
    app.visual_quality_level=2
    app.reduced_motion.pressed=false
    app.backing_dancers.pressed=false
    var ui=app.music_ui
    ui.set_process(false)
    ui.set_playback_context("offline")
    ui._set_fullscreen_track("Synthetic dawn","Fictional artist","MUSIC ASSISTANT / PLAYING HERE")
    ui._enter_fullscreen()
    ui._process(.05)
    ck(ui.fullscreen_track.modulate.a<.03,"real fullscreen card fades in")
    for _i in range(39):
        ui._process(.05)
        ui._set_fullscreen_track("Synthetic dawn","Fictional artist","MUSIC ASSISTANT / PLAYING HERE")
    ck(ui.fullscreen_track.modulate.a>.9,"real notice becomes readable")
    var path=OS.get_environment("SHIELDAMP_NOTICE_PROOF")
    if not path.empty():
        yield(self,"idle_frame")
        var image=get_root().get_texture().get_data()
        image.flip_y()
        image.save_png(path)
    for _i in range(190):ui._process(.05)
    ck(ui.fullscreen_track.modulate.a<.01,"identical metadata refresh does not keep the card popping up")
    ui._show_fullscreen_help()
    for _i in range(40):ui._process(.05)
    ck(ui.fullscreen_track.modulate.a>.9,"user interaction gently reveals metadata again")
    app.visual_quality_level=0
    ui.sync_static_art()
    for _i in range(250):ui._process(.05)
    ck(ui.fullscreen_track.modulate.a==1.0,"artwork remains visible with visuals off")
    ui._exit_fullscreen()
    ck(ui.status_label.modulate.a==1.0,"ordinary status and errors do not fade")
    app._set_web_remote(false)
    app.queue_free()
    yield(self,"idle_frame")
    print("PLAYBACK_NOTICE_UI_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
