extends Reference
# Temporary render cap while a new authenticated audio generation settles.
# Does not pause audio, change its timestamps, or alter the user's quality mode.
const STABLE_MS=2000
const READY_QUEUE_MS=384
var generation=-1
var stable_since=-1
var complete=false
var holding=false
var prepare_until=0

func reset():
    generation=-1
    stable_since=-1
    complete=false
    holding=false
    prepare_until=0

func prepare(now_ms):
    if typeof(now_ms)!=TYPE_INT or now_ms<0:return false
    stable_since=-1
    complete=false
    holding=true
    prepare_until=now_ms+20000
    return true

func observe(now_ms,audio={}):
    if typeof(now_ms)!=TYPE_INT or now_ms<0:return holding
    if typeof(audio)!=TYPE_DICTIONARY or audio.get("active",false)!=true:
        if now_ms<prepare_until:return true
        reset()
        return false
    prepare_until=0
    var gen=audio.get("generation",-1)
    if typeof(gen)!=TYPE_INT or gen<0:
        reset()
        return false
    if gen!=generation:
        generation=gen
        stable_since=-1
        complete=false
    if complete:return false # Metadata/natural transitions never re-arm this cap.
    holding=true
    var queued=audio.get("queued_ms",-1)
    var ready=typeof(queued)==TYPE_INT and queued>=READY_QUEUE_MS and audio.get("buffering",true)==false
    if not ready or (stable_since>=0 and now_ms<stable_since):
        stable_since=-1
    elif stable_since<0:
        stable_since=now_ms
    elif now_ms-stable_since>=STABLE_MS:
        complete=true
        holding=false
    return holding
