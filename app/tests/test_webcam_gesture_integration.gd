extends SceneTree
class RootSpy:
    extends "res://scripts/Main.gd"
    var commands=[]
    var ready_route=true
    func _queue_controls_available():return ready_route
    func _sendspin_controls():return {"paired":true}
    func _sendspin_fresh():return false
    func _play_music_assistant():
        _sendspin_command("play")
        return true
    func _sendspin_command(command,_value=null):commands.append(command)
var failures=[]
var checks=0
var prior_config=PoolByteArray()
var had_config=false
func check(ok,label):
    checks+=1;print("GESTURE_MAIN_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func context(ui,value):
    # Support the isolated pre-context task base and the parent's typed-context
    # integration; production gesture routing only calls the existing buttons.
    if ui.has_method("set_playback_context"):ui.set_playback_context(value)
    else:ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE" if value=="ma" else "OFFLINE MUSIC  •  GENERIC LOCAL FIXTURE"
func _init():call_deferred("run")
func run():
    var old=File.new();had_config=old.file_exists("user://installation.cfg")
    if had_config:
        old.open("user://installation.cfg",File.READ);prior_config=old.get_buffer(old.get_len());old.close()
    AudioServer.set_bus_mute(0,true)
    var app=RootSpy.new();get_root().add_child(app)
    yield(create_timer(.3),"timeout")
    app.set_process(false);app.music_ui.set_process(false)
    app.pose_visual.webcam_timer.stop();app.pose_visual.set_process(false)
    var ui=app.music_ui
    check(not app.gesture_policy.enabled and not app.webcam_gestures.pressed and app.commands.empty() and not app.offline_music.is_playing(),"default_off_no_playback_or_commands")
    app.pose_visual.set_webcam_connected(true);app.pose_visual.set_mode("live");app.pose_visual.set_process(false)
    app._set_gesture_mode(1)
    app._set_webcam_gestures(true)
    check(app.commands.empty() and not app.offline_music.is_playing() and not app.gesture_policy.armed,"enable_does_not_arm_or_play")
    check(ui.gesture_cues[ui.next_button].visible and ui.gesture_cues[ui.previous_button].visible and ui.gesture_cues[ui.play_button].visible and ui.gesture_cues[ui.tv_pause_button].visible and not ui.gesture_cues[ui.stop_button].visible,"configured_cues_only_next_to_assigned_controls")
    check(ui.gesture_cues[ui.next_button].focus_mode==Control.FOCUS_NONE and ui.gesture_cues[ui.next_button].hint_tooltip.find("three direction changes")>=0,"reminders_have_recipe_without_focus_target")
    var next_binding=app.gesture_policy.bindings.next
    check(not app._select_gesture_binding(app.gesture_policy.GESTURES.find(next_binding),"previous") and app.gesture_policy.bindings.previous=="left_wave","duplicate_ui_binding_rejected")
    app._select_gesture_binding(0,"previous")
    check(not ui.gesture_cues[ui.previous_button].visible and ui.gesture_cues[ui.next_button].visible,"unassigned_hides_only_its_cue")
    check(app._gesture_context_allowed(),"player_context_allows_deliberate_gesture")
    app.page_scroller.show()
    check(not app._gesture_context_allowed() and not app._perform_gesture_action("next"),"settings_menu_blocks_commands")
    app.page_scroller.hide();ui.queue_drawer.show()
    check(not app._gesture_context_allowed(),"queue_drawer_blocks_recognition")
    ui.queue_drawer.hide();ui.ma_drawer.show();app.ma_panel.show()
    check(not app._gesture_context_allowed(),"library_and_pairing_blocks_recognition")
    app.ma_panel.hide();ui.ma_drawer.hide();ui.tv_clear_dialog.popup_centered()
    check(not app._gesture_context_allowed(),"confirmation_popup_blocks_recognition")
    ui.tv_clear_dialog.hide()
    context(ui,"ma")
    ui._sync_transport()
    check(app._perform_gesture_action("next") and app._perform_gesture_action("previous") and app.commands==["next","previous"],"commands_share_own_tv_button_routes")
    app.tv_queue_state="paused";ui._sync_transport();app._perform_gesture_action("play_pause")
    app.tv_queue_state="playing";ui._sync_transport();app._perform_gesture_action("play_pause")
    check(app.commands==["next","previous","play","pause"],"deliberate_play_pause_uses_existing_tv_callbacks")
    app.ready_route=false;ui._sync_transport()
    check(not app._perform_gesture_action("next") and app.commands.size()==4,"unavailable_tv_route_never_redirects_player")
    app.ready_route=true
    context(ui,"offline");ui._sync_transport()
    check(app._perform_gesture_action("play_pause") and app.offline_music.is_playing(),"offline_play_uses_existing_local_callback")
    ui._sync_transport();app._perform_gesture_action("play_pause")
    check(not app.offline_music.is_playing() and app.commands.size()==4,"offline_pause_does_not_contact_tv_route")
    app.set_visuals_enabled(false);app._refresh_pose_control_budget()
    check(app.pose_visual.performance_hz==4 and not app.pose_visual.performance_suspended and app.avatar_visual.render_budget_fps==0 and app.visual.material==null and not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0),"explicit_gestures_keep_only_pose_poll_when_visuals_off")
    app._set_webcam_gestures(false)
    check(app.pose_visual.performance_suspended and not ui.gesture_cues[ui.next_button].visible and not ui.gesture_fullscreen_feedback.visible,"disabled_clears_hints_and_resuspends_visual_off_poll")
    app._set_webcam_gestures(true);ui._enter_fullscreen();app._update_gesture_feedback()
    check(app._gesture_context_allowed() and ui.gesture_fullscreen_feedback.visible,"fullscreen_keeps_gestures_and_nonintrusive_feedback")
    ui._exit_fullscreen()
    app.app_has_focus=false;app.gesture_policy.armed=true;app.gesture_policy.tick(OS.get_ticks_msec(),app._gesture_context_allowed())
    check(not app.gesture_policy.armed and not app._perform_gesture_action("next"),"background_cancels_and_blocks_commands")
    app.app_has_focus=true
    for size in [Vector2(480,800),Vector2(720,1280),Vector2(960,720),Vector2(1280,720),Vector2(1720,720)]:
        OS.window_size=size;app._apply_resolution_base();yield(create_timer(.15),"timeout")
        for large in [false,true]:
            ui.set_tv_text_mode(large)
            # This fixture froze ui._process above. Run its normal responsive
            # transport sync explicitly after resize before measuring controls.
            ui._sync_transport()
            yield(create_timer(.05),"timeout")
            ui._fit_stage_button_labels();app._update_gesture_feedback()
            var within=true
            for button in [ui.play_button,ui.previous_button,ui.tv_pause_button,ui.next_button,ui.stop_button,ui.rewind_button,ui.forward_button]:
                if not ui.root.get_global_rect().encloses(button.get_global_rect()) or button.rect_size.x<=40:print("GESTURE_BOUNDS_CONTROL ",button.text," rect=",button.get_global_rect()," root=",ui.root.get_global_rect())
                within=within and ui.root.get_global_rect().encloses(button.get_global_rect()) and button.rect_size.x>40
                if ui.gesture_cues.has(button):
                    var cue=ui.gesture_cues[button]
                    if cue.visible:
                        if not ui.root.get_global_rect().encloses(cue.get_global_rect()):print("GESTURE_BOUNDS_CUE ",button.text," rect=",cue.get_global_rect()," root=",ui.root.get_global_rect())
                        within=within and ui.root.get_global_rect().encloses(cue.get_global_rect())
            check(within,str(size)+("_large" if large else "_normal")+"_transport_and_cues_in_bounds")
            var images=OS.get_environment("SHIELDAMP_GESTURE_IMAGES")
            if not images.empty() and not large and size in [Vector2(480,800),Vector2(1280,720)]:
                var image=get_root().get_texture().get_data();image.flip_y();image.save_png(images+"/gesture_"+str(int(size.x))+".png")
    app.pose_visual.set_webcam_connected(false);app._update_gesture_feedback()
    check(not app._gesture_context_allowed() and not ui.gesture_cues[ui.next_button].visible,"camera_loss_hides_cues_and_blocks")
    var config=ConfigFile.new();config.set_value("installation","webcam_gestures_enabled",true);config.set_value("installation","webcam_gesture_bindings",{"previous":"head_shake","play_pause":"both_hold","next":"right_hold"})
    app._restore_gesture_setup(config)
    check(app.gesture_policy.enabled and app.gesture_policy.bindings.previous=="head_shake" and not app.gesture_policy.armed,"saved_setup_restores_bindings_without_arming")
    app._save_setup()
    var saved=ConfigFile.new();saved.load("user://installation.cfg")
    check(saved.get_value("installation","webcam_gestures_enabled",false)==true and saved.get_value("installation","webcam_gesture_bindings",{}).get("previous","")=="head_shake","save_setup_persists_only_enabled_and_enum_bindings")
    config.set_value("installation","webcam_gesture_bindings",{"previous":"right_hold","play_pause":"both_hold","next":"right_hold"});app._restore_gesture_setup(config)
    check(not app.gesture_policy.enabled,"invalid_saved_bindings_fail_closed_off")
    if had_config:
        old.open("user://installation.cfg",File.WRITE);old.store_buffer(prior_config);old.close()
    else:Directory.new().remove("user://installation.cfg")
    app.queue_free();yield(create_timer(.05),"timeout")
    print("GESTURE_MAIN_CHECKS=",checks," FAILURES=",failures.size());quit(0 if failures.empty() else 1)
