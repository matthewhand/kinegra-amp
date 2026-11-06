extends SceneTree
# Offline-only skeptical regression. Creates ONLY a disposable explicitly
# named user:// test preference, never genuine Methexis user settings.
var checks = 0
var failures = []
const PREF = "user://methexis_hardening_source_test_only.cfg"
func ck(value, message):
    checks += 1
    if not value:
        failures.append(message)
        printerr("FAIL ", message)
func _init():
    call_deferred("run")
func _read():
    var f = File.new()
    if f.open(PREF, File.READ) != OK:
        return ""
    var value = f.get_as_text()
    f.close()
    return value
func _write(raw):
    var f = File.new()
    if f.open(PREF, File.WRITE) != OK:
        return false
    f.store_string(raw)
    f.close()
    return true
func _remove():
    var dir=Directory.new()
    for file in [PREF, PREF + ".tmp"]:
        if File.new().file_exists(file):
            dir.remove(file)
func _new_player():
    var result = load("res://scripts/OfflineMusic.gd").new()
    result.playlist_path = PREF
    get_root().add_child(result)
    return result
func run():
    # Fail safe when a future application created a preference format unknown
    # to this version, even if the user then toggles playlist/favourite/shuffle.
    ck(not File.new().file_exists(PREF), "test fixture path unoccupied")
    var store = load("res://scripts/PlaylistStore.gd").new()
    var future = "[omega]\nversion=91\nplaylist=0\nrepeat=0\nfavorites=[ false, false, false, false ]\nshuffle=false\n[future]\nimportant=\"DO NOT ERASE\"\n"
    ck(_write(future), "unsupported future preferences fixture created")
    var before = _read()
    var music = _new_player()
    ck(music.preferences_load_blocked and not music.last_save_ok, "future preference file blocks in-app writes")
    ck(not music.is_playing() and music.playlists.playlist_index == 0, "corrupt load leaves silent safe defaults")
    music.toggle_shuffle()
    music.toggle_favorite()
    music.cycle_repeat()
    ck(music.choose_playlist(1), "playlist switching still works in memory")
    ck(music.preferences_load_blocked and not music.last_save_ok, "all mutation paths remain unsaved")
    ck(_read() == before, "future schema and unknown fields preserved byte for byte")
    music.queue_free()
    yield(create_timer(0.05), "timeout")
    # Test all three known schemas, including the migration of a selected
    # empty favourites collection, without discarding other preference flags.
    var config = ConfigFile.new()
    for ver in [1,2,3]:
        config.clear()
        config.set_value("omega", "version", ver)
        config.set_value("omega", "playlist", 3)
        config.set_value("omega", "repeat", 2)
        config.set_value("omega", "favorites", [0,0,0,0] if ver == 1 else [false,false,false,false])
        if ver == 3:
            config.set_value("omega", "shuffle", true)
        ck(config.save(PREF) == OK, "preference schema fixture created %d" % ver)
        var data = store.read(PREF)
        ck(data.ok and data.state.playlist == 0, "selected empty favourites falls back safely %d" % ver)
        ck(data.state.repeat == 2 and data.state.shuffle == (ver==3), "other fields survive empty favourites %d" % ver)
        ck(data.state.migrated == (ver!=3), "migration status correct %d" % ver)
    # Damaged v3 is protected against a real player editing its controls.
    var invalid_cases = [
        "[omega]\nversion=3\nplaylist=0\nrepeat=0\nfavorites=[ false, false, false, false ]\nshuffle=\"yes\"\n",
        "[omega]\nversion=3\nplaylist=0\nrepeat=0\nfavorites=[ false, false, false, false ]\n",
        "X".repeat(4097)
    ]
    for case_index in range(invalid_cases.size()):
        ck(_write(invalid_cases[case_index]), "corrupt fixture written %d" % case_index)
        var saved = _read()
        var bad = _new_player()
        ck(bad.preferences_load_blocked, "corrupt preferences cause protective lock %d" % case_index)
        bad.cycle_repeat()
        bad.toggle_favorite()
        bad.toggle_shuffle()
        ck(not bad.last_save_ok and _read() == saved, "corrupt file remains intact after edits %d" % case_index)
        bad.queue_free()
        yield(create_timer(0.04),"timeout")
    # Recovery: a clean, separately repaired configuration is loadable by a
    # NEW player instance (without ever deleting or silently overwriting data).
    var recovered={"playlist":1,"repeat":1,"favorites":[false,true,false,false],"shuffle":true}
    ck(store.write(PREF,recovered), "explicit test-only valid file repair")
    var restored = _new_player()
    ck(not restored.preferences_load_blocked and restored.last_save_ok, "valid file restores normal save authorization")
    ck(restored.playlists.playlist_index==1 and restored.playlists.repeat_index==1 and restored.playlists.shuffle_enabled, "repaired v3 settings restored")
    ck(restored.playlists.is_favorite(1) and not restored.is_playing(), "repaired favorites stay silent")
    restored.toggle_shuffle()
    ck(restored.last_save_ok and not store.read(PREF).state.shuffle, "valid repaired preferences can save normally")
    # An incompatible file can arrive AFTER a successful startup. That
    # external change must also be protected from stale UI-side writes.
    ck(_write(future), "external future schema fixture written after valid load")
    var external_bytes = _read()
    restored.toggle_shuffle()
    ck(restored.preferences_load_blocked and not restored.last_save_ok, "later incompatible disk change locks preference writes")
    ck(_read() == external_bytes, "late future file preserved byte for byte")
    restored.queue_free()
    yield(create_timer(0.04),"timeout")

    # Main/PCM ownership: the FFT GUI must not blank a working local PCM
    # source simply because bundled Ogg is stopped; loss of focus must clear
    # both the speaker and Main's live_audio / epoch ownership indicators.
    var app = load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(0.20),"timeout")
    ck(not app.live_audio and not app.offline_music.is_playing(), "initial app silent")
    ck(not app.offline_music.select_track("2"), "noninteger track selection rejected without playback")
    ck(not app.offline_music.select_track(1.5), "fractional track selection rejected")
    ck(not app.offline_music.select_track(-1) and not app.offline_music.select_track(4), "out-of-bounds track selection rejected")
    ck(app.offline_music.track_index == 0 and not app.offline_music.is_playing(), "invalid selection leaves original silent state")
    var baseline_volume = app.offline_music.player.volume_db
    app.offline_music.set_volume("LOUD")
    app.offline_music.set_volume(NAN)
    app.offline_music.set_volume(INF)
    ck(app.offline_music.player.volume_db == baseline_volume, "malformed volume requests cannot change speaker gain")
    ck(app.begin_explicit_local_pcm(), "explicit local PCM route starts with no streaming")
    ck(app.local_pcm.active and app.local_pcm.audio.playing and app.live_audio, "PCM and main player agree on active ownership")
    ck(app.local_pcm.audio.bus == "Milkdrop" and not app.offline_music.is_playing(), "PCM owns original FFT bus without Ogg overlap")
    app._process(0.02)
    ck(app.analysis_label.text == "LOCAL PCM / REAL AUDIO FFT", "local PCM is visible in main FFT presentation")
    var zeros = PoolByteArray()
    for _i in range(1024):
        zeros.append(0)
    ck(app.feed_explicit_local_pcm(zeros), "fictional silent PCM accepted through bounded staging")
    app._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    ck(not app.local_pcm.active and app.local_pcm.stage.buffered_bytes==0, "main focus-out clears actual PCM and pending blocks")
    ck(not app.live_audio and app.analysis_owner==null, "main focus-out revokes all prior analysis ownership")
    ck(not app.feed_explicit_local_pcm(zeros), "focus loss rejects late PCM")
    app._process(0.02)
    ck(app.analysis_label.text == "IDLE / NO AUDIO", "focus loss makes visible FFT state idle")
    ck(not app.offline_music.is_playing(), "focus loss never restarts bundled Ogg")
    ck(app.begin_explicit_local_pcm(), "explicit restart permitted after focus loss")
    ck(app.live_audio and app.local_pcm.active, "new session explicitly owns audio")
    app._stop_audio()
    ck(not app.live_audio and not app.local_pcm.active and app.analysis_owner == null, "explicit stop releases source and epoch")
    ck(not app.feed_explicit_local_pcm(zeros), "old PCM data cannot leak into new generation")
    ck(app.begin_explicit_local_pcm(), "app can start again explicitly")
    app._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    ck(not app.local_pcm.active and not app.live_audio, "app pause and focus-out both disarm playback")
    app._process(0.02)
    ck(app.analysis_label.text == "IDLE / NO AUDIO", "post-pause idle presentation")
    # TV remote B/Back should stop PCM, not quit, when it is active.
    ck(app.begin_explicit_local_pcm(), "PCM playback can start for TV Back test")
    app.music_ui.show_stage()
    app._handle_tv_back()
    ck(not app.live_audio and not app.local_pcm.active, "TV remote Back stops local PCM")
    ck(app.music_ui.visible, "remote Back keeps music stage visible on Stop")
    # The real bundled Ogg remains app-owned: losing focus must stop it as
    # well, with no silent auto-resume after the window regains focus.
    app._play_offline_music()
    yield(create_timer(0.08), "timeout")
    ck(app.offline_music.is_playing(), "explicit bundled music starts for focus lifecycle test")
    app._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
    ck(not app.offline_music.is_playing() and not app.live_audio, "focus loss stops original offline playback and resets main state")
    yield(create_timer(0.06), "timeout")
    ck(not app.offline_music.is_playing() and app.offline_music.track_index == 0, "no late finished event advances music after focus loss")
    # Invoke a simulated late finished callback to verify the generation
    # guard even if the host audio backend does not deliver such a callback.
    app.offline_music._on_finished()
    ck(not app.offline_music.is_playing() and app.offline_music.track_index == 0, "explicit Stop disarms late end-of-song callbacks")
    _remove()
    print("METHEXIS_HARDENING_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
