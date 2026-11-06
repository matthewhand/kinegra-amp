extends SceneTree
var failures=[]
var checks=0
func check(ok,label):
    checks+=1;print("SURFACE_FRAMING_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var avatars=[]
    for slot in range(3):
        var avatar=load("res://scripts/AvatarRenderer.gd").new();avatar.render_size=256
        get_root().add_child(avatar);avatar.set_active(true);avatar.set_visual_context(0,0,0,0,false)
        var points=load("res://scripts/DanceLibrary.gd").pose(0.0)
        if slot==1:
            for point in points:
                if point[2]>=.5:
                    point[0]=.5+(point[0]-.5)*.8
                    point[1]=.5+(point[1]-.5)*.8+.12
        if slot==2:
            for point in points:
                if point[2]>=.5:point[0]+=.12
        avatar.set_pose(points);avatars.append(avatar)
    for mode in ["body","portrait","face","body"]:
        for avatar in avatars:
            avatar.view_mode=mode
            avatar._process(1.0)
        var target=4.5 if mode=="body" else (2.7 if mode=="portrait" else 1.35)
        var correct=true
        for avatar in avatars:
            correct=correct and abs(avatar.camera.size/(avatar.body_unit/.64)-target)<.001
            if mode!="body":
                var offset=(avatar.head.translation.y-avatar.camera.translation.y)/(avatar.body_unit/.64)
                correct=correct and abs(offset-(.45 if mode=="portrait" else 0.0))<.001
        check(correct,"same_normalized_zoom_and_crop_"+mode)
        check(avatars[0].camera.translation.x!=avatars[2].camera.translation.x,"own_pose_origin_preserved_"+mode)
    var avatar=avatars[0]
    var fingerprints=[]
    for style in avatar.STYLES:
        avatar.set_style(style);avatar.set_visual_context(0,0,0,0,false);avatar._process(1.0)
        yield(create_timer(.12),"timeout")
        var pixels=avatar.viewport_3d.get_texture().get_data().get_data()
        var fingerprint=hash(pixels)
        check(not fingerprint in fingerprints,"distinct_rendered_surface_"+style);fingerprints.append(fingerprint)
        check(avatar.head.visible and avatar.neck.visible and avatar.body_material.get_shader_param("surface_style")==float(avatar.STYLES.find(style)),"style_keeps_head_neck_and_material_contract_"+style)
        yield(create_timer(.12),"timeout")
        check(pixels==avatar.viewport_3d.get_texture().get_data().get_data(),"reduced_motion_surface_is_static_"+style)
    avatar.set_render_budget(0)
    check(not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"zero_budget_no_surface_rendering")
    for item in avatars:item.queue_free()
    print("SURFACE_FRAMING_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
