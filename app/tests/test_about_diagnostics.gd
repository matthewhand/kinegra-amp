extends SceneTree
var failed=[]
func check(value,label):
    print("ABOUT_"+("PASS_" if value else "FAIL_")+label)
    if not value: failed.append(label)
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(0.4),"timeout")
    var text=app._device_info_text("SHIELD Android TV", "Android", "0.8.7", ["Example gamepad"])
    check(text.find("SHIELD Android TV")>=0 and text.find("0.8.7")>=0 and text.find("Example gamepad")>=0,"reported_device_and_controller")
    check(text.find("Hardware revision: Not reported")>=0 and text.find("Remote: Not reported")>=0,"unknown_values_are_honest")
    check(app._device_info_text("", "", "1", []).find("None reported")>=0,"no_controller_fallback")
    app.music_ui._advanced()
    check(app.device_refresh_button.has_focus() and app.device_info_label.text.find("Kinegra Amp "+str(ProjectSettings.get_setting("application/config/version")))>=0,"about_visible_from_settings")
    check(app.SUPPORT_PROFILE=="https://github.com/matthewhand","support_profile")
    print("ABOUT_FAILURES=",failed.size())
    quit(0 if failed.empty() else 1)
