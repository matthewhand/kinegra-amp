extends SceneTree
var failed=[]
func ck(ok,label):
    print("AVATAR_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failed.append(label)
func _init(): call_deferred("run")
func run():
    var avatar=load("res://scripts/AvatarRenderer.gd").new()
    get_root().add_child(avatar)
    yield(self,"idle_frame")
    ck(not avatar.active and not avatar.visible,"off_by_default")
    ck(not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"default_no_hidden_render_or_frame_callback")
    ck(avatar.picture.flip_v,"viewport_texture_upright")
    ck(avatar.set_style("sunset") and not avatar.set_style("unknown"),"style_validation")
    avatar.set_visual_context(1,0.8,0.4,0.2,false)
    ck(avatar.body_material.get_shader_param("scene_preset")==1.0 and abs(avatar.body_material.get_shader_param("bass")-0.8)<0.001 and avatar.body_material.get_shader_param("motion")==0.0,"scene_audio_and_comfort_reach_material")
    ck(avatar.joint_material.get_shader_param("scene_preset")==1.0,"joints_share_scene")
    avatar.set_active(true)
    ck(not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"enabled_without_pose_stays_idle")
    var points=load("res://scripts/DanceLibrary.gd").pose(0.0)
    ck(avatar.set_pose(points) and avatar.scene.visible,"valid_pose_renders")
    ck(avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_ALWAYS,"valid_pose_restarts_rendering")
    ck(avatar.segments[0].visible and avatar.head.visible,"body_and_head_visible")
    ck(avatar.head.mesh is CubeMesh and avatar.torso.mesh is CubeMesh and avatar.segments[1].mesh is CubeMesh,"block_character_geometry")
    ck(avatar.face_details.size()==3 and avatar.face_details[0].get_parent()==avatar.head,"face_follows_head")
    points[2]=[0.4,0.2,1.0]
    points[5]=[0.6,0.25,1.0]
    avatar.set_pose(points)
    ck(abs(avatar.head.rotation.z)>0.1,"eye_line_rotates_head")
    avatar.view_mode="face"
    avatar._process(0.25)
    ck(abs(avatar.camera.size-1.35)<0.01,"face_view_zoom")
    avatar.view_mode="portrait"
    avatar._process(0.25)
    ck(abs(avatar.camera.size-2.7)<0.01,"portrait_view_zoom")
    avatar.view_mode="body"
    avatar._process(0.25)
    ck(abs(avatar.camera.size-4.5)<0.01,"body_view_restored")
    points[2][2]=0.0
    avatar.set_pose(points)
    ck(abs(avatar.head.rotation.z)<0.001,"missing_eye_resets_tilt")
    points[11][2]=0.0
    avatar.set_pose(points)
    ck(not avatar.scene.visible and not avatar.head.is_visible_in_tree(),"missing_body_anchor_hides_incomplete_character")
    ck(not avatar.set_pose([]) and not avatar.scene.visible,"missing_pose_clears")
    ck(not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"missing_pose_stops_gpu_and_callback")
    points[11][2]=1.0
    avatar.set_pose(points)
    ck(avatar.is_processing(),"fresh_pose_recovers_after_idle")
    var invalid=points.duplicate(true);invalid[0]=[NAN,0.5,1.0]
    ck(not avatar.set_pose(invalid) and not avatar.is_processing() and avatar.last_points.empty(),"invalid_pose_cannot_keep_old_render_alive")
    avatar.set_active(false)
    ck(not avatar.visible and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"inactive_no_render")
    print("AVATAR_FAILURES=",failed.size())
    quit(0 if failed.empty() else 1)
