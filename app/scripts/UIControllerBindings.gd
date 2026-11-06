extends Reference
# Godot 3.6 defaults bind UI joy events to slot 0. Android can assign another
# slot to an already connected pad. Widen existing UI joy bindings only;
# keyboard/remote bindings, action deadzones and unrelated actions stay intact.
const ACTIONS=["ui_accept","ui_select","ui_cancel","ui_focus_next","ui_focus_prev","ui_left","ui_right","ui_up","ui_down","ui_page_up","ui_page_down","ui_home","ui_end"]
static func apply():
    var changed=0
    for action in ACTIONS:
        if not InputMap.has_action(action):continue
        for event in InputMap.get_action_list(action):
            if not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or event.device==-1:continue
            var wildcard=event.duplicate()
            wildcard.device=-1
            InputMap.action_erase_event(action,event)
            if not InputMap.action_has_event(action,wildcard):InputMap.action_add_event(action,wildcard)
            changed+=1
    return changed
