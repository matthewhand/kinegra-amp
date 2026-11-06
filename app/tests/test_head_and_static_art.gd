extends SceneTree
var failures=[]
func check(ok,label):
    print("HEAD_STATIC_ART_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.set_process(false)
    app.pose_visual.webcam_timer.stop();app.pose_visual.set_process(false)
    var points=load("res://scripts/DanceLibrary.gd").pose(0.0)
    for point in points:point[2]=0.0
    points[0]=[.50,.35,.95];points[2]=[.46,.32,.95];points[5]=[.54,.32,.95]
    for _i in range(3):app.pose_visual.accept_pose({"enabled":true,"ageMs":0,"landmarks":points})
    var avatar=app.avatar_visual
    avatar.view_mode=app.pose_visual.view_mode
    check(avatar.view_mode=="face" and avatar.set_pose(app.pose_visual.points) and avatar.head.visible and avatar.scene.visible,"real_face_only_route_keeps_head_without_hips")
    check(not avatar.torso.visible and not avatar.neck.visible,"face_route_does_not_invent_a_body")
    var all_hidden=true
    for part in avatar.segments+avatar.joints:all_hidden=all_hidden and not part.visible
    check(all_hidden,"no_stale_body_meshes_in_head_view")
    avatar._process(1.0)
    check(avatar.camera.translation.distance_to(Vector3(avatar.head.translation.x,avatar.head.translation.y,avatar.camera.translation.z))<.001,"head_center_inside_face_camera")
    yield(create_timer(.2),"timeout")
    var output=OS.get_environment("SHIELDAMP_SYNTHETIC_VISUAL_OUTPUT")
    if not output.empty():
        var head_image=avatar.viewport_3d.get_texture().get_data();head_image.flip_y();head_image.save_png(output+"/synthetic-head-only.png")
    var missing=points.duplicate(true);missing[0][2]=.1
    check(not avatar.set_pose(missing) and not avatar.scene.visible,"weak_face_clears_without_stale_head")
    avatar.view_mode="body"
    check(not avatar.set_pose(points),"body_mode_still_requires_body_anchors")
    avatar.view_mode="face";avatar.set_pose(points);avatar._process(1.0)
    var image=Image.new();image.create(96,96,false,Image.FORMAT_RGB8);image.lock()
    for y in range(96):
        for x in range(96):image.set_pixel(x,y,Color(.10+float(x)/130.0,.25+float(y)/180.0,.6))
    image.unlock();var texture=ImageTexture.new();texture.create_from_image(image)
    var ui=app.music_ui
    ui.set_process(false);ui._apply_artwork(texture)
    ui._set_fullscreen_track("Synthetic buffer preview","Test fixture","DEVELOPMENT")
    app._select_visual_quality(1);app.set_visuals_enabled(false)
    app.reduced_motion.pressed=true
    app.backing_dancers.pressed=false
    ui._enter_fullscreen()
    check(ui.cover_target==1 and ui.fullscreen_art.texture==texture,"visuals_off_fullscreen_shows_current_cover")
    check(not ui.fullscreen_art.is_processing() and ui.track_hero.render_budget_fps==0 and app.visual.material==null,"static_cover_without_animation_fft_or_shader")
    for size in [Vector2(1280,720),Vector2(1280,540),Vector2(720,1280)]:
        OS.window_size=size;app._apply_resolution_base()
        yield(create_timer(.15),"timeout")
        var bounds=ui.fullscreen_art.get_global_rect()
        var visible_size=get_root().get_visible_rect().size
        check(bounds.size.x>0 and bounds.size.y>0 and bounds.position.x>=0 and bounds.position.y>=0 and bounds.end.x<=visible_size.x+1 and bounds.end.y<=visible_size.y+1,"cover_fits_"+str(size))
        check(not bounds.intersects(ui.fullscreen_track_title.get_global_rect()) and not bounds.intersects(ui.fullscreen_help.get_global_rect()),"cover_clear_of_title_and_controls_"+str(size))
        var folder=OS.get_environment("SHIELDAMP_SYNTHETIC_VISUAL_OUTPUT")
        if not folder.empty():
            var shot=get_root().get_texture().get_data();shot.flip_y();shot.save_png(folder+"/static-cover-%dx%d.png"%[size.x,size.y])
    app.set_visuals_enabled(true)
    check(ui.cover_target==0,"full_visuals_restore_compact_card")
    app.stream_warmup_budget.observe(100,{"active":true,"generation":5,"buffering":true,"queued_ms":680})
    app._apply_visual_budget(app.visual_governor.snapshot())
    check(ui.cover_target==1 and ui.cover_morph==1.0,"warmup_shows_cover_without_toggling_user_visuals")
    ui._exit_fullscreen()
    check(not ui.fullscreen_track.visible and ui.player_card.visible,"back_restores_controls")
    app.queue_free();print("HEAD_STATIC_ART_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
