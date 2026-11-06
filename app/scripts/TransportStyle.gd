extends Reference
# Shared original transport treatment, matching Home's teal/amber focus palette.
static func apply(button,active):
    var key="playing" if active else "ready"
    if button.has_meta("transport_state") and button.get_meta("transport_state")==key: return
    button.set_meta("transport_state",key)
    var base=Color(.96,.69,.37) if active else Color(.23,.93,.79)
    for state in ["normal","hover","pressed","focus","disabled"]:
        var box=StyleBoxFlat.new()
        box.bg_color=base.darkened(.18 if state=="pressed" else (.27 if state=="disabled" else 0.0))
        box.border_color=Color(1,.86,.52) if state=="focus" else base.lightened(.17)
        box.set_border_width_all(4 if state=="focus" else 1)
        box.set_corner_radius_all(12)
        button.add_stylebox_override(state,box)
    for state in ["font_color","font_color_hover","font_color_pressed","font_color_focus","font_color_disabled"]:
        button.add_color_override(state,Color(.04,.10,.14))
