extends SceneTree
var failures=[]
var checks=0
var now=1000
var frame=0
func ck(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        printerr("TRACKING_PANEL_FAIL_",label)
func pose():
    var points=[]
    for _i in range(33):points.append([.5,.5,0.0])
    for pair in [[11,.4,.35],[12,.6,.35],[23,.43,.7],[24,.57,.7],[15,.4,.65],[16,.6,.65]]:points[pair[0]]=[pair[1],pair[2],.95]
    return points
func sample(policy,points):
    now+=250;frame+=1
    return policy.sample(now,1,frame,now,points,true)
func _init():call_deferred("run")
func run():
    var status=load("res://scripts/StatusStability.gd").new()
    ck(status.update("Waiting",0)=="Waiting","initial_status_immediate")
    for time in range(100,2100,100):status.update("Ready" if time%200==0 else "Waiting",time)
    ck(status.shown=="Waiting","alternating_warning_does_not_flicker")
    for time in range(2200,2900,100):status.update("Ready",time)
    ck(status.shown=="Ready","stable_message_eventually_replaces_old_status")
    ck(status.update("Camera disconnected",2901,true)=="Camera disconnected","hardware_error_is_immediate")
    var fade=load("res://scripts/TrackingFade.gd").new()
    fade.step(.2,true);ck(fade.alpha==1.0,"valid_pose_fades_in")
    fade.step(.25,false);ck(fade.alpha==1.0,"brief_loss_holds_last_frame")
    fade.step(.25,false);ck(fade.alpha<1.0 and fade.alpha>.8,"loss_fades_gradually")
    for _i in range(8):fade.step(.25,false)
    ck(fade.alpha==0.0,"long_loss_becomes_transparent")
    fade.step(.05,true);ck(fade.alpha>0 and fade.alpha<1,"recovery_fades_in_without_flash")
    var policy=load("res://scripts/BodyControlPanelPolicy.gd").new();var down=pose()
    down[15][2]=.52;down[16][2]=.52
    for _i in range(3):ck(sample(policy,down).empty(),"lowering_arms_has_no_action")
    var cross=down.duplicate(true);cross[15]=[.6,.35,.95];cross[16]=[.4,.35,.95]
    for _i in range(4):ck(sample(policy,cross).empty(),"crossing_opens_without_playback")
    ck(policy.panel_open and not policy.armed,"crossed_arms_open_3d_controls_without_head_or_hips")
    for _i in range(3):sample(policy,down)
    ck(policy.armed,"lower_hands_arms_targets")
    var reach=down.duplicate(true);reach[15]=[.3,.358,.95]
    ck(sample(policy,reach).empty(),"first_reach_sample_only_highlights")
    ck(sample(policy,reach)=="next","second_fresh_reach_activates_next_once")
    var extra=[]
    for _i in range(10):
        var action=sample(policy,reach)
        if not action.empty():extra.append(action)
    ck(extra.empty(),"held_hand_does_not_repeat_commands")
    ck(policy.sample(now,1,frame,now,reach,true).empty(),"replayed_frame_never_activates")
    policy.sample(now+250,1,frame+1,now+500,reach,true)
    ck(not policy.panel_open,"future_timestamp_closes_controls")
    policy.panel_open=true;var weak=reach.duplicate(true);weak[15][2]=.1;sample(policy,weak)
    ck(not policy.panel_open,"lost_wrist_closes_recognition_immediately")
    var avatar=load("res://scripts/AvatarRenderer.gd").new();get_root().add_child(avatar);avatar.set_active(true)
    var body=pose();body[0]=[.5,.22,.95];body[2]=[.46,.14,.95];body[5]=[.54,.14,.95]
    ck(avatar.set_tracked_pose(body,true),"good_body_pose_accepted")
    avatar._process(.25);yield(create_timer(.1),"timeout")
    ck(abs(avatar.head.rotation.x)<.01,"first_valid_face_calibrates_neutral_not_down")
    var before=avatar.viewport_3d.get_texture().get_data().get_data()
    avatar.set_tracked_pose([],false);avatar._process(.25)
    ck(avatar.visible and avatar.modulate.a==1.0 and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"lost_body_keeps_frozen_gpu_frame")
    yield(create_timer(.1),"timeout")
    ck(before==avatar.viewport_3d.get_texture().get_data().get_data(),"held_viewport_pixels_do_not_animate")
    for _i in range(8):avatar._process(.25)
    ck(avatar.modulate.a==0.0 and not avatar.is_processing(),"transparent_ghost_stops_processing")
    avatar.set_tracked_pose(body,true);avatar._process(.05)
    ck(avatar.modulate.a>0 and avatar.modulate.a<1,"tracked_avatar_returns_with_fade")
    var profile=body.duplicate(true);profile[11][0]=.49;profile[12][0]=.51;profile[23][0]=.49;profile[24][0]=.51
    ck(avatar.set_tracked_pose(profile,true) and not avatar.tracking_hold,"calibrated_profile_keeps_body_scale_when_anchors_are_valid")
    var app=load("res://Main.tscn").instance();get_root().add_child(app);yield(create_timer(.2),"timeout");app.set_process(false)
    ck(app.body_control_panel!=null and app.body_control_panel.buttons.size()==5,"actual_3d_panel_scene_initializes")
    ck(app.gesture_mode=="panel" and not app.gesture_policy.enabled,"panel_mode_available_but_gestures_default_off")
    app.body_control_policy.panel_open=true;app.body_control_policy.feedback="Synthetic controls / no media command";app.body_control_panel.sync(app.body_control_policy)
    yield(create_timer(.2),"timeout")
    ck(app.body_control_panel.open and app.body_control_panel.panel_root.visible and app.body_control_panel.view.render_target_update_mode!=Viewport.UPDATE_DISABLED,"3d_control_panel_renders")
    var folder=OS.get_environment("SHIELDAMP_SYNTHETIC_PANEL_OUTPUT")
    if not folder.empty():
        var shot=get_root().get_texture().get_data();shot.flip_y();shot.save_png(folder+"/synthetic-3d-controls.png")
    app._close_body_control_panel();ck(not app.body_control_panel.open,"back_or_close_hides_panel_without_quitting")
    app.queue_free();avatar.queue_free();yield(self,"idle_frame")
    print("TRACKING_PANEL_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
