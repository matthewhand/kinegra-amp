extends SceneTree
var checks=0
var failures=[]
func check(ok,name):
    checks+=1
    if not ok:
        failures.append(name)
        printerr("FAIL ",name)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    app.set_visuals_enabled(false)
    yield(create_timer(.1),"timeout")
    check(app.web_remote.profile=="development" and app.web_remote.server.is_listening(),"editor runtime starts development remote")
    check(app.web_remote_toggle.pressed and not app.web_remote_new_key.disabled,"settings reflects active listener")
    app._set_web_remote(false)
    check(not app.web_remote.server.is_listening() and not app.web_remote_toggle.pressed and app.web_remote_new_key.disabled,"off closes listener and updates settings")
    app._set_web_remote(true)
    var old=app.web_remote.key
    app._rotate_web_remote_key()
    check(app.web_remote.key!=old and app.web_remote_status.text.find(app.web_remote.key)>=0,"settings displays current access key")
    var diagnostic=app.web_remote_diagnostics()
    check(diagnostic.connection=="idle" and not diagnostic.sink_active and not diagnostic.runtime_active,"stopped diagnostics safely report no audio without secrets")
    app.web_require_key.pressed=false
    app.web_trusted_ranges.text="127.0.0.1/32"
    app._apply_web_access()
    check(not app.web_remote.require_key and not app.web_require_key.pressed,"TV settings apply no-key policy")
    app.web_require_key.pressed=true
    app._apply_web_access()
    var unavailable=app.web_remote.music_api.route("POST","/api/library",{"kind":"albums"})
    check(unavailable.code==409 and unavailable.body.has("error"),"unconfigured library returns a visible actionable error")
    app.web_remote.music_api.active={"kind":"add"}
    check(app._web_queue_busy() and not app._queue_controls_available(),"web mutation blocks overlapping TV transport")
    app.web_remote.music_api.active.clear()
    app.music_ui.set_playback_context("offline")
    var snapshot=app.web_remote_snapshot()
    check(snapshot.keys().size()==4 and snapshot.source=="Offline library","remote snapshot exposes only display metadata")
    check(not app.web_remote_control("delete") and not app.offline_music.is_playing(),"unknown action cannot start playback")
    app.offline_music.select_track(0)
    check(app.web_remote_control("play"),"Play uses selected offline source")
    yield(create_timer(.15),"timeout")
    check(app.offline_music.is_playing(),"remote starts generated fixture track")
    app.web_remote_control("pause")
    check(not app.offline_music.is_playing(),"Pause uses offline pause path")
    app.web_remote_control("play")
    yield(create_timer(.1),"timeout")
    check(app.offline_music.is_playing(),"Play resumes paused local audio")
    var index=app.offline_music.track_index
    app.web_remote_control("next")
    check(app.offline_music.track_index!=index,"Next routes to existing local queue")
    app.web_remote_control("previous")
    check(app.offline_music.track_index==index,"Previous uses existing local transport")
    app.web_remote_control("stop")
    check(not app.offline_music.is_playing(),"Stop ends local playback")
    app._set_web_remote(false)
    app.queue_free()
    yield(self,"idle_frame")
    print("WEB_REMOTE_MAIN_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
