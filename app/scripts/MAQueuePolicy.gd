extends Reference
# Pure validation for bounded own-queue edits. A fresh server read is required
# by MATvQueueRequest before these decisions become a mutation.
const MAX_SECONDS=86400
const MAX_INDEX=100000
func _number(value,low,high):
    return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and float(value)>=low and float(value)<=high
func item_id(value):
    if typeof(value)!=TYPE_STRING or value.empty() or value.length()>200 or "://" in value:return false
    for i in range(value.length()):
        if value.ord_at(i)<32 or value.ord_at(i)==127:return false
    return true
func _index(value):
    return _number(value,0,MAX_INDEX) and floor(float(value))==float(value)
func upcoming_offset(snapshot):
    if typeof(snapshot)!=TYPE_DICTIONARY:return -1
    var current=snapshot.get("current_index")
    var buffered=snapshot.get("index_in_buffer")
    if current!=null and not _index(current):return -1
    if buffered!=null and not _index(buffered):return -1
    return max(int(current) if current!=null else -1,int(buffered) if buffered!=null else -1)+1
func http_clock(headers,received_ms,roundtrip_ms):
    # RFC7231 Date is produced by this same configured HTTP origin. Keep only
    # a numeric UTC anchor, never response headers or local wall-clock offset.
    var invalid={"clock_valid":false}
    var date=""
    var count=0
    for header in headers:
        if typeof(header)!=TYPE_STRING:continue
        var separator=header.find(":")
        if separator<0 or header.substr(0,separator).strip_edges().to_lower()!="date":continue
        count+=1
        date=header.substr(separator+1).strip_edges()
    if count==0:return {} # No Date: retain the strict local-clock policy.
    if count!=1 or date.length()!=29 or not _number(received_ms,0,20000000000000) or not _number(roundtrip_ms,0,2000):return invalid
    var pattern=RegEx.new()
    pattern.compile("^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), ([0-9]{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$")
    var match_date=pattern.search(date)
    if match_date==null:return invalid
    var months=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    var value={"year":int(match_date.get_string(4)),"month":months.find(match_date.get_string(3))+1,"day":int(match_date.get_string(2)),"hour":int(match_date.get_string(5)),"minute":int(match_date.get_string(6)),"second":int(match_date.get_string(7))}
    if value.year<1970 or value.year>2099 or value.day<1 or value.day>31 or value.hour>23 or value.minute>59 or value.second>59:return invalid
    var epoch=OS.get_unix_time_from_datetime(value)
    var roundtrip=OS.get_datetime_from_unix_time(epoch)
    for key in value:
        if roundtrip.get(key)!=value[key]:return invalid
    if ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][int(roundtrip.weekday)]!=match_date.get_string(1):return invalid
    return {"clock_valid":true,"server_time":epoch,"clock_received_ms":int(received_ms),"clock_rtt_ms":int(roundtrip_ms)}
func seek_target(snapshot,delta,now_unix,now_monotonic=-1):
    if typeof(snapshot)!=TYPE_DICTIONARY or not delta in [-10,0,10]:return -1
    if snapshot.get("active")!=true or snapshot.get("state")!="playing" or not item_id(snapshot.get("current_id")):return -1
    var duration=snapshot.get("duration")
    var elapsed=snapshot.get("elapsed")
    var updated=snapshot.get("elapsed_updated")
    if not _number(duration,1,MAX_SECONDS) or not _number(elapsed,0,float(duration)) or not _number(updated,1,20000000000):return -1
    if snapshot.has("clock_valid") and snapshot.get("clock_valid")!=true:return -1
    var reference=0.0
    var upper_reference=0.0
    if snapshot.has("server_time") or snapshot.has("clock_received_ms"):
        var server_time=snapshot.get("server_time")
        var received=snapshot.get("clock_received_ms")
        var roundtrip_ms=snapshot.get("clock_rtt_ms")
        if not _number(server_time,1,20000000000) or not _number(received,0,20000000000000) or not _number(now_monotonic,0,20000000000000) or not _number(roundtrip_ms,0,2000):return -1
        var since_received=float(now_monotonic)-float(received)
        if since_received<0 or since_received>5000:return -1
        # Date has one-second resolution. Its lower bound is conservative;
        # never add a guessed device/server clock offset to the track position.
        reference=float(server_time)+since_received/1000.0
        # For stale-data rejection use the upper bound: Date rounding plus
        # the full measured request transit, never a widened freshness window.
        upper_reference=reference+1.0+float(roundtrip_ms)/1000.0
    else:
        if not _number(now_unix,1,20000000000):return -1
        reference=float(now_unix)
        upper_reference=reference
    var age=reference-float(updated)
    var upper_age=upper_reference-float(updated)
    # Refuse stale/clock-skewed metadata rather than turn a guessed timeline
    # into a seek. Idle/paused seeks can start playback on MA, so stay disabled.
    if age < -2.0 or upper_age > 10.0 or float(elapsed)+max(0.0,upper_age)>float(duration)+2.0:return -1
    return int(clamp(float(elapsed)+max(0.0,age)+float(delta),0.0,float(duration)))
func removable(snapshot,rows,id):
    if not item_id(id) or typeof(rows)!=TYPE_ARRAY:return false
    var first=upcoming_offset(snapshot)
    if first<0 or id==snapshot.get("current_id"):return false
    var matches=0
    for row in rows:
        if typeof(row)==TYPE_DICTIONARY and row.get("item_id")==id and _index(row.get("index")) and int(row["index"])>=first:matches+=1
    return matches==1
