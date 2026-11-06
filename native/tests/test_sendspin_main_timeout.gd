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
        quit(1); return
    var warm=OS.get_ticks_msec()
    while facade.sink.last_pcm_at<0 or facade.sink.last_rms<.01:
        if OS.get_ticks_msec()-warm>8000:
            quit(1)
            return
        yield(create_timer(.02),"timeout")
    # Dispatch network messages without polling/acknowledging the output sink.
    # Once the ordered boundary begins, stall Main beyond its safety deadline.
    facade.runtime.set_process(false)
    var generation=plugin.status().generation
    var marker=File.new()
    if marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE)!=OK:
        quit(1)
        return
    marker.store_string("clear");marker.close()
    var start=OS.get_ticks_msec()
    while plugin.status().generation==generation:
        if OS.get_ticks_msec()-start>3000:
            quit(1)
            return
        plugin.tick()
        OS.delay_msec(1)
    OS.delay_msec(800)
    var failed=not facade.runtime.step() and not facade.runtime.active and facade.runtime.state=="error" and not facade.sink.active and not plugin.status().connected
    print("MAIN_CLEAR_TIMEOUT_FAILS_CLOSED=",failed)
    app._stop_all_music()
    yield(create_timer(.2),"timeout")
    # Reuse the adapter only after explicit session close; synthetic pairing stays valid.
    facade=load("res://scripts/SendspinExperienceFacade.gd").new()
    get_root().add_child(facade)
    var reopened=facade.begin_dependencies(true,OS.get_environment("SHIELDAMP_TEST_URL"),true,plugin,vault) and app.attach_sendspin_analysis(facade)
    start=OS.get_ticks_msec()
    var recovered=false
    while reopened and OS.get_ticks_msec()-start<8000:
        if facade.runtime.active and app.live_audio and facade.sink.last_rms>.025 and OS.get_ticks_msec()-facade.sink.last_pcm_at<500:
            recovered=true
            break
        yield(create_timer(.02),"timeout")
    print("MAIN_CLEAR_TIMEOUT_RECONNECT=",recovered)
    app._stop_all_music()
    facade.queue_free();app.queue_free()
    quit(0 if failed and recovered else 1)
