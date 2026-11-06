extends SceneTree
var failures=[]
func find_button(node, label):
    if node is Button and node.text == label:
        return node
    for child in node.get_children():
        var result = find_button(child, label)
        if result != null:
            return result
    return null
func _init():
    call_deferred("run")
func run():
    var ui=load("res://Main.tscn").instance()
    get_root().add_child(ui)
    yield(create_timer(0.2),"timeout")
    ui.music_ui._open_library()
    yield(create_timer(0.2),"timeout")
    ui.ma_panel._toggle_demos()
    yield(create_timer(0.2),"timeout")
    for label in ["TRACKS", "PLAYLISTS", "FICTIONAL ALBUMS", "FICTIONAL ARTISTS"]:
        var button=find_button(ui.ma_panel,label)
        if button == null or button.rect_size.x < 100:
            failures.append(label)
            printerr("FAIL collapsed button ",label," width=",button.rect_size.x if button != null else -1)
    print("MA_POPUP_LAYOUT_FAILURES=",failures)
    ui.queue_free()
    quit(0 if failures.empty() else 1)
