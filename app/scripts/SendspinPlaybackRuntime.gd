extends Node
# Explicit, experimental player lifecycle. No discovery, autoplay or UI.
# Mixer timing is estimated; validate latency on the target before release.
signal state_changed(state, detail)
signal pairing_code_changed(code)
var adapter=null
var sink=null
var pump=preload("res://scripts/SendspinBridgePump.gd").new()
var active=false
var buffering = false
var buffer_invalid_generation = -1
var state="idle"
var current_pairing_code=""
const CONNECT_TIMEOUT_MS=20000
const PAIRING_TIMEOUT_MS=120000
var connection_deadline_ms=0
var pairing_started=false
var pairing_confirmation_pending=false
func _ready(): set_process(false)
func _state(value,detail):
    state=value
    emit_signal("state_changed",value,detail)
func begin(client,output,vault,endpoint):
    if active or client==null or output==null or vault==null:
        return false
    var opened=client.open(endpoint,vault)
    if typeof(opened)!=TYPE_BOOL or not opened:
        client.close()
        _state("error","Sendspin connection or secure storage unavailable")
        return false
    adapter=client
    sink=output
    if not pump.bind(adapter,sink):
        adapter.close(); adapter=null; sink=null
        _state("error","Audio output unavailable")
        return false
    active=true
    pairing_started=false
    pairing_confirmation_pending=false
    connection_deadline_ms=OS.get_ticks_msec()+CONNECT_TIMEOUT_MS
    set_process(true)
    _state("connecting","Waiting for paired Sendspin player")
    return true
func step():
    if not active: return false
    var ticked=adapter.tick()
    if typeof(ticked)!=TYPE_BOOL or not ticked:
        stop()
        _state("error","Sendspin connection or secure storage failed")
        return false
    var status=adapter.status()
    if not _valid_status(status):
        stop(); _state("error","Invalid Sendspin status; reconnect playback"); return false
    _set_pairing_code("" if status["paired"] else adapter.pairing_code())
    if not status.get("pairing_window",false):pairing_confirmation_pending=false
    if status["paired"]:
        connection_deadline_ms=0
    elif connection_deadline_ms>0:
        if not pairing_started and (not current_pairing_code.empty() or status.get("pairing_window",false)):
            pairing_started=true
            connection_deadline_ms=OS.get_ticks_msec()+PAIRING_TIMEOUT_MS
        if OS.get_ticks_msec()>=connection_deadline_ms:
            var timed_out_pairing=pairing_started
            stop(); _state("error","Pairing timed out; choose Connect playback to retry" if timed_out_pairing else "Connection timed out; choose Connect playback to retry"); return false
    if sink.active and status["active"] and sink.stream_generation==status["generation"]:
        if not sink.report_mixer_feedback(adapter):
            stop(); _state("error","Audio timing feedback unavailable"); return false
    if not pump.poll():
        var reason=pump.failure
        stop(); _state("error",reason); return false
    var current="receiving" if sink.active else ("paired" if status.get("paired",false) else "connecting")
    var waiting=bool(status.get("startup_buffering",false)) or (sink.active and sink.get("buffering")==true)
    if current!=state or waiting!=buffering:
        buffering=waiting
        _state(current,"Buffering audio…" if waiting else ("Receiving synchronized audio" if current=="receiving" else "Waiting for audio"))
    return true
func _valid_status(status):
    if typeof(status)!=TYPE_DICTIONARY or typeof(status.get("active"))!=TYPE_BOOL or typeof(status.get("paired"))!=TYPE_BOOL or typeof(status.get("generation"))!=TYPE_INT or status["generation"]<0:return false
    if status.has("pairing_window") and typeof(status["pairing_window"])!=TYPE_BOOL:return false
    return not status["active"] or status["paired"]
func confirm_pairing():
    if not active or adapter==null or pairing_confirmation_pending:return false
    var status=adapter.status()
    if not _valid_status(status) or status.get("paired",false) or status.get("pairing_window",false)!=true:return false
    if not adapter.has_method("confirm_pairing"):return false
    var confirmed=adapter.confirm_pairing()
    if typeof(confirmed)!=TYPE_BOOL or not confirmed:return false
    pairing_confirmation_pending=true
    _state(state,"Pairing confirmation sent; waiting for Music Assistant")
    return true
func _set_pairing_code(value):
    var code = value if typeof(value)==TYPE_STRING else ""
    if code.length()!=6:
        code=""
    else:
        for c in code:
            if c < "0" or c > "9":
                code=""
                break
    if code != current_pairing_code:
        current_pairing_code=code
        emit_signal("pairing_code_changed",code)
func command(name,position=-1):
    if not active: return false
    var accepted=adapter.command(name,position) if name=="seek" else adapter.command(name)
    if accepted and name in ["seek","next","previous","stop"]:invalidate_buffer_measurement()
    return accepted
# Also called after accepted MA HTTP seek/skip/stop/clear controls.
func invalidate_buffer_measurement():
    buffer_invalid_generation=pump.generation
func stop():
    connection_deadline_ms=0
    pairing_started=false
    pairing_confirmation_pending=false
    buffer_invalid_generation=-1
    buffering=false
    _set_pairing_code("")
    set_process(false)
    pump.stop()
    if adapter!=null: adapter.close()
    adapter=null
    sink=null
    active=false
    _state("idle","Player stopped")
func _process(_delta): step()
func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED and active:
        stop()
func _exit_tree():
    if active: stop()

# A conservative local lower bound: each byte is in exactly one stage below.
# SDK encoded lookahead is deliberately excluded; the target is not occupancy.
func queued_audio_snapshot():
    if not active or adapter==null or sink==null or not sink.active:return {}
    var status=adapter.status()
    if typeof(status)!=TYPE_DICTIONARY or not status.get("active",false) or not status.get("paired",false) or status.get("startup_buffering",true):return {}
    var gen=status.get("generation",-1)
    var count=status.get("queued_bytes",-1)
    if typeof(gen)!=TYPE_INT or gen<0 or gen!=pump.generation or gen!=sink.stream_generation or gen==buffer_invalid_generation:return {}
    if typeof(count)!=TYPE_INT or count<0 or count>19200 or count%4!=0:return {}
    if not sink.has_method("queued_audio_frames"):return {}
    var frames=sink.queued_audio_frames(gen)
    if typeof(frames)!=TYPE_INT or frames<0 or frames>96000:return {}
    var staging=pump.pending.size()
    if staging<0 or staging>pump.MAX_READ_BYTES or staging%4!=0:return {}
    # Re-read after measuring: a concurrent ordered clear invalidates all stages.
    var fresh=adapter.status()
    if typeof(fresh)!=TYPE_DICTIONARY or not fresh.get("active",false) or fresh.get("generation",-1)!=gen or fresh.get("startup_buffering",true):return {}
    return {"generation":gen,"queued_ms":float(count+staging)*1000.0/192000.0+float(frames)*1000.0/48000.0,"measured_ms":OS.get_ticks_msec()}
