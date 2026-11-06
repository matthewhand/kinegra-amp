extends SceneTree
# Only local Godot controls, fictional input types, no services or Shield.
var checks = 0
var failures = []
func check(ok, name):
    checks += 1
    if not ok:
        failures.append(name)
        printerr("FAIL ", name)
func _init():
    call_deferred("run")
func run():
    var stage = load("res://Main.tscn").instance()
    get_root().add_child(stage)
    yield(create_timer(0.2), "timeout")
    check(stage.music_ui != null and stage.music_ui.visible, "Methexis TV stage is primary")
    check(stage.music_ui.volume_slider==null and stage.music_ui.volume_feedback==null,"system volume only")
    var bus=AudioServer.get_bus_index("Milkdrop")
    check(bus>=0 and is_equal_approx(AudioServer.get_bus_volume_db(bus),0.0),"neutral shared bus gain")
    check(is_equal_approx(stage.offline_music.player.volume_db,0.0),"neutral offline gain")
    check(not stage.offline_music.is_playing(),"no autoplay")
    check(stage.transport_trust.rect_min_size.y >= 52, "LAN trust target enlarged")
    check(stage.reduced_motion.rect_min_size.y >= 52, "reduced-motion target enlarged")
    check(stage.large_text.rect_min_size.y >= 52, "large-text target enlarged")
    check(stage.music_ui.library_button.has_focus(), "MA remains initial Dpad action")
    check(stage.offline_music.current_title() == "Review sample 1", "actual Omega music preserved")
    check(not stage.offline_music.is_playing(), "no sound played in consolidation UI tests")
    print("METHEXIS_CONSOLIDATION_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
