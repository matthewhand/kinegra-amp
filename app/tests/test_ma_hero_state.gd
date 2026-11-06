extends SceneTree
var failures=[]
func check(value, message):
    if not value:
        failures.append(message)
        printerr("MA_HERO_FAIL ", message)
func _init():
    call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(0.2),"timeout")
    var ui=app.music_ui
    check(ui.source_label.text.begins_with("OFFLINE MUSIC"),"startup source identifies bundled track")
    check(ui.now_title.text==app.offline_music.current_title(),"startup title matches bundled selection")
    ui.show_ma_selection("Fixture track")
    ui._process(0.01)
    check(not ui.track_hero.playing and ui.track_hero.state_label.text.find("NO PLAYBACK")>=0,"catalog selection is silent")
    ui.source_label.text="MUSIC ASSISTANT  •  SHORT PREVIEW"
    app.native_transport.ma_preview_mode=true
    app.analysis_owner=app.native_stream_engine
    app.native_stream_engine.active=true
    app.native_stream_engine.last_pcm_at=OS.get_ticks_msec()
    ui._process(0.01)
    check(ui.track_hero.playing and ui.track_hero.state_label.text.find("SHORT PREVIEW")>=0,"fresh preview shows playback")
    check(ui.track_hero.source_label.text.find("SHORT PREVIEW")>=0,"source identifies preview")
    app.native_stream_engine.last_pcm_at=OS.get_ticks_msec()-501
    ui._process(0.01)
    check(not ui.track_hero.playing and ui.track_hero.state_label.text.find("WAITING")>=0,"stale audio is not shown as live")
    app.native_stream_engine.active=false
    app.native_transport.ma_preview_mode=false
    app.analysis_owner=null
    app.queue_free()
    print("MA_HERO_FAILURES=",failures)
    quit(0 if failures.empty() else 1)
