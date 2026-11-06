extends SceneTree
# Isolated, no-network, no-MA state tests. Optional positive PCM fixture
# MUST be decoded from the owner-original Ogg; no synthetic tones.
var checks = 0
var failures = []
const TEST_FILE = "user://methexis_source_batch_test_only.cfg"

func ck(ok, note):
    checks += 1
    if not ok:
        failures.append(note)
        printerr("FAIL ", note)

func _init():
    call_deferred("run")

func _remove_test_file():
    var dir = Directory.new()
    if File.new().file_exists(TEST_FILE):
        dir.remove(TEST_FILE)
    if File.new().file_exists(TEST_FILE + ".tmp"):
        dir.remove(TEST_FILE + ".tmp")

func run():
    _remove_test_file()
    var store = load("res://scripts/PlaylistStore.gd").new()
    var pref = load("res://scripts/LocalPlaylists.gd").new()
    var absent = store.read(TEST_FILE)
    ck(absent.ok and not absent.found, "no missing file falsely marked corrupt")
    ck(not pref.restore({"playlist":2,"repeat":1,"favorites":[true, "bad", false, false]}), "mixed flags transaction rejected")
    ck(pref.playlist_name() == "ALL FOUR", "failed restore no mutation")
    ck(pref.toggle_favorite(1), "favorite stored true")
    ck(pref.choose_playlist(2,1) == 1, "selected preset set")
    ck(pref.cycle_repeat() == "ONE", "repeat updated")
    ck(store.write(TEST_FILE, pref.snapshot()), "persist schema v2")
    var reopened = store.read(TEST_FILE)
    ck(reopened.ok and reopened.found and not reopened.state.migrated, "versioned file reopens")
    var fresh = load("res://scripts/LocalPlaylists.gd").new()
    ck(fresh.restore(reopened.state), "fresh app instance restores valid state")
    ck(fresh.playlist_index == pref.playlist_index and fresh.repeat_index == pref.repeat_index and fresh.favorites == pref.favorites, "playlist favorite repeat preserved across instance")
    ck(not store.write(TEST_FILE, {"playlist":1,"repeat":0,"favorites":[1,0,0,0]}), "bad state cannot overwrite previous file")
    ck(store.read(TEST_FILE).state.favorites[1], "failed write preserves previous file")
    var old = ConfigFile.new()
    old.set_value("omega", "version", 1)
    old.set_value("omega", "playlist", 3)
    old.set_value("omega", "repeat", 2)
    old.set_value("omega", "favorites", [1,0,0,1])
    ck(old.save(TEST_FILE) == OK, "test fixture creates v1 config")
    var migrated = store.read(TEST_FILE)
    ck(migrated.ok and migrated.state.migrated, "explicit legacy v1 accepted")
    ck(migrated.state.favorites == [true,false,false,true] and migrated.state.repeat == 2, "v1 bit flags migrated to bools")
    ck(store.write(TEST_FILE, migrated.state), "migration writes current schema v3")
    ck(not store.read(TEST_FILE).state.migrated, "migration persists current v3")
    # Fully integrated player save/reload without any real user preference file.
    var own_music = load("res://scripts/OfflineMusic.gd").new()
    own_music.playlist_path = TEST_FILE
    get_root().add_child(own_music)
    ck(own_music.track_index == 0 and not own_music.is_playing(), "restored collection remains silent")
    ck(own_music.playlists.is_favorite(0), "app player restored migrated favorite")
    ck(own_music.toggle_favorite() == false, "favorite toggle persisted through app path")
    ck(own_music.last_save_ok, "automatic app persistence succeeded")
    own_music.queue_free()
    yield(create_timer(0.05), "timeout")
    var own_music_again = load("res://scripts/OfflineMusic.gd").new()
    own_music_again.playlist_path = TEST_FILE
    get_root().add_child(own_music_again)
    ck(not own_music_again.playlists.is_favorite(0) and own_music_again.playlists.is_favorite(3), "new player instance loads changed favorites")
    ck(own_music_again.track_index == 3 and not own_music_again.is_playing(), "silent restored selection stays within collection")
    own_music_again.queue_free()
    yield(create_timer(0.05), "timeout")
    old.set_value("omega", "version", 1)
    old.set_value("omega", "favorites", [1, 0, 2, 0])
    old.save(TEST_FILE)
    ck(not store.read(TEST_FILE).ok, "invalid legacy bits fail closed")
    old.set_value("omega", "version", 99)
    old.save(TEST_FILE)
    ck(not store.read(TEST_FILE).ok, "unknown future format fail closed")
    old.set_value("omega", "version", 2)
    old.set_value("omega", "favorites", [true, true, true, true])
    old.set_value("omega", "repeat", "1")
    old.save(TEST_FILE)
    ck(not store.read(TEST_FILE).ok, "string for integer cannot coerce")
    var f = File.new()
    f.open(TEST_FILE, File.WRITE)
    f.store_string("X".repeat(4097))
    f.close()
    ck(not store.read(TEST_FILE).ok, "oversize preference file rejected")
    ck(pref.playlist_name() == "HEAVY ROTATION", "corrupt file leaves in-memory state intact")
    _remove_test_file()

    var catalog = load("res://scripts/OfflineLibraryCatalog.gd").new()
    var albums = catalog.browse("albums")
    ck(albums.ok and albums.total == 2, "two explicit fictional albums")
    ck(albums.items.size() == 2 and albums.items[0].fictional, "offline fictional origin marked")
    ck(catalog.browse("artists").total == 1, "fictional artist grouping")
    ck(catalog.browse("tracks").total == 4, "four original tracks only")
    ck(catalog.browse("albums", "AFTER").total == 1, "case insensitive album search")
    ck(catalog.browse("artists", "no such author").total == 0, "empty query is honest")
    ck(not catalog.browse("playlists").ok, "unsupported collection rejects")
    ck(not catalog.browse("albums", "", -1).ok, "negative offsets reject")

    var ui = load("res://Main.tscn").instance()
    get_root().add_child(ui)
    yield(create_timer(0.2), "timeout")
    ck(ui.local_pcm != null and not ui.local_pcm.active, "PCM node attached but silent until explicit start")
    ck(ui.local_pcm.audio.bus == "Milkdrop", "local PCM routes to actual analyzer bus")
    ck(AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Milkdrop"),0) != null, "actual FFT analyzer instance exists")
    ck(not ui.feed_explicit_local_pcm(PoolByteArray([0,0,0,0])), "cannot feed before explicit start")
    ui.ma_panel._fictional_albums()
    ck(ui.ma_panel.offline_mode and ui.ma_panel.list.get_item_count() == 2, "TV album browsing has two records")
    ck(ui.ma_panel.confirm_button.disabled and ui.ma_panel.preview_button.disabled, "fictional albums cannot open MA playback")
    ui.ma_panel._select_index(0)
    ck("FICTIONAL" in ui.ma_panel.status_label.text, "fictional selection labelled no play")
    ck(ui.ma_panel.catalog.token.empty(), "offline browse no MA credentials")
    ui.ma_panel._preview()
    ui.ma_panel._confirm()
    ck(ui.ma_panel.preview_button.disabled and ui.ma_panel.confirm_button.disabled, "fictional data blocks even direct preview/confirm requests")
    ui.ma_panel._fictional_artists()
    ck(ui.ma_panel.list.get_item_count() == 1, "TV artist browsing visible")
    ck(not ui.offline_music.is_playing(), "browsing never autoplays")

    ck(ui.begin_explicit_local_pcm(), "explicit local PCM start")
    ck(ui.local_pcm.active and ui.local_pcm.audio.playing, "engine generator player active")
    ck(not ui.feed_explicit_local_pcm(PoolByteArray([1,2,3])), "unaligned payload never queued")
    var block = PoolByteArray()
    for i in range(1024):
        block.append(0)
    ck(ui.feed_explicit_local_pcm(block), "silent local PCM staged")
    ck(ui.local_pcm.accepted_frames >= 256 or ui.local_pcm.stage.buffered_bytes == 1024, "PCM accepted or exact bytes retained on pressure")
    var pcm_path = OS.get_environment("METHEXIS_LOCAL_PCM_FIXTURE")
    var fft_peak = 0.0
    var rendered_fft_peak = 0.0
    var real_frames = 0
    if not pcm_path.empty():
        var pcmfile = File.new()
        if pcmfile.open(pcm_path, File.READ) == OK:
            var whole = pcmfile.get_buffer(min(pcmfile.get_len(), 48000))
            pcmfile.close()
            for at in range(0, whole.size(), 4096):
                var part = PoolByteArray()
                for j in range(at, min(at + 4096, whole.size())):
                    part.append(whole[j])
                if ui.feed_explicit_local_pcm(part):
                    real_frames += int(part.size() / 4)
                yield(create_timer(0.015), "timeout")
                ui._process(0.016)
                rendered_fft_peak = max(rendered_fft_peak, ui.fft.max())
                var analyzer = AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Milkdrop"), 0)
                if analyzer != null:
                    var power = analyzer.get_magnitude_for_frequency_range(50, 15000)
                    fft_peak = max(fft_peak, max(power.x, power.y))
            yield(create_timer(0.12), "timeout")
            ui._process(0.016)
            rendered_fft_peak = max(rendered_fft_peak, ui.fft.max())
            var analyzer = AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Milkdrop"), 0)
            var power = analyzer.get_magnitude_for_frequency_range(50,15000)
            fft_peak = max(fft_peak, max(power.x, power.y))
    ck(pcm_path.empty() or real_frames > 0, "owner Ogg decoded PCM frames submitted")
    ck(pcm_path.empty() or fft_peak > 0.000001, "actual original music PCM reaches nonzero FFT")
    ck(pcm_path.empty() or rendered_fft_peak > 0.001, "local PCM also drives nonzero visible FFT bands")
    ck(pcm_path.empty() or ui.analysis_label.text == "LOCAL PCM / REAL AUDIO FFT", "local PCM source properly labelled in visualization")
    print("METHEXIS_LOCAL_PCM_FFT_PEAK=",fft_peak," VISUAL_FFT_PEAK=",rendered_fft_peak," ORIGINAL_FRAMES=",real_frames)
    ui.local_pcm._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    ck(not ui.local_pcm.active and ui.local_pcm.stage.buffered_bytes == 0, "focus loss flushes queued PCM")
    ck(not ui.local_pcm.audio.playing and ui.local_pcm.playback == null, "focus loss frees audio playback")
    ck(not ui.feed_explicit_local_pcm(block), "no stale PCM after focus loss")
    ck(ui.begin_explicit_local_pcm(), "explicit restart after focus loss")
    ui._stop_all_music()
    ck(not ui.local_pcm.active and ui.local_pcm.accepted_frames == 0, "Stop resets generator and counters")
    ck(not ui.offline_music.is_playing(), "PCM never overlaps original Ogg")
    var saved = load("res://scripts/LocalPlaylists.gd").new()
    ck(saved.restore({"playlist":2,"repeat":0,"favorites":[false,false,false,false]}), "preference restore accepts nonempty preset")
    ck(saved.choose_playlist(3,1) == -1, "empty favourites cannot become active")
    var stress = load("res://scripts/OfflinePcmStaging.gd").new()
    var silent = PoolByteArray()
    for _i in range(1024):
        silent.append(0)
    var held = true
    for _i in range(32):
        held = held and stress.enqueue(silent)
    ck(held and stress.buffered_bytes == 32768, "deterministic bounded PCM backlog")
    ck(not stress.enqueue(silent) and stress.buffered_bytes == 32768, "full PCM backlog never drops or overwrites")
    stress.reset()
    ck(stress.buffered_bytes == 0 and stress.blocks.empty(), "post-interruption PCM backlog empty")
    _remove_test_file()
    print("METHEXIS_FINISH_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
