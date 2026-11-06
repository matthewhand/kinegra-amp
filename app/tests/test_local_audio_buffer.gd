extends SceneTree
class Adapter:
    extends Reference
    var state={"active":true,"paired":true,"generation":5,"queued_bytes":1920,"startup_buffering":false}
    var accept=true
    func status():return state.duplicate()
    func command(_name,_position=-1):return accept
    func close():pass
class Sink:
    extends Reference
    var active=true
    var stream_generation=5
    var frames=4800
    func queued_audio_frames(_gen):return frames
    func stop():active=false
var failures=[]
func ck(v,label):
    if not v:failures.append(label)
func _init():call_deferred("run")
func run():
    var r=load("res://scripts/SendspinPlaybackRuntime.gd").new();get_root().add_child(r);r.set_process(false)
    var a=Adapter.new();var s=Sink.new();r.active=true;r.adapter=a;r.sink=s;r.pump.adapter=a;r.pump.sink=s;r.pump.generation=5
    r.pump.pending=PoolByteArray([0,0,0,0])
    ck(abs(r.queued_audio_snapshot().queued_ms-110.020833)<0.001,"unique ring+staging+actual generator occupancy")
    a.state.startup_buffering=true;ck(r.queued_audio_snapshot().empty(),"startup silence excluded");a.state.startup_buffering=false
    a.state.generation=6;ck(r.queued_audio_snapshot().empty(),"clear discards old generation");a.state.generation=5
    a.state.paired=false;ck(r.queued_audio_snapshot().empty(),"auth cleared");a.state.paired=true
    ck(r.command("seek",1000) and r.queued_audio_snapshot().empty(),"accepted seek hides old pending buffer")
    a.state.generation=6;r.pump.generation=6;s.stream_generation=6;ck(not r.queued_audio_snapshot().empty(),"new generation measurable")
    r.invalidate_buffer_measurement();ck(r.queued_audio_snapshot().empty(),"accepted external HTTP control hides old buffer")
    a.state.generation=7;r.pump.generation=7;s.stream_generation=7
    a.accept=false;ck(not r.command("next") and not r.queued_audio_snapshot().empty(),"rejected command preserves current buffer")
    for n in [-1,19204,3,"1920"]:
        a.state.queued_bytes=n;ck(r.queued_audio_snapshot().empty(),"bounded aligned bridge")
    a.state.queued_bytes=1920;s.frames=-1;ck(r.queued_audio_snapshot().empty(),"invalid generator measurement")
    s.frames=4800;r.stop();ck(r.queued_audio_snapshot().empty() and not r.buffering,"session reset")
    print("LOCAL_AUDIO_BUFFER_FAILURES=",failures)
    quit(0 if failures.empty() else 1)
