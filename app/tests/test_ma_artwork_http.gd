extends SceneTree
var received=[]
var textures=[]
var failures=[]
var controller=null
var auth_failures=0
func auth_failed():auth_failures+=1
func check(ok,label):
    print("ARTWORK_HTTP_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func done(context,texture):
    received.append(context)
    textures.append(texture)
func await_result(previous):
    var start=OS.get_ticks_msec()
    while received.size()==previous and OS.get_ticks_msec()-start<6500:
        yield(create_timer(.02),"timeout")
func _init():call_deferred("run")
func run():
    controller=load("res://scripts/MAArtworkController.gd").new();get_root().add_child(controller)
    controller.connect("artwork_ready",self,"done")
    controller.connect("authorization_failed",self,"auth_failed")
    var origin=OS.get_environment("ARTWORK_TEST_ORIGIN")
    check(controller.configure(origin,"fictional-artwork-credential",true,1),"configured_loopback")
    controller.select({"proxy_id":"a".repeat(64)},"cover")
    yield(await_result(0),"completed")
    check(received.size()==1 and textures[0]!=null and textures[0].get_width()==64,"genuine_png_loaded_in_ram")
    var before=received.size()
    controller.select({"proxy_id":"a".repeat(64)},"cached")
    check(received.size()==before+1 and textures.back()==textures[0],"same_session_ram_cache")
    for id in ["b","c","d","e"]:
        before=received.size()
        controller.select({"proxy_id":id.repeat(64)},"reject-"+id)
        yield(await_result(before),"completed")
        check(received.size()==before+1 and textures.back()==null,"unsafe_reply_falls_back_"+id)
    before=received.size()
    controller.select({"proxy_id":"f".repeat(64)},"stale")
    check(controller._request.download_file.empty(),"no_disk_download")
    yield(create_timer(.05),"timeout")
    controller.select({"proxy_id":"a".repeat(64)},"new-selection")
    yield(create_timer(.7),"timeout")
    check(not "stale" in received and received.back()=="new-selection","late_old_selection_discarded")
    for id in ["1","2","3","4","5"]:
        before=received.size()
        controller.select({"proxy_id":id.repeat(64)},"cache-"+id)
        yield(await_result(before),"completed")
        check(textures.back()!=null and textures.back().get_width()<=256 and controller._cache.size()<=4,"bounded_texture_and_cache_"+id)
    controller.configure(origin,"fictional-artwork-credential",true,2)
    check(controller._cache.empty() and controller._request==null,"session_generation_clears_private_ram")
    before=received.size()
    controller.select({"proxy_id":"a".repeat(64)},"before-auth-failure")
    yield(await_result(before),"completed")
    before=received.size()
    controller.select({"proxy_id":"0".repeat(64)},"unauthorized")
    yield(await_result(before),"completed")
    check(auth_failures==1 and controller._credential.empty() and controller._cache.empty(),"authorization_failure_clears_private_session")
    controller._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(controller._credential.empty() and controller._cache.empty(),"background_clears_credentials_and_images")
    print("ARTWORK_HTTP_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
