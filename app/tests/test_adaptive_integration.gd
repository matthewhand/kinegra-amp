extends SceneTree
var failures=[]
class LoadPlugin:
    extends Reference
    var cpu=1000
    var heat=0
    func processCpuTimeMs():return cpu
    func thermalStatus():return heat
func check(ok,label):
    print("ADAPTIVE_MAIN_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.backing_dancers.pressed=true;app._set_backing_dancers(true)
    var pose=load("res://scripts/DanceLibrary.gd").pose(1.0)
    app.avatar_visual.set_pose(pose)
    app._select_visual_quality(2)
    check(app.visual_quality_level==1 and app.visual.material==app.light_shader_material,"light_uses_cheap_material")
    check(app.avatar_visual.render_budget_fps==15 and app.backing_avatars[0].render_budget_fps==0 and app.backing_dancers.pressed,"light_suspends_backing_without_changing_choice")
    check(app.pose_visual.performance_hz==2 and app.music_ui.track_hero.render_budget_fps==10,"light_limits_pose_and_cover_updates")
    app._select_visual_quality(3)
    check(app.visual.material==null and app.avatar_visual.render_budget_fps==0,"audio_first_no_background_shader_or_avatar")
    check(not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0),"audio_first_stops_unused_fft_effect")
    check(app.pose_visual.performance_suspended and not app.pose_visual.is_processing() and not app.music_ui.track_hero.is_processing(),"audio_first_stops_tracking_and_hero_frame_work")
    check(app.offline_music!=null and not app.offline_music.is_playing(),"quality_does_not_start_music")
    app._select_visual_quality(1)
    check(app.visual.material==app.shader_material and app.backing_avatars[0].render_budget_fps==30 and app.backing_dancers.pressed,"full_restores_original_choices")
    check(AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0),"full_restores_fft_effect")
    check(app.avatar_visual.last_points.empty(),"restore_waits_for_fresh_primary_pose")
    var plugin=LoadPlugin.new();app.cpu_sample_at=-1
    app._sample_app_load(plugin,1000);plugin.cpu=1400;app._sample_app_load(plugin,2000)
    check(abs(app.app_cpu_percent-40.0/float(max(1,OS.get_processor_count())))<.01,"cpu_is_app_share_of_reported_cores")
    plugin.cpu="1800";app._sample_app_load(plugin,3000)
    check(abs(app.app_cpu_percent-40.0/float(max(1,OS.get_processor_count())))<.01,"decimal_string_counter_crosses_jni_without_precision_loss")
    plugin.cpu="not available";plugin.heat=99;app._sample_app_load(plugin,4000)
    check(app.app_cpu_percent<0 and app.thermal_status==-1,"invalid_platform_metrics_are_unavailable")
    app._sample_app_load(null,5000)
    check(app.app_cpu_percent<0,"unsupported_metrics_not_zero_idle")
    app.queue_free();print("ADAPTIVE_MAIN_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
