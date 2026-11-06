extends SceneTree
var failures=[]
func check(ok,label):
    print("APP_VOLUME_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var path="user://synthetic_gain_"+str(OS.get_ticks_usec())+".cfg"
    var app=load("res://Main.tscn").instance();app.volume_path=path
    get_root().add_child(app);yield(create_timer(.2),"timeout")
    app.set_process(false)
    check(app.app_volume_percent==100 and not app.music_ui.volume_tag.visible,"default_100_has_no_badge")
    check(app.app_volume_slider!=null and not app.offline_music.is_playing(),"settings_control_without_autoplay")
    var master_gain=AudioServer.get_bus_volume_db(0)
    var master_mute=AudioServer.is_bus_mute(0)
    app.set_app_volume(50);app._flush_app_volume()
    check(app.volume_store.read(path).found and app.music_ui.volume_tag.visible,"reduced_gain_is_saved_and_visible")
    app._restore_app_volume()
    check(app.app_volume_percent==50 and abs(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Milkdrop"))+6.0206)<.01,"saved_gain_survives_restore")
    check(AudioServer.get_bus_volume_db(0)==master_gain and AudioServer.is_bus_mute(0)==master_mute,"master_bus_is_unchanged")
    check(not app.set_app_volume(NAN),"nonfinite_volume_rejected")
    app.set_app_volume(100);app._flush_app_volume()
    check(not app.music_ui.volume_tag.visible,"unity_hides_badge")
    app.queue_free();yield(self,"idle_frame");Directory.new().remove(path)
    print("APP_VOLUME_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
