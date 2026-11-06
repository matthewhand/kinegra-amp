extends SceneTree
class JNISingletonFixture:
    extends Reference
    var value=true
    var calls=0
    func has_method(_method):return false
    func hasUsbWebcam():
        calls+=1
        return value
var failures=[]
func check(ok,label):
    print("WEBCAM_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    var pose=app.pose_visual;var ui=app.music_ui
    check(not ui.body_button.visible and pose.mode=="off" and not pose.is_processing(),"absent_hidden_and_idle")
    var platform=JNISingletonFixture.new()
    check(not platform.has_method("hasUsbWebcam") and pose._platform_webcam_connected(platform) and platform.calls==1,"jni_dispatch_does_not_depend_on_method_advertisement")
    for invalid in [1,"true",null]:
        platform.value=invalid
        check(not pose._platform_webcam_connected(platform),"jni_non_boolean_rejected_"+str(typeof(invalid)))
    platform.value=false
    check(not pose._platform_webcam_connected(platform) and not pose._platform_webcam_connected(null),"jni_absent_and_null_fail_closed")
    ui._toggle_body();check(pose.mode=="off","absent_cannot_start")
    pose.set_webcam_connected(true)
    check(ui.body_button.visible and ui.body_button.text=="WEBCAM: OFF","plug_shows_named_control")
    ui._toggle_body();check(pose.mode=="live" and pose.is_processing() and ui.body_button.text=="WEBCAM: WAITING","enable_starts_pose_consumer")
    ui._toggle_body();check(pose.mode=="off" and not pose.is_processing() and not pose.pending,"off_stops_processing_and_requests")
    ui._toggle_body();pose.set_webcam_connected(false)
    check(not ui.body_button.visible and pose.mode=="off" and not pose.is_processing(),"unplug_hides_and_stops")
    ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    ui.show_tv_queue_snapshot({"current":"Track B","next":"Track B","current_id":"b","next_id":"b"})
    check(ui.now_title.text=="Track B" and ui.tv_queue_label.text=="NEXT: NONE REPORTED","current_not_duplicated_as_next")
    ui.show_tv_queue_snapshot({"current":"Track B","next":"Track C","current_id":"b","next_id":"c"})
    check(ui.now_title.text=="Track B" and ui.tv_queue_label.text=="NEXT: Track C","current_and_next_kept_distinct")
    app.queue_free();print("WEBCAM_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
