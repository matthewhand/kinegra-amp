extends Reference
# Recovery belongs to a recent explicit Play intent, never app entry/autoplay.
const MAX_ATTEMPTS=3
var armed=false
var binding=""
var since=0
var last_data=-1
var healthy_since=-1
var attempts=0
var next_attempt=0
var had_audio=false
var exhausted=false

func cancel():
    armed=false;binding="";healthy_since=-1;exhausted=false

func play_intent(owner,now):
    armed=true;binding=owner;since=now;last_data=-1;healthy_since=-1
    attempts=0;next_attempt=now;had_audio=false;exhausted=false

func step(now,owner,pcm_at,buffering,busy,queue_state,queue_fresh):
    if not armed:return ""
    if owner.empty() or owner!=binding:
        cancel()
        return ""
    # A fresh paused/stopped/empty queue is authoritative, including changes
    # from another controller. Never undo a deliberate external Pause/Stop.
    if queue_fresh and queue_state in ["paused","idle","stopped"]:
        cancel()
        return ""
    if pcm_at>=since and pcm_at<=now:
        if pcm_at>last_data:last_data=pcm_at
        had_audio=true
    var fresh=last_data>=0 and now-last_data<1000 and not buffering
    if fresh:
        if healthy_since<0:healthy_since=now
        if now-healthy_since>=30000:attempts=0;exhausted=false
        return ""
    healthy_since=-1
    var wait=8000 if had_audio else 30000
    var silence=now-last_data if last_data>=0 else now-since
    if busy or silence<wait or now<next_attempt:return ""
    if attempts>=MAX_ATTEMPTS:
        armed=false;exhausted=true
        return "exhausted"
    attempts+=1
    next_attempt=now+[15000,30000,60000][attempts-1]
    since=now;last_data=-1;had_audio=false
    return "reconnect"
