extends SceneTree
# New settings must be actually focusable and fully visible after automatic scroll.
var failures=[]
var checks=0
func check(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        print("SETTINGS_REACH_FAIL_",label)
func key_press(code):
    for down in [true,false]:
        var event=InputEventKey.new()
        event.scancode=code;event.pressed=down
        Input.parse_input_event(event)
func _init():call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    app.set_visuals_enabled(false)
    var ui=app.music_ui
    ui._advanced()
    for size in [Vector2(480,800),Vector2(720,1280),Vector2(960,720),Vector2(1280,720),Vector2(1720,720)]:
        OS.window_size=size;app._apply_resolution_base()
        yield(create_timer(.1),"timeout")
        for large in [false,true]:
            app.large_text.set_pressed_no_signal(large)
            app._set_large_text(large)
            yield(create_timer(.1),"timeout")
            for pair in [["webcam_gestures",app.webcam_gestures],["previous_gesture",app.gesture_choices.previous],["play_pause_gesture",app.gesture_choices.play_pause],["next_gesture",app.gesture_choices.next],["visual_quality",app.visual_quality_choice],["music_reactivity",app.music_reactivity_choice]]:
                var control=pair[1]
                control.grab_focus()
                yield(create_timer(.08),"timeout")
                var label=str(size)+("_large" if large else "_normal")+"_"+pair[0]
                var bounded=app.page_scroller.get_global_rect().encloses(control.get_global_rect())
                var ancestor=control.get_parent()
                while ancestor!=null:
                    if ancestor is ScrollContainer:bounded=bounded and ancestor.get_global_rect().encloses(control.get_global_rect())
                    ancestor=ancestor.get_parent()
                if not bounded:print("SETTINGS_REACH_RECT=",label," control=",control.get_global_rect()," viewport=",app.page_scroller.get_global_rect())
                check(control.has_focus() and control.is_visible_in_tree() and bounded,label)
    OS.window_size=Vector2(480,800);app._apply_resolution_base()
    app.large_text.set_pressed_no_signal(true);app._set_large_text(true)
    yield(create_timer(.1),"timeout")
    app.webcam_gestures.grab_focus()
    yield(create_timer(.1),"timeout")
    key_press(KEY_ENTER)
    yield(create_timer(.05),"timeout")
    check(app.gesture_policy.enabled and app.webcam_gestures.pressed,"enter_activates_reachable_gesture_checkbox")
    key_press(KEY_ENTER)
    yield(create_timer(.05),"timeout")
    check(not app.gesture_policy.enabled and not app.webcam_gestures.pressed,"enter_can_disable_same_checkbox")
    app._select_music_reactivity(0)
    app.music_reactivity_choice.grab_focus()
    yield(create_timer(.1),"timeout")
    key_press(KEY_ENTER)
    yield(create_timer(.05),"timeout")
    check(app.music_reactivity_choice.get_popup().visible,"enter_opens_reactivity_choices")
    key_press(KEY_DOWN);key_press(KEY_ENTER)
    yield(create_timer(.1),"timeout")
    check(app.sensitivity_index==1 and not app.music_reactivity_choice.get_popup().visible,"remote_selection_changes_actual_reactivity")
    check(app.music_reactivity_choice.hint_tooltip==app.music_reactivity_choice.get_item_text(1),"choice_tooltip_retains_complete_selected_label")
    app.visual_quality_choice.select(0);app._select_visual_quality(0)
    app.visual_quality_choice.grab_focus()
    yield(create_timer(.1),"timeout")
    key_press(KEY_ENTER)
    yield(create_timer(.05),"timeout")
    check(app.visual_quality_choice.get_popup().visible,"enter_opens_quality_choices")
    key_press(KEY_DOWN);key_press(KEY_ENTER)
    yield(create_timer(.1),"timeout")
    check(app.visual_governor.mode=="full" and not app.visuals_enabled and app.visual_quality_level==0,"remote_quality_choice_preserved_with_visuals_off_override")
    check(not app.offline_music.is_playing() and app.sendspin_facade==null and app.pose_visual.mode=="off","settings_activation_never_starts_audio_or_camera")
    app._set_webcam_gestures(false)
    app.free()
    print("SETTINGS_REACH_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
