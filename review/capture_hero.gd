extends SceneTree
# Publication fixture: generated local samples, no account, webcam or MA server.
var app
func _init(): call_deferred("run")
func run():
    OS.window_size=Vector2(1280,720)
    app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    app._set_web_remote(false)
    app.pose_visual.set_mode("off")
    app.preset_index=1
    app._apply_resolution_base()
    app.visual_governor.set_mode("full",OS.get_ticks_msec())
    app._apply_visual_budget(app.visual_governor.snapshot())
    app.backing_dancers.pressed=true
    app._set_backing_dancers(true)
    app.music_ui.set_playback_context("offline")
    app.offline_music.select_track(0)
    app._play_offline_music()
    yield(create_timer(2.5),"timeout")
    var ui=app.music_ui
    ui._queue_add(1)
    ui._queue_add(2)
    ui._queue_add(3)
    var folder=OS.get_environment("KINEGRA_AMP_HERO_FRAMES")
    if folder.empty():
        printerr("Missing capture output directory")
        quit(1)
        return
    for frame in range(96):
        if frame==24: ui._open_queue()
        if frame==48:
            ui._close_queue()
            ui._enter_fullscreen()
        if frame==72:
            app.set_visuals_enabled(false)
            ui._set_cover_morph(1.0)
        yield(create_timer(1.0/6.0),"timeout")
        yield(self,"idle_frame")
        var pixels=get_root().get_texture().get_data()
        pixels.flip_y()
        if pixels.save_png(folder+"/frame-%03d.png"%frame)!=OK:
            printerr("Cannot save capture frame")
            quit(1)
            return
    app._stop_all_music()
    app.queue_free()
    print("KINEGRA_AMP_SYNTHETIC_HERO_FRAMES=96")
    quit()
