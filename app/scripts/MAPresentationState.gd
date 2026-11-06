extends Reference
# Read-only presentation of MA's genuine current item; never a queue mutation.
const MAX_AGE_MS=10000
var queue_policy=preload("res://scripts/MAQueuePolicy.gd").new()
func _number(value,low,high):
    return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and float(value)>=low and float(value)<=high
func current(snapshot,received_ms,now_ms,fresh_audio,now_unix):
    if typeof(snapshot)!=TYPE_DICTIONARY or not _number(received_ms,0,20000000000000) or not _number(now_ms,received_ms,received_ms+MAX_AGE_MS):return {}
    if not queue_policy.item_id(snapshot.get("current_id")) or str(snapshot.get("current","")).strip_edges().empty():return {}
    var result={"title":str(snapshot["current"]),"artist":str(snapshot.get("artist","")),"album":str(snapshot.get("album","")),"state":str(snapshot.get("state","unknown")),"timeline":false,"advancing":false}
    var duration=snapshot.get("duration")
    var elapsed=snapshot.get("elapsed")
    if not _number(duration,1,86400) or not _number(elapsed,0,float(duration)):return result
    result["timeline"]=true
    result["duration"]=float(duration)
    result["position"]=float(elapsed)
    if fresh_audio and snapshot.get("state")=="playing":
        var position=queue_policy.seek_target(snapshot,0,now_unix,now_ms)
        if position>=0:
            result["position"]=float(position)
            result["advancing"]=true
    return result
