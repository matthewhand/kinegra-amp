extends SceneTree
var failures=[]
func check(ok,label):
    print("PUMP_SINK_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class Source:
    extends Reference
    var active=true
    var generation=1
    var next=PoolByteArray()
    func acknowledge_generation(g): return active and g==generation
    func status(): return {"active":active,"generation":generation}
    func read(_size):
        var data=next
        next=PoolByteArray()
        return {"generation":generation,"bytes":data}
func _init(): call_deferred("run")
func run():
    if AudioServer.get_bus_index("Milkdrop")<0:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.get_bus_count()-1,"Milkdrop")
    var sink=load("res://scripts/SendspinPcmOutput.gd").new()
    get_root().add_child(sink)
    var pump=load("res://scripts/SendspinBridgePump.gd").new()
    var source=Source.new()
    source.next=PoolByteArray([1,2,3,4,5,6,7,8])
    check(pump.bind(source,sink) and pump.poll(),"start_and_feed_real_sink")
    check(sink.active and sink.audio.bus=="Milkdrop" and sink.stream_generation==1,"routes_pcm_to_visualizer_bus")
    var original=sink.playback
    source.generation=2
    check(pump.poll() and sink.stream_generation==2 and sink.playback!=original,"clear_replaces_audio_buffer")
    source.active=false
    check(pump.poll() and not sink.active,"end_stops_output")
    sink.queue_free()
    print("PUMP_SINK_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
