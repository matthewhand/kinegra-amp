extends Node
# One explicit operation: read fresh players, validate the exact paired owner,
# then issue only a bounded queue command/read. Credentials are cleared at end.
signal completed(ok, action, snapshot, detail)
var active=false
var host=null
var session=null
var client_id=""
var action=""
var catalog=null
var command_may_have_been_sent=false
var argument=null
var queue_snapshot={}
var failure_reason=""
var policy=preload("res://scripts/MAQueuePolicy.gd").new()

func _owner_is_current():
    if host==null or not is_instance_valid(host) or session==null or not is_instance_valid(session) or host.sendspin_facade!=session:
        return false
    if session.runtime==null or not session.runtime.active or session.client==null:
        return false
    var state=session.client.status()
    return typeof(state)==TYPE_DICTIONARY and state.get("paired",false)==true and state.get("client_id","")==client_id and not client_id.empty()

func begin(host_node, facade, endpoint, credential, trust_private, requested, requested_argument=null):
    if active or not requested in ["play","pause","stop","next","previous","read","items","seek_backward","seek_forward","remove","clear"]:
        return false
    if requested=="remove" and not policy.item_id(requested_argument):return false
    argument=requested_argument
    failure_reason=""
    queue_snapshot.clear()
    command_may_have_been_sent=false
    host=host_node
    session=facade
    action=requested
    if session==null or not is_instance_valid(session) or session.client==null: return false
    var state=session.client.status()
    if typeof(state)!=TYPE_DICTIONARY: return false
    client_id=str(state.get("client_id",""))
    if not _owner_is_current(): return false
    catalog=load("res://scripts/MACatalog.gd").new()
    add_child(catalog)
    if not catalog.configure(endpoint,credential,[],trust_private):
        catalog.queue_free();catalog=null
        return false
    catalog.connect("players_ready",self,"_on_players")
    catalog.connect("state_changed",self,"_on_state")
    catalog.connect("local_queue_snapshot",self,"_on_snapshot")
    catalog.connect("local_queue_items",self,"_on_items")
    active=true
    if not catalog.discover_players():
        if active: _finish(false,{},"Could not request player metadata")
        return false
    return true

func _on_players(_players):
    if not active: return
    if not _owner_is_current():
        _finish(false,{},"TV player changed; no queue command sent")
        return
    if action in ["play","items","seek_backward","seek_forward","remove"]:
        if not catalog.local_queue_request(client_id,"read") and active:
            _finish(false,{},"TV output route could not be verified")
    else:
        _send_mutation(action)

func _send_mutation(command, value=null):
    if not _owner_is_current():
        _finish(false,{},"TV player changed; no queue command sent")
        return
    command_may_have_been_sent=not command in ["read","items"]
    if not catalog.local_queue_request(client_id,command,value) and active:
        _finish(false,{},"TV output route could not be verified")

func _on_state(state, _detail):
    if not active: return
    if state=="queue_accepted":
        if _owner_is_current(): _finish(true,{},"Music Assistant accepted the queue command")
        else: _finish(false,{},"TV player changed while the request was in flight")
    elif state in ["auth_expired","permission_denied","disconnected","malformed_reply","command_failed","stale_reply","unsafe_route","invalid_request"]:
        if state in ["auth_expired","permission_denied"]:failure_reason="auth_failed"
        var reason="QUEUE REQUEST FAILED"
        if state=="auth_expired": reason="MUSIC ASSISTANT LOGIN EXPIRED"
        elif state=="permission_denied": reason="MUSIC ASSISTANT PERMISSION DENIED"
        elif state in ["disconnected","malformed_reply","stale_reply"] and command_may_have_been_sent: reason="PLAYBACK COMMAND RESULT UNKNOWN / CHECK QUEUE"
        elif state=="disconnected": reason="MUSIC ASSISTANT CONNECTION FAILED"
        elif state=="unsafe_route": reason="PLAYBACK ROUTE NOT VERIFIED"
        _finish(false,{},reason)

func _on_snapshot(value):
    if not active:return
    if not _owner_is_current():
        _finish(false,{},"TV player changed during the queue read")
        return
    if action=="read":
        _finish(true,value,"TV queue metadata read")
        return
    queue_snapshot=value.duplicate(true)
    if action=="play":
        if typeof(value.get("item_count"))==TYPE_INT and value.item_count==0:
            failure_reason="queue_empty"
            _finish(false,{},"YOUR QUEUE IS EMPTY / CHOOSE MUSIC")
            return
        # A newly reconnected client has no stream to unpause. MA's Play can
        # unpause its stale server-side queue without rebuilding that stream.
        # Resume reopens the saved queue position; a live stream keeps Play.
        _send_mutation(_play_request_command())
    elif action in ["seek_backward","seek_forward"]:
        var position=policy.seek_target(value,-10 if action=="seek_backward" else 10,OS.get_unix_time(),OS.get_ticks_msec())
        if position<0:
            _finish(false,{},"SEEK UNAVAILABLE / NEEDS FRESH PLAYING TRACK TIMING")
            return
        _send_mutation("seek",position)
    elif action in ["items","remove"]:
        if action=="items" and value.get("item_count",-1)==0:
            var empty=value.duplicate(true)
            empty["items"]=[]
            _finish(true,empty,"Queue is empty")
            return
        var offset=policy.upcoming_offset(value)
        if offset<0:
            _finish(false,{},"QUEUE POSITION UNAVAILABLE / REFRESH")
            return
        if not catalog.local_queue_request(client_id,"items",offset) and active:
            _finish(false,{},"TV output route could not be verified")

func _play_request_command():
    var output=session.client.status()
    return "play" if output.get("active",false)==true else "resume"

func _on_items(items):
    if not active:return
    if not _owner_is_current():
        _finish(false,{},"TV player changed during the queue read")
        return
    if action=="remove":
        if not policy.removable(queue_snapshot,items,argument):
            _finish(false,{},"SELECT A FRESH UPCOMING TRACK / REFRESH QUEUE")
            return
        _send_mutation("remove",argument)
    else:
        var snapshot=queue_snapshot.duplicate(true)
        snapshot["items"]=items
        _finish(true,snapshot,"Upcoming TV queue items read")

func _finish(ok, snapshot, detail):
    if not active: return
    active=false
    var completed_action=action
    if catalog!=null:
        catalog.close()
        catalog.queue_free()
        catalog=null
    client_id=""
    argument=null
    queue_snapshot.clear()
    session=null
    host=null
    emit_signal("completed",ok,completed_action,snapshot,detail)

func cancel():
    if not active: return
    active=false
    if catalog!=null:
        catalog.close()
        catalog.queue_free()
        catalog=null
    client_id=""
    argument=null
    queue_snapshot.clear()
    session=null
    host=null

func _exit_tree(): cancel()
