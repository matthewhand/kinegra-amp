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
    var initial_generation=-1
    var stale_after_clear=0
    func push_validated_pcm(bytes,generation=-1):
        var ok=.push_validated_pcm(bytes,generation)
        if ok:
            for j in range(0,bytes.size()-3,4):
                if bytes[j]==244 and bytes[j+1]==1 and bytes[j+2]==12 and bytes[j+3]==254:
                    if initial_generation<0: initial_generation=generation
                    if generation>initial_generation: stale_after_clear+=1
        return ok
func _init(): call_deferred("run")
func run():
    Engine.target_fps=50
    AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.get_bus_count()-1,"Milkdrop")
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var vault=Vault.new();vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var plugin=load("res://ShieldSendspin.gdns").new()
    var sink=Sink.new();get_root().add_child(sink)
    var runtime=load("res://SendspinPlaybackRuntime.gd").new();get_root().add_child(runtime)
    if not runtime.begin(plugin,sink,vault,OS.get_environment("SHIELDAMP_TEST_URL")):
        quit(1)
        return
    var warm=OS.get_ticks_msec()
    while sink.last_pcm_at<0 or sink.reported_frames<48000:
        if OS.get_ticks_msec()-warm>10000 or not runtime.active:
            print("SUSTAINED_WARM_FAILED")
            runtime.stop();quit(1)
            return
        yield(create_timer(.02),"timeout")
    var duration_seconds=16
    if not OS.get_environment("SHIELDAMP_STRESS_SECONDS").empty(): duration_seconds=int(OS.get_environment("SHIELDAMP_STRESS_SECONDS"))
    if duration_seconds<16 or duration_seconds>120:
        runtime.stop();quit(1)
        return
    var start=OS.get_ticks_msec()
    var severe_at=-1
    var severe_frames=0
    var recovered=false
    var clear_generation=-1
    var cleared=false
    var short_stalls=0
    var next_short=800
    while OS.get_ticks_msec()-start<duration_seconds*1000 and runtime.active:
        var elapsed=OS.get_ticks_msec()-start
        if elapsed>=next_short and severe_at<0:
            OS.delay_msec(100)
            short_stalls+=1
            next_short+=800
        if elapsed>=4500 and severe_at<0:
            severe_frames=sink.reported_frames
            OS.delay_msec(1000)
            severe_at=OS.get_ticks_msec()
        if severe_at>=0 and not recovered and not sink.buffering and sink.reported_frames>severe_frames+4800 and sink.last_pcm_at>severe_at:
            recovered=true
        if elapsed>=10000 and clear_generation<0:
            clear_generation=sink.stream_generation
            var marker=File.new()
            if marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE)!=OK:
                runtime.stop();quit(1)
                return
            marker.store_string("clear");marker.close()
        if clear_generation>=0 and sink.stream_generation>clear_generation and sink.last_rms>.025:cleared=true
        yield(create_timer(.02),"timeout")
    var active=runtime.active
    print("SUSTAINED_ACTIVE=",active)
    print("SUSTAINED_100MS_STALLS=",short_stalls)
    print("SUSTAINED_FORCED_UNDERRUN=",sink.underruns>0 and sink.rebuffer_count>0)
    print("SUSTAINED_RECOVERED=",recovered)
    print("SUSTAINED_CLEAR_REPLACEMENT=",cleared)
    print("SUSTAINED_STALE_FRAMES=",sink.stale_after_clear)
    print("SUSTAINED_REBUFFERS=",sink.rebuffer_count)
    print("SUSTAINED_FINAL_GENERATION=",sink.stream_generation)
    print("SUSTAINED_CLEAR_BEFORE=",clear_generation)
    print("SUSTAINED_LAST_RMS=",sink.last_rms)
    print("SUSTAINED_LAST_PCM_AGE=",OS.get_ticks_msec()-sink.last_pcm_at)
    print("SUSTAINED_BUFFER_QUEUED=",sink.mixer_feedback.queued)
    print("SUSTAINED_BUFFERING=",sink.buffering)
    print("SUSTAINED_FINAL_PLAYED=",sink.reported_frames)
    var ok=active and short_stalls>=5 and sink.underruns>0 and recovered and cleared and sink.stale_after_clear==0
    runtime.stop();sink.queue_free();runtime.queue_free();quit(0 if ok else 1)
