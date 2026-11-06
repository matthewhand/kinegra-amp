extends SceneTree
var failures=[]
func check(ok,label):
    print("BRIDGE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class Adapter:
    extends Reference
    var state={"active":true,"generation":1}
    var blocks=[]
    var calls=0
    func acknowledge_generation(g): return state.active and g==state.generation
    func status(): return state.duplicate()
    func read(_limit):
        calls+=1
        return blocks.pop_front() if not blocks.empty() else {"generation":state.generation,"bytes":PoolByteArray()}
class Output:
    extends Reference
    var started=[]
    var stopped=0
    var received=[]
    var reject=false
    var fail_start=false
    func stop(): stopped+=1
    func start_after_verified_session(g):
        started.append(g)
        return not fail_start
    func push_validated_pcm(data,g):
        if reject: return false
        received.append({"generation":g,"bytes":data})
        return true
func _init(): call_deferred("run")
func run():
    var Pump=load("res://scripts/SendspinBridgePump.gd")
    var pump=Pump.new()
    var source=Adapter.new()
    var sink=Output.new()
    var pcm=PoolByteArray([1,2,3,4,5,6,7,8])
    source.blocks=[{"generation":1,"bytes":pcm}]
    sink.reject=true
    check(pump.bind(source,sink) and pump.poll(),"attach_and_backpressure")
    check(pump.pending==pcm and source.calls==1 and sink.received.empty(),"pending_bytes_retained")
    check(pump.poll() and source.calls==1,"backpressure_does_not_read_again")
    sink.reject=false
    check(pump.poll() and sink.received.size()==1 and sink.received[0].bytes==pcm,"retry_sends_exact_bytes")
    sink.reject=true
    source.blocks=[{"generation":1,"bytes":pcm}]
    pump.poll()
    source.state.generation=2
    sink.reject=false
    check(pump.poll() and sink.received.size()==1 and pump.pending.empty() and sink.started==[1,2],"clear_flushes_pending_and_sink")
    source.blocks=[{"generation":1,"bytes":pcm}]
    check(pump.poll() and pump.generation==-1 and sink.received.size()==1,"raced_read_never_submitted")
    source.blocks=[{"generation":2,"bytes":PoolByteArray([1,2,3])}]
    check(not pump.poll() and pump.failure=="Invalid PCM block","misaligned_fails_closed")
    pump.bind(source,sink)
    source.state={"active":true,"generation":3}
    sink.fail_start=true
    check(not pump.poll() and pump.failure=="Audio output unavailable","failed_sink_does_not_read")
    sink.fail_start=false
    pump.bind(source,sink)
    source.state={"active":false,"generation":4}
    check(pump.poll() and pump.generation==-1,"inactive_remains_silent")
    source.state={"active":true,"generation":4}
    pump.poll()
    source.state.active=false
    check(pump.poll() and pump.generation==-1,"end_flushes_sink")
    pump.stop()
    print("BRIDGE_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
