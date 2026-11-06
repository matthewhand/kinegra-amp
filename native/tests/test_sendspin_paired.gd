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
class Sink:
    extends "res://SendspinPcmOutput.gd"
    var nonzero_frames=0
    var replacement_frames=0
    var first_audio_generation=-1
    var stale_frames=0
    func push_validated_pcm(bytes,generation=-1):
        var ok=.push_validated_pcm(bytes,generation)
        if ok:
            for j in range(0,bytes.size()-3,4):
                if bytes[j]==244 and bytes[j+1]==1 and bytes[j+2]==12 and bytes[j+3]==254:
                    if first_audio_generation<0: first_audio_generation=generation
                    if generation>first_audio_generation: stale_frames+=1
                    nonzero_frames+=1
                if bytes[j]==232 and bytes[j+1]==3 and bytes[j+2]==24 and bytes[j+3]==252:
                    replacement_frames+=1
        return ok
func _init(): call_deferred("run")
func run():
    AudioServer.add_bus()
    var bus=AudioServer.get_bus_count()-1
    AudioServer.set_bus_name(bus,"Milkdrop")
    AudioServer.set_bus_mute(bus,true) # Synthetic PCM is never audible.
    var vault=Vault.new()
    vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var plugin=load("res://ShieldSendspin.gdns").new()
    var sink=Sink.new()
    get_root().add_child(sink)
    var runtime=load("res://SendspinPlaybackRuntime.gd").new()
    get_root().add_child(runtime)
    if not runtime.begin(plugin,sink,vault,OS.get_environment("SHIELDAMP_TEST_URL")):
        print("AUTH_TEST_OPEN_FAILED"); quit(1); return
    var paired=false
    var audio=false
    var feedback=false
    var cleared=false
    var initial_generation=-1
    for _i in range(600):
        if not runtime.active: break
        if plugin.status().paired: paired=true
        if sink.nonzero_frames>0: audio=true
        if sink.reported_frames>0: feedback=true
        if paired and audio and feedback and initial_generation<0:
            initial_generation=sink.stream_generation
            var marker=File.new()
            if marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE)!=OK:
                runtime.stop(); quit(1); return
            marker.store_string("ready")
            marker.close()
        if initial_generation>=0 and sink.stream_generation>initial_generation and sink.replacement_frames>0:
            cleared=true; break
        yield(create_timer(.025),"timeout")
    print("AUTHENTICATED_SYNTHETIC_PAIRED=",paired)
    print("ESTIMATED_MIXER_FEEDBACK=",feedback)
    print("AUTHENTICATED_SYNTHETIC_PCM=",audio)
    print("SYNTHETIC_CLEAR_AND_REPLACEMENT=",cleared)
    print("SYNTHETIC_STALE_AUDIO_FRAMES=",sink.stale_frames)
    if not runtime.active: print("RUNTIME_STOPPED=",runtime.state)
    runtime.stop()
    sink.queue_free(); runtime.queue_free()
    quit(0 if paired and audio and feedback and cleared and sink.stale_frames==0 else 1)
