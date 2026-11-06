extends SceneTree
var failures = []
func check(ok, label):
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func _init():
    call_deferred("run")
func run():
    var ui = load("res://Main.tscn").instance()
    get_root().add_child(ui)
    yield(create_timer(0.2), "timeout")
    check(ui.stream_origin_edit.text.empty() and ui.ha_endpoint_edit.text.empty(), "portable empty setup")
    ui.ha_endpoint_edit.text = "wss://ha.example/api/websocket"
    ui.stream_origin_edit.text = "https://audio.example:443"
    ui.entity_edit.text = "media_player.example"
    ui.token_edit.text = "synthetic-private-credential"
    ui.url_edit.text = "https://audio.example/private-track"
    ui._save_setup()
    var f = File.new()
    check(f.open("user://installation.cfg", File.READ) == OK, "explicit save")
    var saved = f.get_as_text()
    f.close()
    check(not "synthetic-private" in saved and not "private-track" in saved, "no token or track URL persisted")
    check("audio.example" in saved and "media_player.example" in saved, "nonsecret settings saved")
    ui.stream_origin_edit.text = "https://user:secret@host"
    ui._save_setup()
    check("not saved" in ui.detail_label.text, "invalid endpoint rejected")
    f.open("user://installation.cfg", File.READ)
    check(f.get_as_text() == saved, "invalid save preserves valid setup")
    f.close()
    var api = get_root().get_node("HAApi")
    api.start("synthetic", "media_player.bad/invalid", "wss://ha.example/api/websocket")
    check(api._client == null and api._token.empty(), "invalid entity clears credential before network")
    api.start("synthetic", "media_player.example", "ws://10.77.0.1:8123/api/websocket", false)
    check(api._client == null and api._token.empty(), "untrusted cleartext blocks token transmission")
    ui.token_edit.text = ""
    ui.url_edit.text = ""
    ui.stream_origin_edit.text = "https://audio.example"
    ui.detail_label.text = "Optional HA • Independent PCM WAV playback • Setup saves no token"
    yield(create_timer(0.2), "timeout")
    var image = get_root().get_texture().get_data()
    image.flip_y()
    image.save_png("user://setup-ui.png")
    Directory.new().remove("user://installation.cfg")
    print("SETUP_UI_FAILURES=", failures)
    quit(0 if failures.empty() else 1)
