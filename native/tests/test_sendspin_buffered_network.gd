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
    AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.get_bus_count()-1,"Milkdrop")
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var vault=Vault.new();vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var plugin=load("res://ShieldSendspin.gdns").new()
    var sink=load("res://SendspinPcmOutput.gd").new();get_root().add_child(sink)
    var runtime=load("res://SendspinPlaybackRuntime.gd").new();get_root().add_child(runtime)
    print("BUFFERED_NETWORK_BEFORE_BEGIN")
    if not runtime.begin(plugin,sink,vault,OS.get_environment("SHIELDAMP_TEST_URL")):
        quit(1)
        return
    print("BUFFERED_NETWORK_STARTED")
    var start=OS.get_ticks_msec()
    var last_debug=start
    while sink.last_pcm_at<0 or sink.reported_frames<48000:
        if OS.get_ticks_msec()-start>10000 or not runtime.active:
            print("BUFFERED_NETWORK_START_FAILED")
            runtime.stop()
            quit(1)
            return
        if OS.get_ticks_msec()-last_debug>1000:
            last_debug=OS.get_ticks_msec()
            print("BUFFERED_NETWORK_WARM active=",sink.active," queued=",sink.mixer_feedback.queued," pcm=",sink.last_pcm_at," played=",sink.reported_frames)
        yield(create_timer(.02),"timeout")
    var before=sink.playback.get_skips()
    var stalls=0
    for i in range(240):
        if i%20==0:
            OS.delay_msec(60)
            stalls+=1
        yield(create_timer(.02),"timeout")
        if not runtime.active: break
    var skips=sink.playback.get_skips()-before if sink.playback!=null else -1
    print("BUFFERED_NETWORK_ACTIVE=",runtime.active)
    print("BUFFERED_NETWORK_60MS_STALLS=",stalls)
    print("BUFFERED_NETWORK_UNDERRUNS=",skips)
    print("BUFFERED_NETWORK_REPORTED_FRAMES=",sink.reported_frames)
    var ok=runtime.active and stalls==12 and skips==0 and sink.reported_frames>240000
    runtime.stop();sink.queue_free();runtime.queue_free();quit(0 if ok else 1)
