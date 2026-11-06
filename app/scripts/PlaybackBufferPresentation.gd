extends Reference
# Uses only current playback metadata and measured local PCM occupancy.
static func present(metadata,queued,now_ms):
    if typeof(metadata)!=TYPE_DICTIONARY or metadata.empty() or typeof(queued)!=TYPE_DICTIONARY:return {}
    var measured=queued.get("measured_ms",-1)
    var amount=queued.get("queued_ms",-1)
    if typeof(measured)!=TYPE_INT or measured<0 or now_ms<measured or now_ms-measured>500:return {}
    if not (typeof(amount) in [TYPE_INT,TYPE_REAL]) or is_nan(float(amount)) or is_inf(float(amount)) or amount<=0 or amount>2500:return {}
    var result={"label":"Buffered ~%.1fs" % (float(amount)/1000.0),"timeline":false,"end_percent":0.0}
    if not metadata.get("timeline",false):return result
    var duration=metadata.get("duration",0)
    var position=metadata.get("position",-1)
    for value in [duration,position]:
        if not (typeof(value) in [TYPE_INT,TYPE_REAL]) or is_nan(float(value)) or is_inf(float(value)):return {}
    if duration<=0 or position<0 or position>duration:return {}
    result.timeline=true
    result.end_percent=100.0*min(float(duration),float(position)+float(amount)/1000.0)/float(duration)
    return result
