extends SceneTree
var checks = 0
var failures = 0
func check(ok, label):
    checks += 1
    if not ok:
        printerr("FAIL: ", label)
        failures += 1
func _init():
    call_deferred("run")
func run():
    var panel = load("res://scripts/MASetupPanel.gd").new()
    get_root().add_child(panel)
    check(panel.token_edit.secret, "token masked")
    panel.setup_box.visible = false
    panel.focus_entry()
    check(panel.setup_button.has_focus(), "collapsed connection has visible focus")
    panel.setup_box.visible = true
    panel.focus_entry()
    check(panel.endpoint_edit.has_focus(), "expanded connection focuses endpoint")
    check(panel.play_button.disabled and panel.playlist_button.disabled, "actions initially disabled")
    check(panel.list.focus_mode == Control.FOCUS_ALL, "list can receive remote focus")
    check(panel.play_button.focus_mode == Control.FOCUS_ALL and panel.playlist_button.focus_mode == Control.FOCUS_ALL, "actions can receive remote focus")
    check(panel.play_button.get_parent() == panel.add_queue_button.get_parent(), "play and add are adjacent")
    panel._on_players([{"name":"Test player", "player_id":"test"}])
    panel.catalog.token="synthetic-credential"
    panel.catalog.selected={"name":"Test track", "provider":"library", "media_type":"track", "available":true}
    panel._on_selection(panel.catalog.selected)
    check("Test track" in panel.selection_label.text, "track selection visible")
    check(not panel.play_button.disabled and panel.playlist_button.disabled, "track play available")
    panel.catalog.selected={"name":"Test playlist", "provider":"library", "media_type":"playlist", "available":true}
    panel._on_selection(panel.catalog.selected)
    check("Test playlist" in panel.selection_label.text, "playlist selection visible")
    check(not panel.play_button.disabled and not panel.playlist_button.disabled, "playlist actions available")
    panel._on_page({"items":[], "kind":"tracks", "offset":0})
    check(not panel.play_button.disabled and panel.add_queue_button.disabled and panel.playlist_button.disabled, "page clears selection but queue Play remains available")
    panel._fictional_albums()
    check(panel.play_button.disabled, "fictional groups cannot play through MA")
    panel._close()
    check(panel.play_button.disabled and "choose" in panel.selection_label.text, "close clears selection")
    print("MA_LIBRARY_UX_CHECKS=", checks)
    panel.queue_free()
    quit(0 if failures == 0 else 1)
