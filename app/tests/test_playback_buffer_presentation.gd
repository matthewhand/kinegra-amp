extends SceneTree
const P=preload("res://scripts/PlaybackBufferPresentation.gd")
var checks=0
func ck(v):
    checks+=1
    if not v:
        push_error("buffer presentation check %d" % checks)
        quit(1)
func _init():call_deferred("run")
func run():
    var m={"timeline":true,"duration":100.0,"position":20.0,"state":"playing"}
    var q={"queued_ms":750.0,"measured_ms":1000,"generation":4}
    var a=P.present(m,q,1000)
    ck(a.timeline and abs(a.end_percent-20.75)<0.001 and a.label=="Buffered ~0.8s")
    m.state="paused";ck(not P.present(m,q,1100).empty())
    m.position=99.9;ck(P.present(m,q,1100).end_percent==100.0)
    m={"timeline":false,"state":"playing"};a=P.present(m,q,1100)
    ck(not a.timeline and a.end_percent==0.0 and not a.label.empty())
    ck(P.present({},q,1000).empty())
    ck(P.present(m,{},1000).empty())
    ck(P.present(m,q,1501).empty())
    ck(P.present(m,q,999).empty())
    for value in [-1,0,3000,NAN,INF,"750"]:
        q.queued_ms=value;ck(P.present(m,q,1100).empty())
    q.queued_ms=750
    for value in [NAN,INF,-1,"x"]:
        m={"timeline":true,"position":value,"duration":100.0};ck(P.present(m,q,1100).empty())
    print("BUFFER_PRESENTATION_CHECKS=",checks)
    quit()
