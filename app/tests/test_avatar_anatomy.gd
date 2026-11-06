extends SceneTree
var failures=[]
var checks=0
func check(ok,label):
    checks+=1
    print("ANATOMY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func generic():return load("res://scripts/DanceLibrary.gd").pose(0.0)
func bounded(avatar):
    var rig=avatar.anatomy.layout(avatar.last_points)
    if rig.empty():return false
    var offset=avatar.head.translation-rig.shoulder
    return offset.dot(rig.up)>=rig.unit*.65 and offset.dot(rig.up)<=rig.unit*.97 and abs(offset.dot(rig.right))<=rig.unit*.36
func _init():call_deferred("run")
func run():
    var avatar=load("res://scripts/AvatarRenderer.gd").new();get_root().add_child(avatar);avatar.set_active(true)
    var full=generic()
    check(avatar.set_pose(full) and avatar.head.visible and avatar.neck.visible and avatar.torso.visible and bounded(avatar),"full_body_connected_head_neck_torso")
    var neck_bottom=avatar.neck.translation-avatar.neck.transform.basis.y*.5
    var neck_top=avatar.neck.translation+avatar.neck.transform.basis.y*.5
    var rig=avatar.anatomy.layout(full)
    check(neck_bottom.distance_to(rig.shoulder)<.001 and neck_top.distance_to(avatar.head.translation-avatar.head.transform.basis.y*.48)<.001,"neck_connects_actual_mesh_endpoints")
    var seated=full.duplicate(true)
    for point in seated:
        if point[2]>=.5:point[1]+=0.12
    check(avatar.set_pose(seated) and bounded(avatar),"seated_head_stays_attached")
    avatar._process(1.0)
    var projection=(rig.shoulder.y-0.0)/4.5
    var seated_projection=(avatar.body_anchor.y-avatar.camera.translation.y)/avatar.camera.size
    check(abs(projection-seated_projection)<.02,"seated_and_backup_shoulders_share_screen_framing")
    var outlier=full.duplicate(true);outlier[0]=[0.5,0.01,1.0]
    avatar.set_pose(outlier)
    check(avatar.head.visible and bounded(avatar) and avatar.neck.visible,"high_confidence_nose_jitter_cannot_detach_head")
    var neutral=full.duplicate(true)
    neutral[2]=[.47,.19,1.0];neutral[5]=[.53,.19,1.0];neutral[0]=[.5,.22,1.0]
    avatar.set_pose(neutral)
    var fixed_head=avatar.head.translation
    var up=neutral.duplicate(true);up[0][1]=.185
    for _i in range(10):avatar.set_pose(up)
    var up_pitch=avatar.head.rotation.x
    check(up_pitch<-.15 and avatar.head.translation.distance_to(fixed_head)<.001 and bounded(avatar),"looking_up_rotates_without_floating_head")
    var down=neutral.duplicate(true);down[0][1]=.26
    for _i in range(10):avatar.set_pose(down)
    check(avatar.head.rotation.x>.15 and avatar.head.translation.distance_to(fixed_head)<.001 and avatar.neck.visible,"looking_down_rotates_without_floating_head")
    var top=avatar.neck.translation+avatar.neck.transform.basis.y*.5
    check(top.distance_to(avatar.head.translation-avatar.head.transform.basis.y*.48)<.001,"pitched_head_remains_connected_to_neck")
    var max_step=0.0
    var previous=avatar.head.translation
    for index in range(40):
        var jitter=full.duplicate(true);jitter[0][0]+=0.08 if index%2==0 else -0.08;jitter[0][1]+=0.08 if index%2==0 else -0.08
        avatar.set_pose(jitter)
        max_step=max(max_step,avatar.head.translation.distance_to(previous));previous=avatar.head.translation
        check(bounded(avatar),"jitter_head_bounds")
    check(max_step<.25,"head_offset_smoothing_limits_frame_jumps")
    for missing in [11,12,23,24]:
        var partial=full.duplicate(true);partial[missing][2]=.2
        check(not avatar.set_pose(partial) and not avatar.scene.visible and not avatar.is_processing(),"weak_required_body_anchor_hides_rig_"+str(missing))
    var missing_head=full.duplicate(true);missing_head[0][2]=.1;avatar.set_pose(missing_head)
    check(avatar.torso.visible and not avatar.head.visible and not avatar.neck.visible,"weak_head_cannot_draw_a_false_valid_head")
    var cropped=full.duplicate(true);cropped[23][1]=1.5;cropped[24][1]=1.5
    check(not avatar.set_pose(cropped) and not avatar.scene.visible,"cropped_invalid_hips_do_not_sink_torso")
    var long_body=full.duplicate(true);long_body[23][1]=.75;long_body[24][1]=.75;avatar.set_pose(long_body)
    check(avatar.torso.scale.y<=avatar.body_unit*2.09 and bounded(avatar),"torso_height_and_head_share_bounded_unit")
    var visual_pose=load("res://scripts/PoseVisual.gd").new();get_root().add_child(visual_pose)
    visual_pose.webcam_timer.stop();visual_pose.set_process(false)
    var partial=neutral.duplicate(true);partial[23][2]=.1
    for index in [25,26,27,28]:partial[index][2]=.1
    var payload={"enabled":true,"ageMs":0,"landmarks":partial}
    for _i in range(3):visual_pose.accept_pose(payload)
    avatar.set_pose(visual_pose.points)
    var portrait_anchor=avatar.head.translation
    check(visual_pose.view_mode=="portrait" and visual_pose.points[23][2]==1.0 and avatar.head.visible and avatar.neck.visible,"portrait_reconstruction_still_obeys_connected_rig")
    payload.landmarks[0][1]=.185
    for _i in range(10):
        visual_pose.accept_pose(payload)
        avatar.set_pose(visual_pose.points)
    check(avatar.head.rotation.x<-.15 and avatar.head.translation.distance_to(portrait_anchor)<.001,"reconstructed_portrait_looking_up_rotates_without_float")
    var portrait_neck=avatar.neck.translation+avatar.neck.transform.basis.y*.5
    check(portrait_neck.distance_to(avatar.head.translation-avatar.head.transform.basis.y*.48)<.001,"reconstructed_portrait_neck_joins_rotated_head")
    visual_pose.queue_free()
    avatar.set_render_budget(0)
    check(not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"visual_off_budget_remains_idle")
    avatar.queue_free()
    print("ANATOMY_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
