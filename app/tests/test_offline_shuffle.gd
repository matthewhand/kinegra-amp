extends SceneTree
# Source-only listening UX: seeded local shuffle, favourites, persistence,
# real original music node safety, accessible TV control. Never use MA/HA.
var checks = 0
var failures = []
const FILE = "user://methexis_shuffle_source_test_only.cfg"
func ck(ok, message):
    checks += 1
    if not ok:
        failures.append(message)
        printerr("FAIL ", message)
func clean():
    var dir = Directory.new()
    for path in [FILE, FILE + ".tmp"]:
        if File.new().file_exists(path):
            dir.remove(path)
func _init():
    call_deferred("run")
func run():
    clean()
    var a = load("res://scripts/LocalPlaylists.gd").new()
    ck(not a.shuffle_enabled and a.shuffle_name() == "OFF", "legacy listening keeps shuffle off")
    ck(not a.set_shuffle_seed("fake") and not a.set_shuffle(true, 5), "invalid seed or selection cannot turn on shuffle")
    ck(a.set_shuffle_seed(101) and a.set_shuffle(true, 0), "seeded local shuffle starts on current")
    ck(a.shuffle_name() == "ON" and a._deck[0] == 0, "shuffle deck anchors current")
    ck(a._deck.size() == 4, "initial deck has all original songs")
    var seen = [0]
    var last = 0
    for i in range(3):
        last = a.step_track(last, 1, true)
        ck(last >= 0 and last < 4 and not last in seen, "shuffle never repeats before exhaustion %d" % i)
        seen.append(last)
    ck(seen.size() == 4 and seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "shuffle exhaustive permutation")
    var boundary = a.step_track(last, 1, true)
    ck(boundary >= 0 and boundary < 4 and boundary != last, "repeat all new cycle never immediate duplicate")
    ck(a.step_track(boundary, -1) == last, "previous follows played shuffle order")
    ck(a.step_track(last, 1) == boundary, "next returns same item after previous")
    var b = load("res://scripts/LocalPlaylists.gd").new()
    ck(b.set_shuffle_seed(101) and b.set_shuffle(true, 0), "second player seeded identically")
    ck(a._rng is RandomNumberGenerator and b._rng is RandomNumberGenerator, "private RNG objects")
    ck(b._deck == [0] + seen.slice(1, 3), "identical seed yields deterministic ordering")
    var first=load("res://scripts/LocalPlaylists.gd").new()
    ck(first.set_shuffle_seed(101) and first.set_shuffle(true, 0), "initial-history boundary setup")
    ck(first.step_track(0,-1)==0 and first._deck_position==0, "previous at shuffle start stays on current")
    ck(first.step_track(0,1)==seen[1], "previous at start does not skip unplayed song")
    # Property sweep across 32 deterministic seeds checks permutation
    # exhaustion and non-repetition at the exact cycle boundary.
    for trial_seed in range(32):
        var walk=load("res://scripts/LocalPlaylists.gd").new()
        walk.set_shuffle_seed(trial_seed)
        walk.set_shuffle(true, 0)
        var visited=[0]
        var current_track=0
        var no_repeat=true
        for _j in range(3):
            current_track=walk.step_track(current_track,1,true)
            if current_track in visited or current_track < 0 or current_track > 3:
                no_repeat=false
            visited.append(current_track)
        ck(no_repeat and visited.size()==4, "each seeded deck exhausts without duplicates %d" % trial_seed)
        var next_cycle=walk.step_track(current_track,1,true)
        ck(next_cycle != current_track and next_cycle in [0,1,2,3], "seeded wrap avoids adjacent duplicate %d" % trial_seed)
        ck(walk.step_track(next_cycle,-1)==current_track, "previous after cycle wrap returns boundary track %d" % trial_seed)
        walk.cycle_repeat()
        ck(walk.step_track(current_track,1,true)==current_track, "repeat one handles stale caller state safely %d" % trial_seed)
    ck(a.snapshot().shuffle and not b.snapshot().favorites[0], "shuffle is separate from favorites")
    ck(not a.set_shuffle(1, boundary) and a.shuffle_enabled, "invalid bool cannot change shuffle state")
    ck(a.set_shuffle(false, boundary) and not a.shuffle_enabled, "shuffle disabled without any audio")
    ck(a.step_track(0, 1) == 1, "disabled shuffle preserves sequential mode")
    ck(a.set_shuffle(true, 2) and a._deck[0] == 2, "re-enable anchored to selected song")
    ck(a.cycle_repeat() == "ONE" and a.step_track(2, 1, true) == 2, "repeat one wins for automatic shuffle")
    ck(a.step_track(2, 1, false) != 2, "manual skip overrides repeat one")
    ck(a.cycle_repeat() == "OFF", "repeat off selected")
    var off = a._deck[a._deck.size() - 1]
    # Move to end of the current deck by stepping forward from the cursor.
    var cursor = a._deck[a._deck_position]
    for i in range(a._deck.size() - a._deck_position - 1):
        cursor = a.step_track(cursor, 1)
    ck(cursor == off and a.step_track(cursor, 1, true) == -1, "shuffle repeat off halts at deck end")
    ck(a.step_track(cursor, 1, false) >= 0, "explicit skip works with repeat off")
    var fav = load("res://scripts/LocalPlaylists.gd").new()
    ck(fav.set_shuffle_seed(7) and fav.toggle_favorite(1), "favorite one")
    ck(fav.toggle_favorite(3) and fav.choose_playlist(3,1) == 1, "favorites can be shuffled")
    ck(fav.set_shuffle(true, 1) and fav._deck.size()==2, "shuffle respects favorite subset")
    var other = fav.step_track(1,1)
    ck(other == 3 and fav.step_track(3,1,true) == 1, "two-favorite shuffle cycles exactly")
    ck(not fav.toggle_favorite(3) and fav.indices() == [1], "removal updates favorite subset")
    ck(fav.step_track(1,1) == 1, "single favorite manual next stable")
    ck(fav.cycle_repeat() == "ONE" and fav.step_track(1,1,true)==1, "single favorite repeat one")
    ck(fav.cycle_repeat() == "OFF" and fav.step_track(1,1,true)==-1, "single favorite repeat off")
    ck(not fav.toggle_favorite(1) and fav.indices().empty(), "bare collection may temporarily empty")
    ck(fav.step_track(1,1)==-1, "empty favorites fail closed")
    ck(fav.choose_playlist(3,1)==-1, "cannot explicitly activate empty collection")
    var before = a.snapshot()
    ck(not a.restore({"playlist":2,"repeat":0,"favorites":[true,true,true,true],"shuffle":"on"}), "restore rejects string shuffle")
    var after = a.snapshot()
    ck(after.playlist == before.playlist and after.repeat == before.repeat and after.favorites == before.favorites and after.shuffle == before.shuffle, "rejected restore is transactional")
    ck(a.restore({"playlist":1,"repeat":0,"favorites":[false,false,false,false]}), "legacy in-memory restore defaults shuffle off")
    ck(not a.shuffle_enabled, "legacy in-memory shuffle default off")
    var store=load("res://scripts/PlaylistStore.gd").new()
    var state={"playlist":1,"repeat":2,"favorites":[false,true,false,true],"shuffle":true}
    ck(store.write(FILE,state), "schema three saves shuffle")
    var current=store.read(FILE)
    ck(current.ok and not current.state.migrated and current.state.shuffle, "schema three rereads true shuffle")
    ck(current.state.favorites==[false,true,false,true] and current.state.repeat==2, "previous preferences preserved")
    var config=ConfigFile.new()
    ck(config.load(FILE)==OK and config.get_value("omega","version")==4, "on-disk version four")
    config.set_value("omega","shuffle","true")
    config.save(FILE)
    ck(not store.read(FILE).ok, "string instead of bool rejected")
    config.set_value("omega","shuffle",true)
    config.set_value("omega","version",5)
    config.save(FILE)
    ck(not store.read(FILE).ok, "future schema version rejected")
    config.erase_section_key("omega","shuffle")
    config.set_value("omega","version",3)
    config.save(FILE)
    ck(not store.read(FILE).ok, "missing shuffle field rejected")
    config.set_value("omega","version",2)
    config.save(FILE)
    var migrated=store.read(FILE)
    ck(migrated.ok and migrated.state.migrated and not migrated.state.shuffle, "v2 migrates safely with shuffle off")
    ck(store.write(FILE,migrated.state), "v2 migration persisted as v3")
    ck(store.read(FILE).ok and not store.read(FILE).state.migrated, "v3 migration completion verified")
    var live=load("res://scripts/OfflineMusic.gd").new()
    live.playlist_path=FILE
    get_root().add_child(live)
    ck(not live.is_playing() and not live.playlists.shuffle_enabled, "no autoplay on migrated state")
    ck(live.toggle_shuffle() and live.last_save_ok, "live control saves shuffle toggle")
    live.queue_free()
    yield(create_timer(0.05),"timeout")
    var again=load("res://scripts/OfflineMusic.gd").new()
    again.playlist_path=FILE
    get_root().add_child(again)
    ck(again.playlists.shuffle_enabled and not again.is_playing(), "restart restores shuffle without autoplay")
    ck(again.playlists.playlist_index==1 and again.playlists.repeat_index==2, "shuffle does not overwrite other settings")
    again.queue_free()
    yield(create_timer(0.05),"timeout")
    # Remove selected last favourite in the actual app player (never autoplay).
    var single=load("res://scripts/OfflineMusic.gd").new()
    single.playlist_path=FILE
    get_root().add_child(single)
    single.choose_playlist(0)
    if not single.playlists.is_favorite(0):
        single.toggle_favorite()
    ck(single.choose_playlist(3) and single.track_index==0, "select favorite for removal")
    # Force selected favorites to a singleton without touching a user path.
    var only=[true,false,false,false]
    ck(single.playlists.restore({"playlist":3,"repeat":0,"favorites":only,"shuffle":true}), "singleton fixture accepted")
    ck(not single.toggle_favorite(), "last favorite removed")
    ck(single.playlists.playlist_index==0 and not single.is_playing(), "empty favorites falls back to all silently")
    ck(single.last_save_ok and store.read(FILE).state.playlist==0, "fallback to all persisted")
    single.queue_free()
    yield(create_timer(0.05),"timeout")
    var subset=load("res://scripts/OfflineMusic.gd").new()
    subset.playlist_path=FILE
    get_root().add_child(subset)
    subset.choose_playlist(0)
    ck(subset.playlists.restore({"playlist":3,"repeat":0,"favorites":[true,false,true,false],"shuffle":true}), "two-favorite fixture accepted")
    ck(subset.track_index==0 and not subset.toggle_favorite(), "current favorite can be removed silently")
    ck(subset.track_index==2 and subset.playlists.playlist_index==3 and not subset.is_playing(), "remaining favorite selected without playback")
    ck(subset.last_save_ok and store.read(FILE).state.favorites == [false,false,true,false], "favorite subset saved after cursor repair")
    subset.queue_free()
    yield(create_timer(0.05),"timeout")
    var tv=load("res://Main.tscn").instance()
    get_root().add_child(tv)
    yield(create_timer(0.2),"timeout")
    ck(tv.music_ui.shuffle_button!=null and tv.music_ui.shuffle_button.focus_mode==Control.FOCUS_ALL, "D-pad shuffle control")
    ck(tv.music_ui.shuffle_button.rect_min_size.y>=50, "TV shuffle touch/focus size")
    ck(tv.music_ui.shuffle_button.text=="SHUFFLE: OFF", "restored isolated default text")
    tv.music_ui._toggle_shuffle()
    ck(tv.offline_music.playlists.shuffle_enabled and tv.music_ui.shuffle_button.text=="SHUFFLE: ON", "UI toggles shuffle on")
    ck(not tv.offline_music.is_playing() and tv.music_ui.library_button.has_focus(), "shuffle never autoplays or steals MA first focus")
    tv.music_ui._toggle_shuffle()
    ck(not tv.offline_music.playlists.shuffle_enabled and tv.music_ui.shuffle_button.text=="SHUFFLE: OFF", "UI toggles shuffle off")
    ck(tv.ma_panel.catalog.token.empty(), "no Music Assistant token action")
    clean()
    print("METHEXIS_SHUFFLE_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
