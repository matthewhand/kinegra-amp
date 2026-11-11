extends SceneTree
var failures=[]
var observed=[]
func observe(code): observed.append(code)
func check(ok,label):
    print("RUNTIME_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class Adapter:
    extends Reference
    var opens=0
    var closes=0
    var tick_ok=true
    var code=""
    func pairing_code(): return code
    var status_value={"active":false,"generation":0,"paired":false}
    func open(_url,_vault):
        opens+=1
        return true
    func close(): closes+=1
    func tick(): return tick_ok
    func status(): return status_value
    func command(_name): return false
class Sink:
    extends Reference
    var active=false
    var stream_generation=-1
    func stop(): active=false
func _init(): call_deferred("run")
func run():
    var runtime=load("res://scripts/SendspinPlaybackRuntime.gd").new()
    get_root().add_child(runtime)
    runtime.connect("pairing_code_changed",self,"observe")
    var adapter=Adapter.new()
    var sink=Sink.new()
    check(not runtime.begin(adapter,sink,null,"ws://fixture") and adapter.opens==0,"requires_explicit_vault")
    var vault=Reference.new()
    check(runtime.begin(adapter,sink,vault,"ws://fixture") and adapter.opens==1,"explicit_start")
    check(not runtime.begin(adapter,sink,vault,"ws://fixture"),"duplicate_start_rejected")
    check(runtime.step() and runtime.active and runtime.state=="connecting","idle_connection_no_autoplay")
    adapter.code="012345"
    check(runtime.step() and observed.size()==1 and observed[0]==adapter.code,"pairing_code_emitted")
    check(runtime.step() and observed.size()==1,"unchanged_not_reemitted")
    adapter.code="01x345"
    check(runtime.step() and observed.size()==2 and observed[1]=="","invalid_code_cleared")
    adapter.code="012345"
    runtime.step()
    adapter.code=""
    check(runtime.step() and observed.back()=="","sdk_clear_propagated")
    adapter.code="012345"
    runtime.step()
    runtime._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    check(runtime.active and adapter.closes==0,"focus_loss_preserves_pip_split_playback")
    runtime._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(observed.back()=="" and runtime.current_pairing_code=="","background_clears_code")
    check(not runtime.active and adapter.closes==1,"background_stops_and_disconnects")
    check(runtime.begin(adapter,sink,vault,"ws://fixture"),"restart_after_stop")
    adapter.tick_ok=false
    check(not runtime.step() and not runtime.active and adapter.closes==2 and runtime.state=="error","transport_failure_stops")
    adapter.tick_ok=true
    check(runtime.begin(adapter,sink,vault,"ws://fixture"),"open_after_transport_failure")
    adapter.status_value.paired=true
    check(runtime.step() and runtime.connection_deadline_ms==0,"paired_session_clears_deadline")
    adapter.status_value.paired=false
    check(runtime.step() and runtime.state=="connecting" and runtime.connection_deadline_ms>OS.get_ticks_msec(),"lost_peer_rearms_reconnect_deadline")
    adapter.status_value.paired=true
    check(runtime.step() and runtime.state=="paired" and runtime.connection_deadline_ms==0,"recovered_peer_clears_deadline")
    adapter.status_value.paired=false
    runtime.step()
    runtime.connection_deadline_ms=OS.get_ticks_msec()
    check(not runtime.step() and not runtime.active and runtime.state=="error","unrecovered_peer_expires_and_can_be_retried")
    runtime.queue_free()
    print("RUNTIME_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
