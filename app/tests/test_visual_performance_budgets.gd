extends SceneTree
class BudgetHero:
    extends "res://scripts/TrackHero.gd"
    var repaints=0
    func _request_repaint():
        repaints+=1
        ._request_repaint()
class RequestFixture:
    extends HTTPRequest
    var calls=0
    var cancellations=0
    func request(_url,_headers=PoolStringArray(),_ssl=true,_method=0,_body=""):
        calls+=1
        return OK
    func cancel_request():cancellations+=1
var failures=[]
func check(ok,label):
    print("VISUAL_BUDGET_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func inject_request(pose):
    pose.request_node.cancel_request();pose.request_node.queue_free()
    var fake=RequestFixture.new();pose.add_child(fake);pose.request_node=fake
    return fake
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    var hero=BudgetHero.new();hero.rect_size=Vector2(700,240);get_root().add_child(hero)
    yield(create_timer(.2),"timeout")
    var pose=app.pose_visual;var ui=app.music_ui
    check(not pose.webcam_timer.is_stopped(),"usb_metadata_detection_remains_running")
    pose.set_webcam_connected(true);pose.set_mode("live")
    var landmarks=load("res://scripts/DanceLibrary.gd").pose(0.5)
    var valid={"enabled":true,"ageMs":0,"landmarks":landmarks}
    check(pose.accept_pose(valid) and pose.tracking_live,"synthetic_live_pose_accepted_before_suspension")
    check(pose.performance_hz==4 and pose._poll_interval_ms()==250,"full_poll_budget_is_four_hz")
    pose.set_performance_budget(2)
    var fake=inject_request(pose)
    var now=OS.get_ticks_msec()
    pose.last_poll=now-450;pose._process(0.0)
    check(fake.calls==0 and pose._poll_interval_ms()==500,"light_poll_budget_does_not_poll_before_half_second")
    pose.last_poll=now-550;pose._process(0.0)
    check(fake.calls==1 and pose.pending,"light_poll_budget_requests_at_half_second")
    var previous_epoch=pose.request_epoch
    pose.set_performance_budget(0)
    check(fake.cancellations==1 and pose.mode=="live" and pose.enabled and pose.performance_suspended and not pose.is_processing() and not pose.pending and pose.points.empty() and not pose.tracking_live,"audio_first_cancels_and_clears_work_while_preserving_live_choice")
    check(ui.body_button.text=="WEBCAM: PAUSED" and pose.status=="PAUSED FOR AUDIO","ui_distinguishes_audio_suspension_from_owner_off")
    var before=pose.poll_attempts;pose._process(1.0)
    check(pose.poll_attempts==before and not pose.accept_pose(valid),"suspended_consumer_cannot_poll_or_accept_direct_pose")
    var body=to_json({"pose":valid}).to_utf8()
    pose._completed(HTTPRequest.RESULT_SUCCESS,200,[],body,previous_epoch)
    check(pose.points.empty() and pose.status=="PAUSED FOR AUDIO","queued_pre_pause_completion_ignored_while_suspended")
    pose.set_performance_budget(2)
    check(pose.mode=="live" and pose.enabled and not pose.performance_suspended and pose.is_processing() and pose.points.empty() and not pose.tracking_live and ui.body_button.text=="WEBCAM: WAITING","restoration_keeps_choice_but_requires_fresh_pose")
    pose.pending=true;pose._completed(HTTPRequest.RESULT_SUCCESS,200,[],body,previous_epoch)
    check(pose.pending and pose.points.empty(),"pre_pause_callback_cannot_overwrite_new_request_after_restore")
    pose._completed(HTTPRequest.RESULT_SUCCESS,200,[],body,pose.request_epoch)
    check(not pose.pending and pose.tracking_live and not pose.points.empty() and ui.body_button.text=="WEBCAM: LIVE","fresh_generation_can_resume_live_pose")
    pose.set_performance_budget(0);ui._toggle_body();pose.set_performance_budget(4)
    check(pose.mode=="off" and not pose.enabled and not pose.is_processing() and ui.body_button.text=="WEBCAM: OFF","owner_off_during_suspension_is_respected_on_restore")
    pose.set_mode("live");pose.set_performance_budget(0);pose.set_webcam_connected(false);pose.set_performance_budget(4)
    check(pose.mode=="off" and not pose.is_processing() and not ui.body_button.visible,"unplug_during_suspension_cannot_auto_resume")
    check(not pose.set_performance_budget(3) and not pose.set_performance_budget("2") and pose.performance_hz==4,"invalid_pose_budget_rejected")
    hero.set_track(load("res://assets/branding/icon_192.png"),"Synthetic title","Synthetic source")
    hero.set_audio_state(true,[0.8,0.4],0.3,false)
    for fps in [10,30]:
        hero.set_render_budget(fps);hero.repaints=0
        for _frame in range(120):
            hero.set_render_budget(fps)
            hero._process(1.0/120.0)
        check(hero.repaints>=fps-1 and hero.repaints<=fps+1,str(fps)+"_hero_repaints_bounded_even_with_repeated_budget_assignment")
    hero.set_render_budget(0);before=hero.repaints;var phase=hero.phase
    hero._process(1.0);hero.set_audio_state(true,[1.0],0.4,false)
    check(not hero.is_processing() and hero.repaints==before and hero.phase==phase and hero.cover!=null and hero.title_label.text=="Synthetic title" and hero.title_label.is_visible_in_tree(),"zero_hero_budget_keeps_static_art_and_title_without_animation_callback")
    check(not hero.set_render_budget(15) and hero.render_budget_fps==0,"unsupported_hero_budget_rejected")
    hero.set_render_budget(10);hero._process(0.1)
    check(hero.is_processing() and hero.repaints==before+1,"hero_animation_resumes_after_audio_first")
    pose.set_mode("off");hero.queue_free();app.queue_free();print("VISUAL_BUDGET_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
