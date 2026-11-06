extends SceneTree
class Vault:
    extends Reference
    var blob=PoolByteArray()
    func loadSendspinSnapshot():return blob
    func sendspinSnapshotStatus():return "secure"
    func replaceSendspinSnapshot(v):
        blob=v
        return true
# A synced SDK may adjust the initial ramp within one 20 ms chunk while its
# estimated output clock acquires. Reject loss of a whole chunk, not legal
# sub-chunk synchronization; this is not a bit-exact/DAC test.
class Sink:
    extends "res://SendspinPcmOutput.gd"
    var first_sample=0
    var first_at=-1
    var first_gen=-1
    var observed=0
    func push_validated_pcm(bytes,generation=-1):
        var ok=.push_validated_pcm(bytes,generation)
        if not ok:return false
        for i in range(0,bytes.size()-3,4):
            var left=_signed16(bytes,i)
            if left!=0:
                if generation!=first_gen:
                    first_gen=generation;first_sample=left;first_at=OS.get_ticks_msec()
                observed+=1
        return true
func _init():call_deferred("run")
func run():
    Engine.target_fps=50
    var bus=AudioServer.generate_bus_layout();var n=AudioServer.get_bus_count()
    bus.set("bus/%d/name"%n,"Milkdrop");bus.set("bus/%d/send"%n,"Master");AudioServer.set_bus_layout(bus)
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Milkdrop"),true)
    var vault=Vault.new();vault.blob=Marshalls.base64_to_raw(OS.get_environment("SHIELDAMP_SYNTHETIC_SNAPSHOT"))
    var plugin=load("res://ShieldSendspin.gdns").new()
    var sink=Sink.new();get_root().add_child(sink)
    var r=load("res://SendspinPlaybackRuntime.gd").new();get_root().add_child(r)
    var url=OS.get_environment("SHIELDAMP_TEST_URL")
    var okay=r.begin(plugin,sink,vault,url)
    var start=OS.get_ticks_msec();var waiting_seen=false;var maximum_remaining=0
    while sink.first_at<0 and OS.get_ticks_msec()-start<7000:
        waiting_seen=waiting_seen or r.buffering
        maximum_remaining=max(maximum_remaining,int(plugin.status().get("startup_remaining_ms",0)))
        yield(create_timer(0.02),"timeout")
    var status=plugin.status();var first_wait=sink.first_at-start
    okay=okay and waiting_seen and first_wait>=3000 and first_wait<6000 and sink.first_sample>=1 and sink.first_sample<=960 and maximum_remaining>=3700 and status.get("buffer_minimum_ms")==3000 and status.get("startup_lead_ms")==4000
    print("STARTUP_COLD_WAIT_MS=",first_wait," FIRST_SAMPLE=",sink.first_sample," WAITING_SEEN=",waiting_seen," MAX_SCHEDULED_LEAD_MS=",maximum_remaining)
    yield(create_timer(1.0),"timeout")
    var queued=r.queued_audio_snapshot()
    okay=okay and not r.buffering and queued.get("queued_ms",0)>0
    print("STARTUP_COLD_READY_AND_LOCAL_QUEUE=",not r.buffering and queued.get("queued_ms",0)>0)
    var oldgen=sink.first_gen
    var marker=File.new();marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE);marker.store_string("clear");marker.close()
    start=OS.get_ticks_msec();waiting_seen=false
    while sink.first_gen==oldgen and OS.get_ticks_msec()-start<7000:
        waiting_seen=waiting_seen or r.buffering
        maximum_remaining=max(maximum_remaining,int(plugin.status().get("startup_remaining_ms",0)))
        yield(create_timer(0.02),"timeout")
    var clear_wait=sink.first_at-start
    okay=okay and sink.first_gen!=oldgen and sink.first_sample>=1 and sink.first_sample<=960 and waiting_seen and clear_wait>=3000
    print("STARTUP_CLEAR_WAIT_MS=",clear_wait," FIRST_SAMPLE=",sink.first_sample," WAITING_SEEN=",waiting_seen," MAX_SCHEDULED_LEAD_MS=",maximum_remaining)
    r.stop();okay=okay and not r.buffering and r.queued_audio_snapshot().empty()
    yield(create_timer(0.3),"timeout")
    sink.first_at=-1;sink.first_gen=-1;sink.first_sample=0
    marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE);marker.store_string("reconnect");marker.close()
    start=OS.get_ticks_msec();var reconnected=r.begin(plugin,sink,vault,url);okay=reconnected and okay
    while sink.first_at<0 and OS.get_ticks_msec()-start<7000:yield(create_timer(0.02),"timeout")
    var reconnect_wait=sink.first_at-start
    okay=okay and sink.first_sample>=1 and sink.first_sample<=960 and reconnect_wait>=3000
    print("STARTUP_RECONNECT_WAIT_MS=",reconnect_wait," FIRST_SAMPLE=",sink.first_sample)
    # Cancel a fresh startup before its scheduled first frame.
    r.stop();yield(create_timer(0.3),"timeout")
    marker.open(OS.get_environment("SHIELDAMP_CLEAR_MARKER"),File.WRITE);marker.store_string("cancel");marker.close()
    var canceled_started=r.begin(plugin,sink,vault,url)
    okay=canceled_started and okay
    yield(create_timer(0.4),"timeout")
    r.stop();okay=okay and not r.buffering and not sink.active and r.queued_audio_snapshot().empty()
    print("STARTUP_COLD_CLEAR_RECONNECT_CANCEL=",okay)
    quit(0 if okay else 1)
