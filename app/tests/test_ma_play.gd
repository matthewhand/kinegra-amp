extends SceneTree
var failures=[]
func check(value, message):
    if not value:
        failures.append(message)
        printerr("FAIL ", message)
func _init():
    call_deferred("run")
func run():
    var catalog=load("res://scripts/MACatalog.gd").new()
    get_root().add_child(catalog)
    catalog.configure("http://10.77.0.1:8095", "synthetic-token-value", [], true)
    catalog.current_page={"items":[{"provider":"library","item_id":"9","media_type":"playlist","name":"Example"}]}
    catalog.select_index(0)
    check(not catalog.play_on_player("not-discovered"), "reject undiscovered player")
    catalog.available_players["player-1"]=true
    catalog.players_at=OS.get_ticks_msec()
    catalog.selected["item_id"]="9/other"
    check(not catalog.play_on_player("player-1"), "reject invalid media id")
    catalog.selected["item_id"]="9"
    catalog.selected_at=OS.get_ticks_msec()-61000
    catalog.players_at=OS.get_ticks_msec()-61000
    check(catalog.play_on_player("player-1"), "highlighted playlist remains playable after TV navigation")
    check(catalog.request_context.get("kind") == "play", "request labelled as explicit play")
    catalog.cancel()
    catalog.queue_free()
    print("MA_PLAY_FAILURES=",failures)
    quit(0 if failures.empty() else 1)
