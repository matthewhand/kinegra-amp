extends SceneTree
class BudgetAvatar:
    extends "res://scripts/AvatarRenderer.gd"
    var requested_frames=0
    func _request_budget_frame():
        requested_frames+=1
        ._request_budget_frame()
var failures=[]
func check(ok,label):
    print("AVATAR_BUDGET_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var avatar=BudgetAvatar.new();get_root().add_child(avatar)
    yield(self,"idle_frame")
    var points=load("res://scripts/DanceLibrary.gd").pose(0.0)
    avatar.set_active(true);avatar.set_pose(points)
    check(avatar.render_budget_fps==60 and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_ALWAYS,"full_budget_preserves_default_rendering")
    for fps in [15,30]:
        avatar.set_render_budget(fps);avatar.requested_frames=0
        var all_once=true
        for _frame in range(120):
            # Incoming pose updates must not bypass the render cadence.
            avatar.set_pose(points)
            avatar._process(1.0/120.0)
            if avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_ALWAYS:all_once=false
            avatar.viewport_3d.render_target_update_mode=Viewport.UPDATE_DISABLED
        check(avatar.requested_frames>=fps-1 and avatar.requested_frames<=fps+1 and all_once,str(fps)+"_bounded_once_requests_under_120hz_pose_updates")
    var retained=avatar.last_points.duplicate(true)
    avatar.set_render_budget(0)
    check(avatar.active and avatar.last_points==retained and not avatar.visible and not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"zero_budget_stops_gpu_and_callback_without_losing_pose_or_activation")
    var before=avatar.requested_frames
    avatar._process(1.0)
    check(avatar.requested_frames==before,"zero_budget_never_requests_a_frame")
    avatar.set_render_budget(15);avatar._process(1.0/15.0)
    check(avatar.active and avatar.last_points==retained and avatar.visible and avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_ONCE,"restored_budget_recovers_existing_pose")
    before=avatar.requested_frames;avatar._process(5.0)
    check(avatar.requested_frames==before+1,"long_frame_requests_once_without_catchup_burst")
    check(not avatar.set_render_budget(20) and not avatar.set_render_budget("30") and avatar.render_budget_fps==15,"invalid_budget_does_not_change_quality")
    avatar.set_render_budget(0);avatar.set_active(false);avatar.set_render_budget(60)
    check(not avatar.active and avatar.last_points.empty() and not avatar.visible and not avatar.is_processing(),"explicit_off_still_clears_and_cannot_be_restored_by_budget")
    avatar.set_active(true);avatar.set_render_budget(30);avatar.set_pose([])
    check(not avatar.visible and not avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_DISABLED,"empty_pose_stays_idle_at_limited_budget")
    avatar.set_pose(points);avatar.set_render_budget(60)
    check(avatar.is_processing() and avatar.viewport_3d.render_target_update_mode==Viewport.UPDATE_ALWAYS,"full_budget_restored_after_limited_mode")
    avatar.queue_free();print("AVATAR_BUDGET_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
