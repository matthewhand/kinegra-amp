extends SceneTree
var failures=[]
var samples=[]
var losses=[]
func check(ok,label):
    print("POSE_GESTURE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _sample(points,epoch,frame,captured):samples.append({"points":points,"epoch":epoch,"frame":frame,"captured":captured})
func _lost(reason):losses.append(reason)
func _init():call_deferred("run")
func run():
    var pose=load("res://scripts/PoseVisual.gd").new();get_root().add_child(pose)
    pose.connect("gesture_sample",self,"_sample");pose.connect("gesture_tracking_lost",self,"_lost")
    yield(create_timer(.03),"timeout")
    pose.webcam_timer.stop();pose.set_webcam_connected(true);pose.set_mode("live");pose.set_process(false)
    var data={"enabled":true,"sourceEpoch":1,"frame":1,"ageMs":0,"landmarks":load("res://scripts/DanceLibrary.gd").pose(0.0)}
    data.landmarks[15][2]=.1
    pose.accept_pose(data)
    check(samples.size()==1 and samples[0].points[15][2]==.1 and pose.points[15][2]==1.0,"signal_contains_raw_confidence_before_visual_inference")
    for _i in range(8):pose.accept_pose(data)
    check(samples.size()==1,"cached_frame_is_not_emitted_again")
    yield(create_timer(.02),"timeout")
    data.frame=2;pose.accept_pose(data)
    check(samples.size()==2,"fresh_distinct_frame_emitted")
    data.frame=3;data.ageMs=501;pose.accept_pose(data)
    check(samples.size()==2 and losses.back()=="unidentified_or_stale_pose","stale_visual_hold_never_becomes_gesture_sample")
    data.ageMs="0";pose.accept_pose(data)
    check(samples.size()==2,"string_age_cannot_forge_fresh_sample")
    data.ageMs=0;data.erase("frame");pose.accept_pose(data)
    check(samples.size()==2,"missing_frame_identity_rejected")
    data.frame=4;pose.set_mode("demo");pose.set_process(false);pose.accept_pose(data)
    check(samples.size()==2,"demo_never_emits_control_sample")
    pose.set_mode("live");pose.set_process(false);pose.set_webcam_connected(false);pose.accept_pose(data)
    check(samples.size()==2,"disconnected_camera_never_emits_control_sample")
    check(losses.has("source_reset") and losses.has("webcam_disconnected"),"source_reset_and_camera_loss_cancel_recognition")
    pose.queue_free();print("POSE_GESTURE_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
