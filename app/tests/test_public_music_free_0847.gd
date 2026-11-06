extends SceneTree
var checks = 0
var failures = []
var base = "user://public_music_free_0847"
func check(ok, name):
    checks += 1
    if not ok:
        failures.append(name)
        printerr("FAIL ", name)
func _init():
    Engine.target_fps = 60
    create_timer(20).connect("timeout",self,"deadline")
    call_deferred("run")
func deadline():
    printerr("FAIL public music-free fixture deadline")
    quit(1)
func run():
    var app = load("res://Main.tscn").instance()
    get_root().add_child(app)
    app.set_visuals_enabled(false)
    yield(create_timer(.15),"timeout")
    var music = app.offline_music
    var ui = app.music_ui
    check(music.SOURCES.empty() and ui.TRACK_COVERS.empty(),"production runtime has no bundled audio or cover paths")
    check(music.playlists.indices().empty() and not music.is_playing(),"fresh offline library is empty and silent")
    check(music.player.stream == null and music.current_title() == "No local track selected","empty selection has no missing-resource load")
    check(ui.playback_context == "ma" and ui.play_button.has_focus(),"Music Assistant and primary Play remain the default")
    ui._open_offline_collection()
    yield(create_timer(.08),"timeout")
    check(ui.offline_list.get_item_count() == 0 and ui.offline_import_button.has_focus(),"empty library focuses import")
    check(ui.offline_play_button.disabled and ui.offline_queue_button.disabled and ui.offline_remove_button.disabled,"unavailable track actions are disabled")
    check(ui.offline_summary.text.find("EMPTY") >= 0,"empty library explains how to start")
    check(not music.restore_bundled_tracks() and not music.select_track(0),"missing legacy tracks fail without playback or resource loads")
    ui._close_offline_collection()
    check(music.user_library.directory != base,"uses an isolated catalog fixture")
    music.user_library.directory = base
    check(music.user_library.initialize(),"initialize user-owned library")
    var audio = load("res://assets/music/track_01.ogg")
    check(audio != null,"generated test input is available outside production source paths")
    if audio == null:
        quit(1)
        return
    var hashes = []
    var paths = []
    for i in range(2):
        var bytes = PoolByteArray(audio.data)
        bytes.append(i)
        var context = HashingContext.new()
        context.start(HashingContext.HASH_SHA256)
        context.update(bytes)
        var digest = context.finish().hex_encode()
        var filename = "import_" + digest + ".ogg"
        var f = File.new()
        var path = base.plus_file(filename)
        f.open(path,File.WRITE)
        f.store_buffer(bytes)
        f.close()
        f.open(path + ".meta.json",File.WRITE)
        f.store_string(to_json({"version":1,"file":filename,"title":"Synthetic local track %d" % (i+1),"sha256":digest,"bytes":bytes.size()}))
        f.close()
        hashes.append(digest)
        paths.append(path)
    check(music.refresh_user_library() and music.track_count() == 6,"imports retain legacy-stable indices four and five")
    check(not music.available(0) and not music.available(3) and music.available(4) and music.available(5),"only user imports are playable")
    music.playlist_path = "user://public_music_free_preferences.cfg"
    var state = {"playlist":1,"repeat":2,"favorites":[true,false,false,false,true,false],"shuffle":true}
    check(music.playlist_store.write(music.playlist_path,state),"seed old legacy-selected mix and user favorite")
    check(music.restore_preferences(),"restore prior preferences with unavailable bundled slots")
    check(music.playlists.playlist_index == 0 and music.playlists.is_favorite(4) and music.playlists.shuffle_enabled and music.playlists.repeat_name() == "OFF","unavailable old mix falls back while import favorites and playback settings survive")
    music.queue_path = "user://public_music_free_queue.cfg"
    check(music.queue_store.write(music.queue_path,[0,4,3,5]) and music.restore_queue(),"restore mixed legacy/import queue without reindexing")
    check(music.upcoming_queue == [0,4,3,5] and not music.is_playing(),"queue restoration is silent and preserves stored order")
    check(music._play_queued(),"explicit queue Play skips unavailable legacy and plays a user import")
    yield(create_timer(.05),"timeout")
    check(music.track_index == 4 and music.is_playing(),"first imported track plays at its original index")
    music.stop()
    check(music._play_queued(),"next explicit queue Play skips the next legacy entry")
    yield(create_timer(.05),"timeout")
    check(music.track_index == 5 and music.is_playing(),"second imported track remains usable")
    music.stop()
    for i in range(paths.size()):
        check(File.new().get_sha256(paths[i]) == hashes[i],"existing user audio bytes are preserved")
    ui._open_offline_collection()
    check(ui.offline_list.get_item_count() == 2,"offline browser shows only the two imports")
    ui._close_offline_collection()
    ui.show_licenses()
    yield(create_timer(.05),"timeout")
    check(ui.legal_dialog.visible and ui.legal_dialog.entries.size() >= 20,"in-app upstream notice bundle opens")
    check(ui.legal_dialog.viewer.text.find("licenses and notices") >= 0,"license overview is readable")
    for i in range(ui.legal_dialog.entries.size()):
        if ui.legal_dialog.entries[i].file == "ANDROID-CXX-r28-NOTICE.txt":
            ui.legal_dialog._select(i)
            check(ui.legal_dialog.viewer.text.length() <= ui.legal_dialog.PAGE_CHARS and not ui.legal_dialog.next.disabled,"long license text uses bounded pages")
            ui.legal_dialog._next()
            check(ui.legal_dialog.page == 1 and not ui.legal_dialog.previous.disabled,"remote page actions expose the complete notice")
    ui.legal_dialog.hide()
    check(not music.is_playing() and not app.native_transport.active,"fixture ends without music or a network transport")
    print("SHIELDAMP_PUBLIC_MUSIC_FREE_CHECKS=",checks," FAILURES=",failures)
    app.queue_free()
    yield(self,"idle_frame")
    quit(0 if failures.empty() else 1)
