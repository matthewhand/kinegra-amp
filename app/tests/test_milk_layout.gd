extends SceneTree
var failures = []
var checks = 0
func check(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func _init():
    call_deferred("run")
func run():
    var ui = load("res://Main.tscn").instance()
    get_root().add_child(ui)
    yield(create_timer(.1), "timeout")
    for size in [Vector2(960,720), Vector2(1280,720), Vector2(1280,800), Vector2(1680,720), Vector2(360,800), Vector2(3440,1440)]:
        for large in [false, true]:
            OS.window_size = size
            ui._apply_resolution_base()
            ui.rect_size = get_root().size
            ui._update_layout()
            ui.large_text.pressed = large
            ui._set_large_text(large)
            yield(create_timer(.02), "timeout")
            check(ui.command_grid.columns >= 1 and ui.command_grid.columns <= 4, "responsive grid columns")
            var max_columns = max(1, int((ui.rect_size.x - 48) / 140))
            check(ui.command_grid.columns <= max_columns, "buttons fit logical width")
            check(ui.accessibility_font.size == (28 if large else 20), "actual readable font size")
            check(ui.page_scroller.get_child(0).get_combined_minimum_size().x <= ui.page_scroller.rect_size.x + 1, "content has no horizontal overflow")
            check(ui.page_scroller.follow_focus and not ui.page_scroller.scroll_horizontal_enabled, "reachable vertical navigation")
    ui._show_ma_catalog()
    check(ui.ma_panel.visible and ui.ma_panel.endpoint_edit.has_focus(), "optional collection focus")
    ui.ma_panel.token_edit.text = "synthetic-memory-only"
    ui.ma_panel._close()
    check(not ui.ma_panel.visible and ui.ma_panel.token_edit.text.empty() and ui.music_ui.library_button.has_focus(), "MA close clears token and returns to library focus")
    var before = ui.url_edit.text
    ui._on_ma_selected({"name":"Synthetic title", "uri":"library://not-playable"})
    check(ui.url_edit.text == before and not ui.stream_engine.active, "catalog selection cannot become inferred playback")
    ui.reduced_motion.pressed = true
    ui._process(.016)
    check(ui.shader_material.get_shader_param("motion") == 0.0, "reduced motion shader")
    check("IDLE" in ui.analysis_label.text, "silent idle without fake audio")
    ui._switch_demo()
    ui._process(.016)
    check("DEMO VISUALS" in ui.analysis_label.text, "opt-in visual demo is not an audio source")
    print("LAYOUT_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
