extends SceneTree
var checks = 0
var failures = []
func ck(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func _init():
    Engine.target_fps = 60
    create_timer(15.0).connect("timeout", self, "deadline")
    call_deferred("run")
func deadline():
    printerr("FAIL offline accessibility fixture exceeded its deadline")
    quit(1)
func run():
    var scene = load("res://Main.tscn")
    if scene == null:
        ck(false, "main scene loads")
        quit(1)
        return
    var tv = scene.instance()
    get_root().add_child(tv)
    tv.set_visuals_enabled(false)
    yield(create_timer(0.22), "timeout")
    var ui = tv.music_ui
    ck(not tv.offline_music.is_playing(), "no autoplay at boot")
    ck(ui.play_button.has_focus(), "initial focus reaches the primary Play action")
    var baseline = ui.root.theme.default_font.size
    tv._set_large_text(true)
    ck(ui.root.theme.default_font.size > baseline, "large text changes music-first button fonts")
    tv._set_large_text(false)
    ck(ui.root.theme.default_font.size == baseline, "normal text restored")
    var source = ui.playback_context
    var original_track = tv.offline_music.track_index
    ui._open_offline_collection()
    yield(create_timer(0.1), "timeout")
    ck(ui.offline_list.get_item_count() >= 4, "four generated fixture tracks are available")
    if ui.offline_list.get_item_count() < 4:
        tv.queue_free()
        quit(1)
        return
    ck(ui.offline_list.focus_mode == Control.FOCUS_ALL, "track list accepts remote focus")
    ck(ui.offline_mix_button.has_focus(), "opening library focuses mix")
    for dimension in [Vector2(960,720), Vector2(1280,720), Vector2(1920,1080)]:
        OS.window_size = dimension
        tv._apply_resolution_base()
        ui._apply_compact_layout()
        ui.offline_mix_button.grab_focus()
        yield(create_timer(0.13), "timeout")
        var viewport = Rect2(Vector2.ZERO, dimension)
        ck(viewport.encloses(ui.offline_drawer.get_global_rect()), "drawer within screen at %d" % dimension.x)
        ck(ui.offline_mix_button.rect_size.y >= 48, "mix retains its declared remote target at %d" % dimension.x)
        ck(ui.offline_list.rect_size.y >= 180, "list retains a browsable viewport at %d" % dimension.x)
        tv._set_large_text(true)
        yield(create_timer(0.05), "timeout")
        ck(ui.root.theme.default_font.size >= baseline + 2, "large text remains active at %d" % dimension.x)
        ck(ui.offline_mix_button.has_focus(), "resizing and scaling preserve focus at %d" % dimension.x)
        var header_width = ui.offline_heading.get_font("font").get_string_size(ui.offline_heading.text).x
        var title_width = ui.offline_selected_label.get_font("font").get_string_size(ui.offline_selected_label.text).x
        ck(header_width <= ui.offline_heading.rect_size.x + 2.0, "library heading fits large text at %d" % dimension.x)
        ck(title_width <= ui.offline_selected_label.rect_size.x + 2.0, "selected title fits large text at %d" % dimension.x)
        ui.offline_favorite_button.grab_focus()
        yield(create_timer(0.08), "timeout")
        ck(ui.offline_drawer.get_global_rect().encloses(ui.offline_favorite_button.get_global_rect()), "focused footer scrolls into view at %d" % dimension.x)
        tv._set_large_text(false)
    var selected_title = tv.offline_music.get_title(3)
    ui.offline_list.select(3)
    ui.offline_list.grab_focus()
    ui._offline_item_selected(3)
    ck(ui.offline_list.has_focus(), "selecting a row retains list focus")
    ck(ui.offline_list.get_item_text(3) == selected_title, "row retains the source track title")
    ck(ui.offline_list.get_item_tooltip(3) == selected_title, "unabridged row tooltip is retained")
    ck(ui.offline_selected_label.text == "SELECTED: " + selected_title.to_upper(), "selected-title label names the selected track")
    ck(ui.offline_selected_label.hint_tooltip == ui.offline_selected_label.text, "unabridged selected-title help is retained")
    ui._refresh_offline_collection()
    ck(ui.offline_list.has_focus() and ui.offline_list.get_selected_items() == PoolIntArray([3]), "refresh preserves selected row and focus")
    ui._offline_item_activated(3)
    ck(ui.offline_play_button.has_focus(), "row activation reaches Play without starting music")
    ck(ui.playback_context == source and tv.offline_music.track_index == original_track, "browsing preserves the active source and track")
    ck(not tv.offline_music.is_playing(), "accessibility operations never autoplay")
    ck(tv.ma_panel.catalog.token.empty(), "no MA credentials are used")
    ck(not tv.native_transport.active, "layout checks leave network transport idle")
    ui._close_offline_collection()
    ck(ui.offline_button.has_focus() and not ui.offline_drawer.visible, "closing restores launch focus")
    print("METHEXIS_TV_ACCESSIBILITY_CHECKS=",checks," FAILURES=",failures)
    tv.queue_free()
    yield(self, "idle_frame")
    quit(0 if failures.empty() else 1)
