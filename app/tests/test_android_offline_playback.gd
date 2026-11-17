extends SceneTree

class Platform:
    extends Reference
    var plan = {}
    var snapshot = {}
    var commands = []

    func playBackgroundLocal(value):
        plan = JSON.parse(value).result
        return true

    func updateBackgroundLocal(value):
        plan = JSON.parse(value).result
        return true

    func backgroundLocalSnapshot():
        return JSON.print(snapshot)

    func backgroundLocalCommand(_token, command, argument):
        commands.append([command,argument])
        return true

var failures = 0

func check(condition, name):
    if not condition:
        failures += 1
        printerr("FAIL ",name)

func _initialize():
    call_deferred("_run")

func _run():
    OS.set_environment("METHEXIS_SOURCE_TEST","1")
    var player = preload("res://scripts/OfflineMusic.gd").new()
    var native = Platform.new()
    player.android_playback = native
    get_root().add_child(player)
    check(native.plan.empty(),"startup does not play")
    player.user_library.slots = [
        {"file":"import_"+ "a".repeat(64)+".mp3","title":"Fixture one"},
        {"file":"import_"+ "b".repeat(64)+".ogg","title":"Fixture two"}
    ]
    player.playlists.set_availability([false,false,false,false,true,true])
    check(player.cue_track(4) and native.plan.empty(),"cue does not play")
    check(player.queue_track(5) and player.queue_track(5),"each duplicate is queued")
    check(player.play(),"explicit native play accepted")
    var token = native.plan.get("token",0)
    var queued = native.plan.get("queue",[])
    check(token > 0 and queued.size() == 2 and queued[0][0] != queued[1][0],
        "queue occurrences are distinct")
    if queued.size() != 2:
        quit(1)
        return
    native.snapshot={"token":token,"source":"local","state":"playing","track":4,
        "position_ms":23000,"duration_ms":60000}
    player._refresh_native()
    player.suspend_for_background()
    check(player.is_playing() and native.commands.empty(),"UI suspension leaves native player alone")
    native.snapshot.track=5
    native.snapshot.consumed=[queued[0][0]]
    player._refresh_native()
    check(player.track_index==5 and player.upcoming_queue==[5],"return commits just one occurrence")
    player._refresh_native()
    check(player.upcoming_queue==[5],"repeated snapshot does not consume a second occurrence")
    native.snapshot.state="paused"
    native.snapshot.position_ms=24000
    player._refresh_native()
    check(not player.is_playing() and player.progress_seconds()==24.0 and native.commands.empty(),
        "return reflects service pause without a Play command")
    check(player.seek_relative(-3.0) and native.commands==[["seek",21000]],
        "seek works while paused without resuming")
    player.stop()
    check(native.commands.back()==["stop",0] and not player.is_android_playback(),"explicit stop releases owner")
    player.queue_free()
    if failures==0: print("ANDROID_OFFLINE_PLAYBACK_PASS")
    quit(int(failures>0))
