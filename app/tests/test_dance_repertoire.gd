extends SceneTree
var failed=[]
func ck(ok,label):
    print("DANCE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failed.append(label)
func _init(): call_deferred("run")
func run():
    var library=load("res://scripts/DanceLibrary.gd")
    ck(library.NAMES.size()>=12,"twelve_named_moves")
    var poses=[]
    for i in range(library.NAMES.size()):
        var at=float(i)*library.SECONDS_PER_MOVE+4.0
        var p=library.pose(at)
        ck(p.size()==33 and library.move_name(at)==library.NAMES[i],"valid_move_"+str(i))
        poses.append(p)
        for index in [0,11,12,13,14,15,16,23,24,25,26,27,28]:
            ck(p[index][0]>=0.0 and p[index][0]<=1.0 and p[index][1]>=0.0 and p[index][1]<=1.0,"bounded_joint")
    ck(poses[1][15]!=poses[3][15] and poses[2][13]!=poses[7][13],"distinct_movements")
    var before=library.pose(7.999)
    var after=library.pose(8.001)
    ck(abs(before[15][0]-after[15][0])<0.02 and abs(before[15][1]-after[15][1])<0.02,"smooth_transition")
    var visual=load("res://scripts/PoseVisual.gd").new()
    get_root().add_child(visual)
    yield(self,"idle_frame")
    visual.set_mode("live")
    visual.accept_pose({"enabled":true,"ageMs":-1,"landmarks":[]})
    visual._process(0.1)
    ck(visual.points.size()==33 and not visual.tracking_live,"no_person_synthetic_fallback")
    var live=library.pose(0.0)
    ck(visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":live}) and visual.tracking_live,"live_body_recovers")
    visual.last_pose=OS.get_ticks_msec()-2000
    visual.accept_pose({"enabled":true,"ageMs":2000,"landmarks":live})
    visual._process(0.1)
    ck(visual.points.size()==33 and not visual.tracking_live,"stale_body_falls_back")
    print("DANCE_FAILURES=",failed.size())
    quit(0 if failed.empty() else 1)
