extends SceneTree
var failures=[]
func check(ok,label):
    print("POSE_VIS_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var visual=load("res://scripts/PoseVisual.gd").new()
    get_root().add_child(visual)
    yield(self,"idle_frame")
    check(not visual.enabled and visual.mode=="off" and not visual.is_processing(),"default_off_no_camera_work")
    visual.set_mode("demo")
    visual._process(0.1)
    check(visual.points.size()==33 and visual.status=="DEMO DANCER","synthetic_pose_visible")
    visual.set_enabled(true)
    var points=[]
    points=load("res://scripts/DanceLibrary.gd").pose(0)
    var collapsed=[]
    for i in range(33): collapsed.append([0.5,0.4,0.9])
    check(not visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":collapsed}),"collapsed_body_rejected")
    var partial=points.duplicate(true)
    partial[13][2]=0.1
    partial[15][2]=0.1
    partial[25][2]=0.1
    partial[27][2]=0.1
    check(visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":partial}) and visual.points[15][2]>=0.5 and visual.points[27][2]>=0.5 and visual.status=="BODY LIVE / PORTRAIT","missing_limbs_use_demo")
    for i in range(3): visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":partial})
    check(visual.view_mode=="portrait","legs_missing_zoom_to_portrait")
    var face=points.duplicate(true)
    for joint in [11,12,23,24]: face[joint][2]=0.0
    face[0]=[0.5,0.24,0.9]
    face[2]=[0.44,0.2,0.9]
    face[5]=[0.56,0.2,0.9]
    for i in range(3): visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":face})
    check(visual.view_mode=="face" and visual.status=="FACE LIVE","face_only_zoom")
    for i in range(3): visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":points})
    check(visual.view_mode=="body" and visual.points.size()==33,"fresh_pose_accepted")
    check(not visual.accept_pose({"enabled":true,"ageMs":2000,"landmarks":points}) and visual.tracking_live and not visual.points.empty() and visual.status=="BODY HOLD / BRIEF DROPOUT","brief_dropout_holds")
    visual.last_pose=OS.get_ticks_msec()-1000
    check(not visual.accept_pose({"enabled":true,"ageMs":2000,"landmarks":points}) and visual.points.empty() and not visual.tracking_live,"long_dropout_cleared")
    visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":points})
    visual.accept_pose({"enabled":true,"ageMs":900,"landmarks":points})
    check(OS.get_ticks_msec()-visual.last_pose>=900,"aging_frame_does_not_refresh_clock")
    check(not visual.accept_pose({"enabled":true,"ageMs":1300,"landmarks":points}) and not visual.tracking_live,"aging_frame_does_not_extend_hold")
    visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":points})
    var missing_anchor=points.duplicate(true)
    missing_anchor[11][2]=0.1
    missing_anchor[13][2]=0.1
    missing_anchor[15][2]=0.1
    check(visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":missing_anchor}) and visual.points[11][2]>=0.5 and visual.points[15][2]>=0.5,"missing_anchor_and_limb_synthesized")
    visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":points})
    check(not visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":collapsed}) and visual.points.empty(),"collapsed_clears_immediately")
    check(not visual.accept_pose({"enabled":false,"ageMs":1,"landmarks":points}),"disabled_pose_rejected")
    check(not visual.accept_pose({"enabled":true,"ageMs":10,"landmarks":[]}),"missing_pose_rejected")
    visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":points})
    var bad=points.duplicate(true)
    bad[0]=["invalid",0.4,0.9]
    check(not visual.accept_pose({"enabled":true,"ageMs":50,"landmarks":bad}) and visual.points.empty(),"malformed_pose_cleared")
    visual.set_mode("demo")
    visual._process(0.1)
    visual._completed(0,500,[],PoolByteArray())
    check(visual.status=="DEMO DANCER" and not visual.points.empty(),"late_live_callback_ignored_in_demo")
    visual.set_enabled(false)
    check(visual.points.empty() and visual.status=="OFF" and not visual.is_processing() and not visual.pending,"stop_cancels_poll_and_frame_work")
    visual.set_webcam_connected(true)
    visual.set_mode("live")
    visual.set_webcam_connected(false)
    check(visual.mode=="off" and not visual.is_processing(),"unplug_stops_tracking")
    print("POSE_VIS_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
