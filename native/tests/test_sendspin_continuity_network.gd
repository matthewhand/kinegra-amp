extends SceneTree
class Vault:
    extends Reference
    var blob=PoolByteArray()
    func loadSendspinSnapshot(): return blob
    func sendspinSnapshotStatus(): return "secure"
    func replaceSendspinSnapshot(value):
        blob=value
        return true
# A positive ramp (opposite in each stereo channel) makes inserted zero runs,
# frame jumps and channel corruption distinguishable from ordinary SDK soft sync.
# Ignore the first second of startup clock/stream acquisition; this is not an
# audible-output or DAC measurement.
class Sink:
    extends "res://SendspinPcmOutput.gd"
    var prev=-1
    var start=-1
    var frames=0
    var zeros=0
    var discontinuities=0
    var max_step=0
    var channel_errors=0
    var zero_runs=0
    var zero_run=0
    var max_zero_run=0
    var first_zero_ms=-1
    var last_zero_ms=-1
    func push_validated_pcm(bytes,generation=-1):
        var ok=.push_validated_pcm(bytes,generation)
        if not ok:return false
        for j in range(0,bytes.size()-3,4):
            var left=_signed16(bytes,j)
            var right=_signed16(bytes,j+2)
            if start<0 and left>0:start=OS.get_ticks_msec()
            if start<0:continue
            if OS.get_ticks_msec()-start<1000:
                prev=left
                continue
            frames+=1
            if left==0:
                zeros+=1
                if zero_run==0:zero_runs+=1
                zero_run+=1
                max_zero_run=max(max_zero_run,zero_run)
                if first_zero_ms<0:first_zero_ms=OS.get_ticks_msec()-start
                last_zero_ms=OS.get_ticks_msec()-start
            elif prev>0:
                zero_run=0
                var delta=(left-prev+30000)%30000
                max_step=max(max_step,delta)
                if delta>4:discontinuities+=1
            if abs(left+right)>1:channel_errors+=1
            prev=left
        return true
func _init():call_deferred("run")
func run():
    Engine.target_fps=50
    var layout=AudioServer.generate_bus_layout()
    var bus=AudioServer.get_bus_count()
    layout.set("bus/%d/name" % bus,"Milkdrop")
    layout.set("bus/%d/send" % bus,"Master")
    AudioServer.set_bus_layout(layout)
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var vault=Vault.new();vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var plugin=load("res://ShieldSendspin.gdns").new()
    var sink=Sink.new();get_root().add_child(sink)
    var runtime=load("res://SendspinPlaybackRuntime.gd").new();get_root().add_child(runtime)
    if not runtime.begin(plugin,sink,vault,OS.get_environment("SHIELDAMP_TEST_URL")):
        quit(1)
        return
    var duration=int(OS.get_environment("SHIELDAMP_CONTINUITY_SECONDS")) if not OS.get_environment("SHIELDAMP_CONTINUITY_SECONDS").empty() else 8
    if duration<8 or duration>120:
        runtime.stop();quit(1)
        return
    yield(create_timer(float(duration)),"timeout")
    print("CONTINUITY_ACTIVE=",runtime.active)
    print("CONTINUITY_FRAMES=",sink.frames)
    print("CONTINUITY_ZERO_FRAMES=",sink.zeros)
    print("CONTINUITY_LARGE_STEPS=",sink.discontinuities)
    print("CONTINUITY_MAX_STEP=",sink.max_step)
    print("CONTINUITY_CHANNEL_ERRORS=",sink.channel_errors)
    print("CONTINUITY_UNDERRUNS=",sink.underruns)
    print("CONTINUITY_ZERO_RUNS=",sink.zero_runs)
    print("CONTINUITY_MAX_ZERO_RUN=",sink.max_zero_run)
    print("CONTINUITY_FIRST_ZERO_MS=",sink.first_zero_ms)
    print("CONTINUITY_LAST_ZERO_MS=",sink.last_zero_ms)
    print("CONTINUITY_OUTPUT_LATENCY_US=",sink.cached_output_latency_us)
    var ok=runtime.active and sink.frames>200000 and sink.zeros==0 and sink.discontinuities==0 and sink.channel_errors==0 and sink.underruns==0
    runtime.stop();quit(0 if ok else 1)
