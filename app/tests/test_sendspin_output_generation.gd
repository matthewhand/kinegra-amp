extends SceneTree
var errors = []
var observed = 0
func on_pcm(_epoch,_rms,_playback,_latency): observed+=1
func _init():
    call_deferred("run")
func check(ok, message):
    if not ok:
        errors.append(message)
        printerr(message)
func run():
    if AudioServer.get_bus_index("Milkdrop") < 0:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.get_bus_count()-1,"Milkdrop")
    var sink = load("res://scripts/SendspinPcmOutput.gd").new()
    get_root().add_child(sink)
    sink.connect("pcm_observed",self,"on_pcm")
    check(sink.start_after_verified_session(10),"sink starts on asserted test session")
    var pcm = PoolByteArray([0,0,0,0,0,0,0,0])
    check(sink.push_validated_pcm(pcm,10),"current generation accepted")
    check(observed==0 and sink.last_pcm_at==-1,"priming silence is not live content")
    var audible=PoolByteArray([244,1,12,254])
    check(sink.push_validated_pcm(audible,10) and observed==1 and sink.last_rms>0.0,"nonzero real PCM updates analysis")
    check(not sink.push_validated_pcm(pcm),"unmarked PCM rejected")
    var old_playback = sink.playback
    check(sink.clear_after_verified_boundary(11),"ordered clear accepted")
    check(sink.active and sink.stream_generation == 11 and sink.playback != old_playback,"backend buffer replaced")
    check(sink.last_pcm_at==-1,"clear invalidates prior analysis")
    check(not sink.push_validated_pcm(pcm,10),"pre-seek PCM rejected")
    check(sink.push_validated_pcm(pcm,11),"post-seek PCM accepted")
    check(not sink.clear_after_verified_boundary(10),"stale clear rejected")
    sink.stop()
    check(not sink.active and sink.stream_generation == -1 and not sink.push_validated_pcm(pcm,11),"stop revokes generation")
    check(not sink.start_after_verified_session(-1),"invalid generation rejected")
    sink.queue_free()
    print("SENDSPIN_OUTPUT_GENERATION_CHECKS=13 FAILURES=", errors)
    quit(0 if errors.empty() else 1)
