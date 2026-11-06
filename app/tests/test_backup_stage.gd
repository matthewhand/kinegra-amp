extends SceneTree
class TempoFixture:
    extends Reference
    var live=false
    func reset():live=false
    func observe(_now,_bands,source,_epoch):live=source
    func snapshot(now):
        return {"kind":"estimated_onsets" if live else "none","bpm":170.0,"phase":fposmod(float(now)*170.0/60000.0,1.0),"confidence":1.0 if live else 0.0,"family":"fast","signal":live}
var failures=[]
func check(ok,label):
    print("BACKUP_STAGE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func distinct(app):
    return app.backing_avatars[0].mode!=app.avatar_visual.mode and app.backing_avatars[1].mode!=app.avatar_visual.mode and app.backing_avatars[0].mode!=app.backing_avatars[1].mode
func _init():call_deferred("run")
func run():
    AudioServer.set_bus_mute(0,true)
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.3),"timeout")
    app.set_process(false)
    app.backing_dancers.pressed=true;app._set_backing_dancers(true)
    for style in app.avatar_visual.STYLES:
        app.avatar_visual.set_style(style)
        check(distinct(app),"lead_change_immediately_recasts_"+style)
    app._update_visuals(.1)
    check(app.backing_avatars[0].last_points.empty() and app.backing_avatars[1].last_points.empty(),"no_pcm_keeps_backups_idle")
    # Controlled analysis fixture exercises Main's real-audio source gate and
    # choreography wiring; actual tempo detection is covered separately.
    app.backup_tempo=TempoFixture.new()
    app._play_offline_music();yield(create_timer(.05),"timeout")
    for _i in range(20):app._update_visuals(.05)
    check(app.backup_choreography.family=="fast" and app.backup_choreography.kind=="estimated_onsets" and app.backing_avatars[0].last_points.size()==33 and app.backing_avatars[1].last_points.size()==33,"actual_source_gate_consumes_estimated_tempo")
    check(app.backing_avatars[0].last_points[15]!=app.backing_avatars[1].last_points[15],"backups_use_different_phase_and_moves")
    app.pose_visual.enabled=true;app.pose_visual.tracking_live=true
    app.pose_visual.points=load("res://scripts/DanceLibrary.gd").pose(0.0)
    for framing in ["body","portrait","face","body"]:
        app.pose_visual.view_mode=framing;app._update_visuals(.05)
        check(app.avatar_visual.view_mode==framing and app.backing_avatars[0].view_mode==framing and app.backing_avatars[1].view_mode==framing,"shared_view_mode_"+framing)
    app._set_backing_dancers(false);app._set_backing_dancers(true)
    check(app.backing_avatars[0].view_mode==app.avatar_visual.view_mode and app.backing_avatars[1].view_mode==app.avatar_visual.view_mode,"later_enabled_backups_keep_shared_framing")
    app._update_visuals(.05)
    var before=app.backing_avatars[0].last_points.duplicate(true)
    app.reduced_motion.pressed=true;app._update_visuals(.1)
    check(app.backing_avatars[0].last_points==before,"reduced_motion_keeps_static_backup_pose")
    app.offline_music.stop();app._update_visuals(.1)
    check(app.backing_avatars[0].last_points.empty() and app.backing_avatars[1].last_points.empty(),"stopped_audio_clears_both_poses")
    app.visual_quality_level=0;app._set_backing_dancers(true);app._update_visuals(.1)
    check(not app.backing_avatars[0].is_processing() and app.backing_avatars[0].viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED and app.backing_dancers.pressed,"visual_off_preserves_preference_without_rendering")
    app.queue_free()
    print("BACKUP_STAGE_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
