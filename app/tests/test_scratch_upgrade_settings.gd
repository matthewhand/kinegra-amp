extends SceneTree

# Two separate Godot launches with a disposable profile, never device data.
const STAGE = "user://scratch-upgrade-stage.marker"
const SETTINGS = "user://installation.cfg"
const SECRET = "synthetic-fixture-secret-not-real"
const TRACK = "https://music.example/fictional-private-track"
var failures = []

func check(ok, description):
    if not ok:
        failures.append(description)
        printerr("FAIL ", description)

func _init():
    call_deferred("run")

func run():
    var probe = File.new()
    var second = probe.file_exists(STAGE)
    var ui = load("res://Main.tscn").instance()
    get_root().add_child(ui)
    yield(create_timer(0.25), "timeout")
    if not second:
        check(ui.ha_endpoint_edit.text.empty(), "fresh HA endpoint")
        check(ui.stream_origin_edit.text.empty(), "fresh audio origin")
        ui.ha_endpoint_edit.text = "wss://ha.example/api/websocket"
        ui.stream_origin_edit.text = "https://music.example:443"
        ui.entity_edit.text = "media_player.fictional"
        ui.transport_trust.pressed = false
        ui.reduced_motion.pressed = true
        ui.large_text.pressed = true
        ui.metronome_bpm.value = 125
        ui.token_edit.text = SECRET
        ui.url_edit.text = TRACK
        ui._save_setup()
        check("Setup saved" in ui.detail_label.text, "save succeeded")
        check(probe.open(SETTINGS, File.READ) == OK, "setup file exists")
        if probe.is_open():
            var content = probe.get_as_text()
            probe.close()
            check(not SECRET in content and not TRACK in content, "no secret or playable URL persisted")
            check("music.example" in content and "fictional" in content, "non-secret settings persisted")
        check(probe.open(STAGE, File.WRITE) == OK, "scratch-only marker")
        if probe.is_open():
            probe.store_string("synthetic-first-run-complete")
            probe.close()
        print("SCRATCH_SETTINGS_STAGE1_FAILURES=", failures)
    else:
        check(ui.ha_endpoint_edit.text == "wss://ha.example/api/websocket", "HA endpoint restored")
        check(ui.stream_origin_edit.text == "https://music.example:443", "audio origin restored")
        check(ui.entity_edit.text == "media_player.fictional", "entity restored")
        check(not ui.transport_trust.pressed, "trust disabled")
        check(ui.reduced_motion.pressed, "reduced motion restored")
        check(ui.large_text.pressed, "large text restored")
        check(int(ui.metronome_bpm.value) == 125, "metronome setting restored")
        check(ui.token_edit.text.empty(), "token absent after process restart")
        check(ui.url_edit.text.empty(), "track URL absent after process restart")
        check(ui.demo and not ui.live_audio, "restart did not start real audio")
        var config = ConfigFile.new()
        check(config.load(SETTINGS) == OK, "installation.cfg reloadable")
        check(config.get_value("installation", "stream_origin", "") == "https://music.example:443", "stable schema")
        check(Directory.new().remove(SETTINGS) == OK, "scratch setup cleaned")
        check(Directory.new().remove(STAGE) == OK, "scratch marker cleaned")
        print("SCRATCH_SETTINGS_STAGE2_FAILURES=", failures)
    quit(0 if failures.empty() else 1)
