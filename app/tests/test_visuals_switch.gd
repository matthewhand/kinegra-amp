extends SceneTree
class AudioSpy:
    extends Reference
    var active=true
    var stopped=0
    func stop():
        stopped+=1
        active=false
var failures=[]
var prior_config=PoolByteArray()
var had_config=false
func check(ok,label):
    print("VISUAL_SWITCH_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func accept():
    for down in [true,false]:
        var event=InputEventAction.new();event.action="ui_accept";event.pressed=down;Input.parse_input_event(event)
func _init():call_deferred("run")
func run():
    var old=File.new()
    had_config=old.file_exists("user://installation.cfg")
    if had_config:
        old.open("user://installation.cfg",File.READ);prior_config=old.get_buffer(old.get_len());old.close()
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.set_process(false);app.music_ui.set_process(false)
    var ui=app.music_ui
    check(app.visuals_enabled and ui.visuals_button.text=="VISUALS: ON","visuals_default_on_obvious_control")
    var original_local=app.local_pcm;var original_offline=app.offline_music
    var local=AudioSpy.new();var offline=AudioSpy.new();app.local_pcm=local;app.offline_music=offline
    app.analysis_owner=local;var epoch=app.analysis_epoch
    app.visual_governor.set_mode("light",OS.get_ticks_msec());app._apply_visual_budget(app.visual_governor.snapshot())
    app.pose_visual.set_webcam_connected(true);app.pose_visual.set_mode("live")
    app.backing_dancers.pressed=true;app.preset_index=2
    app.set_visuals_enabled(false)
    var gpu_stopped=app.avatar_visual.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED and not app.avatar_visual.is_processing()
    for avatar in app.backing_avatars:gpu_stopped=gpu_stopped and not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED
    check(app.visual.material==null and app.visual_quality_level==0 and gpu_stopped and app.pose_visual.performance_suspended and not app.pose_visual.is_processing() and not ui.track_hero.is_processing(),"off_stops_background_fft_avatar_pose_and_hero_work")
    check(not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0),"off_disables_fft_effect")
    check(app.visual_governor.mode=="light" and app.visual_governor.level==1 and app.backing_dancers.pressed and app.pose_visual.mode=="live" and app.preset_index==2,"off_preserves_quality_scene_webcam_and_cast_preferences")
    app.set_visuals_enabled(true)
    check(app.visual_quality_level==1 and app.visual.material==app.light_shader_material and app.pose_visual.performance_hz==2,"on_restores_selected_light_quality")
    app.set_visuals_enabled(false);app.pose_visual.set_mode("off");app.visual_governor.set_mode("auto",OS.get_ticks_msec());app.visual_governor.level=0;app.set_visuals_enabled(true)
    check(app.visual_quality_level==0 and app.visual_governor.mode=="auto" and app.pose_visual.mode=="off","on_respects_current_unsafe_auto_level_and_owner_webcam_off")
    check(local.active and offline.active and local.stopped==0 and offline.stopped==0 and app.analysis_owner==local and app.analysis_epoch==epoch,"visual_switch_never_stops_or_reassigns_audio")
    app.local_pcm=original_local;app.offline_music=original_offline;app.analysis_owner=null
    app.visual_governor.set_mode("full",OS.get_ticks_msec());app._apply_visual_budget(app.visual_governor.snapshot())
    check(not ui.sensitivity_button.visible and app.music_reactivity_choice!=null,"music_reactivity_moved_out_of_main_controls")
    app._select_music_reactivity(2);check(app.sensitivity_index==2 and app.music_reactivity_choice.selected==2,"settings_controls_existing_fft_reactivity_value")
    app.pose_visual.webcam_timer.stop();app.pose_visual.set_webcam_connected(true);ui._sync_transport()
    check(not ui.avatar_button.visible,"avatar_style_hidden_when_webcam_choice_off")
    app.pose_visual.set_mode("live");ui._sync_transport();check(ui.avatar_button.visible,"avatar_style_available_for_connected_live_webcam")
    ui.avatar_button.grab_focus();app.pose_visual.set_mode("off");ui._sync_transport()
    check(not ui.avatar_button.visible and ui.body_button.has_focus(),"hiding_avatar_style_moves_focus_to_webcam_control")
    for size in [Vector2(480,800),Vector2(720,1280),Vector2(960,720),Vector2(1280,720),Vector2(1720,720)]:
        OS.window_size=size;app._apply_resolution_base();yield(create_timer(.15),"timeout")
        for large in [false,true]:
            ui.set_tv_text_mode(large);yield(create_timer(.05),"timeout");ui._fit_stage_button_labels()
            var ok=true
            for button in [ui.library_button,ui.offline_button,ui.queue_button,ui.fullscreen_button,ui.visuals_button,ui.settings_button]:
                var font=button.get_font("font");var padding=button.get_stylebox("normal").get_minimum_size().x
                ok=ok and button.is_visible_in_tree() and ui.root.get_global_rect().encloses(button.get_global_rect()) and ui.header_card.get_global_rect().encloses(button.get_global_rect()) and font.get_string_size(button.text).x+padding<=button.rect_size.x+1
            check(ok,str(size)+("_large" if large else "_normal")+"_main_actions_visible_and_readable")
            ui.visuals_button.grab_focus();var before=app.visuals_enabled;accept();yield(create_timer(.05),"timeout")
            check(ui.visuals_button.has_focus() and app.visuals_enabled!=before,str(size)+("_large" if large else "_normal")+"_remote_accept_toggles_without_losing_focus")
    app.visual_governor.set_mode("light",OS.get_ticks_msec());app.set_visuals_enabled(false);app._select_music_reactivity(2);app._save_setup()
    var saved=ConfigFile.new();saved.load("user://installation.cfg")
    check(saved.get_value("installation","visuals_enabled",true)==false and saved.get_value("installation","music_reactivity",-1)==2 and saved.get_value("installation","visual_quality","")=="light","existing_save_setup_persists_visual_and_reactivity_preferences")
    app.queue_free();yield(self,"idle_frame")
    var restored=load("res://Main.tscn").instance();get_root().add_child(restored);yield(create_timer(.2),"timeout")
    check(not restored.visuals_enabled and restored.visual_quality_level==0 and restored.visual_governor.mode=="light" and restored.sensitivity_index==2,"saved_off_and_quality_choices_restore_without_audio_start")
    restored.queue_free()
    if had_config:
        var restored_file=File.new();restored_file.open("user://installation.cfg",File.WRITE);restored_file.store_buffer(prior_config);restored_file.close()
    else:Directory.new().remove("user://installation.cfg")
    print("VISUAL_SWITCH_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
