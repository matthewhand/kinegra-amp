extends SceneTree
class Vault:
    extends Reference
    var blob=PoolByteArray()
    func loadSendspinSnapshot(): return blob
    func sendspinSnapshotStatus(): return "secure"
    func replaceSendspinSnapshot(value):
        blob=value
        return true
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var vault=Vault.new();vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var facade=load("res://scripts/SendspinExperienceFacade.gd").new();get_root().add_child(facade)
    if not facade.begin_dependencies(true,OS.get_environment("SHIELDAMP_TEST_URL"),true,load("res://ShieldSendspin.gdns").new(),vault) or not app.attach_sendspin_analysis(facade):
        print("FAULT_OPEN_FAILED");quit(1);return
    facade.runtime.connect("state_changed",app,"_on_sendspin_state",[facade])
    app.music_ui.source_label.text="MUSIC ASSISTANT  •  TV PLAYER"
    var had_audio=false
    for _i in range(500):
        if app._sendspin_fresh():
            had_audio=true
            break
        yield(create_timer(.025),"timeout")
    if not had_audio:
        print("FAULT_NO_INITIAL_AUDIO")
        quit(1)
        return
    var f=File.new()
    if f.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE)!=OK:
        quit(1)
        return
    f.store_string("drop");f.close()
    var no_audio=false
    for _i in range(240):
        if not app._sendspin_fresh():
            no_audio=true
            break
        yield(create_timer(.025),"timeout")
    yield(create_timer(1.0),"timeout")
    app.music_ui._sync_transport()
    var no_fallback=not app.offline_music.is_playing()
    var reconnect_visible=app.music_ui.play_button.text=="RECONNECT"
    print("FAULT_INITIAL_AUDIO=",had_audio)
    print("FAULT_STREAM_STALE=",no_audio and not app._sendspin_fresh())
    print("FAULT_NO_OFFLINE_AUTOPLAY=",no_fallback)
    print("FAULT_RECONNECT_VISIBLE=",reconnect_visible)
    print("FAULT_RUNTIME_STATE=",facade.runtime.state if facade.runtime!=null else "closed")
    app._stop_all_music();facade.queue_free();app.queue_free()
    quit(0 if had_audio and no_audio and no_fallback and reconnect_visible else 1)
