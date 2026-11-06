extends SceneTree
class Vault:
    extends Reference
    var blob=PoolByteArray()
    var status="secure"
    func loadSendspinSnapshot(): return blob
    func sendspinSnapshotStatus(): return status
    func replaceSendspinSnapshot(value):
        blob=value
        return true
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var vault=Vault.new()
    vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var plugin=load("res://ShieldSendspin.gdns").new()
    var facade=load("res://scripts/SendspinExperienceFacade.gd").new()
    get_root().add_child(facade)
    if not facade.begin_dependencies(true,OS.get_environment("SHIELDAMP_TEST_URL"),true,plugin,vault) or not app.attach_sendspin_analysis(facade):
        print("MAIN_AUTH_OPEN_FAILED"); quit(1); return
    app.music_ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    var bus=AudioServer.get_bus_index("Milkdrop")
    var quiet_route=bus>=0 and is_equal_approx(AudioServer.get_bus_volume_db(bus),0.0) and facade.sink.audio.bus=="Milkdrop" and is_equal_approx(facade.sink.audio.volume_db,0.0) and app.music_ui.volume_slider==null
    print("MAIN_AUTH_SHARED_SYSTEM_GAIN=",quiet_route)
    var capabilities_observed=false
    var live=false
    var spectrum=false
    var cleared=false
    var first_epoch=-1
    for _i in range(600):
        if facade.runtime==null or not facade.runtime.active: break
        var capabilities=app._sendspin_controls()
        if capabilities.has("can_play") and typeof(capabilities["can_play"])==TYPE_BOOL: capabilities_observed=true
        if app.analysis_frame.snapshot(OS.get_ticks_msec()).source=="live_pcm": live=true
        if app.fft.max()>0.00001: spectrum=true
        if live and spectrum and first_epoch<0:
            first_epoch=facade.sink.epoch
            var marker=File.new()
            if marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE)!=OK:
                facade.stop(); quit(1); return
            marker.store_string("ready")
            marker.close()
        if first_epoch>=0 and facade.sink.epoch>first_epoch and facade.sink.last_rms>.025 and app.live_audio:
            cleared=true; break
        yield(create_timer(.025),"timeout")
    print("MAIN_AUTH_CAPABILITIES=",capabilities_observed)
    print("MAIN_AUTH_LIVE=",live)
    print("MAIN_AUTH_SPECTRUM=",spectrum)
    print("MAIN_AUTH_CLEAR_REPLACEMENT=",cleared)
    app._stop_all_music()
    var stopped=not app.live_audio and facade.runtime==null
    print("MAIN_AUTH_STOPPED=",stopped)
    facade.queue_free(); app.queue_free()
    quit(0 if quiet_route and capabilities_observed and live and spectrum and cleared and stopped else 1)
