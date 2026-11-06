extends SceneTree
var failures=[]
var checks=0
func check(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        print("CONTROLLER_BINDINGS_FAIL_",label)
func _init():call_deferred("run")
func run():
    var policy=load("res://scripts/UIControllerBindings.gd")
    var before=InputEventJoypadButton.new();before.button_index=0;before.pressed=true
    before.device=0
    check(before.is_action_pressed("ui_accept"),"actual_default_slot_zero_matches")
    before.device=5
    check(not before.is_action_pressed("ui_accept"),"actual_default_slot_five_does_not_match")
    # This runtime has no default axis events. Seed one existing UI motion
    # binding to verify migration also preserves any configured axes.
    var existing_axis=InputEventJoypadMotion.new()
    existing_axis.device=5;existing_axis.axis=0;existing_axis.axis_value=-1.0
    InputMap.action_add_event("ui_left",existing_axis)
    var originals={}
    var key_signatures={}
    var deadzones={}
    var default_joy_count=0
    var axes=0
    for action in policy.ACTIONS:
        if not InputMap.has_action(action):continue
        originals[action]=[]
        key_signatures[action]=[]
        deadzones[action]=InputMap.action_get_deadzone(action)
        for event in InputMap.get_action_list(action):
            if event is InputEventJoypadButton or event is InputEventJoypadMotion:
                originals[action].append(event.duplicate())
                default_joy_count+=1
                if event is InputEventJoypadMotion:axes+=1
            else:key_signatures[action].append(event.as_text()+"|"+str(event.device))
    var custom=InputEventJoypadButton.new();custom.device=5;custom.button_index=7
    InputMap.add_action("fixture_non_ui");InputMap.action_add_event("fixture_non_ui",custom)
    check(policy.apply()>0,"actual_runtime_defaults_need_wildcard")
    var total_after=0
    for action in originals:
        var after_keys=[]
        var joy_count=0
        for event in InputMap.get_action_list(action):
            if event is InputEventJoypadButton or event is InputEventJoypadMotion:
                check(event.device==-1,"only_wildcard_joy_"+action)
                joy_count+=1
            else:after_keys.append(event.as_text()+"|"+str(event.device))
        check(after_keys==key_signatures[action],"keyboard_remote_mapping_unchanged_"+action)
        check(InputMap.action_get_deadzone(action)==deadzones[action],"deadzone_unchanged_"+action)
        check(joy_count==originals[action].size(),"no_duplicate_or_new_binding_"+action)
        total_after+=joy_count
        for original in originals[action]:
            for slot in [0,1,5,15]:
                var event=original.duplicate();event.device=slot
                if event is InputEventJoypadButton:event.pressed=true
                else:event.axis_value=original.axis_value
                check(event.is_action_pressed(action),"press_slot_"+str(slot)+"_"+action)
                if event is InputEventJoypadButton:event.pressed=false
                else:event.axis_value=0.0
                check(not event.is_action_pressed(action) and event.is_action_released(action),"release_slot_"+str(slot)+"_"+action)
    check(total_after==default_joy_count and axes>0,"existing_axis_and_button_bindings_preserved")
    check(policy.apply()==0,"idempotent_startup")
    var custom_after=InputMap.get_action_list("fixture_non_ui")
    check(custom_after.size()==1 and custom_after[0].device==5,"unrelated_action_unchanged")
    InputMap.erase_action("fixture_non_ui")
    for action in ["ui_accept","ui_cancel","ui_left","ui_right","ui_up","ui_down"]:
        var keys=[]
        for event in InputMap.get_action_list(action):
            if event is InputEventKey:keys.append(event)
        check(not keys.empty(),"keyboard_remote_exists_"+action)
        for original in keys:
            var event=original.duplicate();event.pressed=true
            check(event.is_action_pressed(action),"keyboard_remote_still_matches_"+action)
            event.pressed=false
            check(not event.is_action_pressed(action),"keyboard_remote_release_"+action)
    print("CONTROLLER_BINDINGS_CHECKS=",checks," AXIS_BINDINGS=",axes," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
