extends Node
# User-owned offline music; the distribution contains no bundled songs.
# Four unavailable legacy slots preserve imported-track and saved-queue indices.
signal track_changed(title)
signal music_state_changed(playing)
signal playlist_changed(name)
signal favorite_changed(is_favorite)
signal repeat_changed(mode)
signal shuffle_changed(enabled)
signal library_changed
signal queue_changed
const MAX_QUEUE = preload("res://scripts/QueueStore.gd").MAX_QUEUE
var upcoming_queue = []
var queue_store = preload("res://scripts/QueueStore.gd").new()
var queue_path = "user://methexis_up_next.cfg"
var queue_save_ok = true
var queue_load_blocked = false
const TITLES = ["Legacy track 1", "Legacy track 2", "Legacy track 3", "Legacy track 4"]
const SOURCES = []
var player = null
var track_index = 0
var sample_store = null
var user_library = preload("res://scripts/UserLibraryStore.gd").new()
# Guard against delayed AudioStreamPlayer.finished after an explicit Stop or
# focus loss. Only a user-started/unpaused track may auto-advance.
var _advance_on_natural_finish = false
var _pending_play_until_ms = 0
# Reserve a queued item until the backend confirms audio actually started.
var _pending_queue_index = -1
var playlists = preload("res://scripts/LocalPlaylists.gd").new()
var playlist_store = preload("res://scripts/PlaylistStore.gd").new()
var playlist_path = "user://methexis_omega_playlists.cfg"
var last_save_ok = true
# A corrupt or unsupported saved file must never be overwritten by casual
# UI edits; the owner can repair/replace that file outside this app.
var preferences_load_blocked = false

func restore_preferences():
    # Offline suites opt out explicitly; never read or write real preferences.
    if OS.get_environment("METHEXIS_SOURCE_TEST") == "1" and playlist_path == "user://methexis_omega_playlists.cfg":
        return true
    var result = playlist_store.read(playlist_path)
    if not result["ok"]:
        preferences_load_blocked = true
        last_save_ok = false
        return false
    preferences_load_blocked = false
    last_save_ok = true
    if not result["found"]:
        return true
    if result["state"].favorites.size() > track_count():
        preferences_load_blocked = true
        return false
    if not playlists.restore(result["state"]):
        return false
    # A saved collection may exclude the default first track. Move the silent
    # selection to a member before creating/loading the audio player.
    var allowed = playlists.indices()
    # A selected legacy mix may contain only songs absent from this distribution.
    # Keep imports/favorites/repeat/shuffle; do not rewrite the saved file at boot.
    if allowed.empty() and true in playlists.available_tracks:
        playlists.playlist_index = 0
        allowed = playlists.indices()
    if not track_index in allowed and not allowed.empty():
        track_index = allowed[0]
    # Valid legacy states are applied without autoplay; next successful edit writes v4.
    return true

func persist_preferences():
    if OS.get_environment("METHEXIS_SOURCE_TEST") == "1" and playlist_path == "user://methexis_omega_playlists.cfg":
        return true
    if preferences_load_blocked:
        last_save_ok = false
        return false
    # A different process/app version may have changed the file since this
    # player started. Revalidate before replacing it, especially to avoid
    # silently clobbering future-version preferences with older state.
    var disk = playlist_store.read(playlist_path)
    if not disk["ok"]:
        preferences_load_blocked = true
        last_save_ok = false
        return false
    last_save_ok = playlist_store.write(playlist_path, playlists.snapshot())
    return last_save_ok


func _ready():
    if OS.get_environment("METHEXIS_SOURCE_TEST") != "1" and SOURCES.size() == 4:
        sample_store = load("res://scripts/BundledSampleStore.gd").new()
        sample_store.initialize(SOURCES)
        playlists.set_availability(sample_store.availability())
    if OS.get_environment("METHEXIS_SOURCE_TEST") != "1": user_library.initialize()
    _refresh_availability()
    restore_preferences()
    restore_queue()
    var available = playlists.indices()
    if not track_index in available and not available.empty():
        track_index = available[0]
    player = AudioStreamPlayer.new()
    player.name = "OfflineMusicPlayer"
    player.bus = "Milkdrop"
    player.volume_db = -9.0
    add_child(player)
    player.connect("finished", self, "_on_finished")
    # No autoplay. Importing or selecting music never starts it.
    _load_track()

func _load_track():
    if player == null:
        return
    _advance_on_natural_finish = false
    _pending_play_until_ms = 0
    _pending_queue_index = -1
    # Imported Ogg resources loop by default. Never mutate the shared asset.
    # Completion and shuffle/repeat are controlled by this player instead.
    player.stream = null
    if not available(track_index): return
    if track_index >= 4:
        player.stream = user_library.load_track(track_index - 4)
    elif sample_store != null:
        player.stream = sample_store.load_track(track_index)
    elif track_index < SOURCES.size():
        var original = load(SOURCES[track_index])
        if original != null: player.stream = original.duplicate()
    if player.stream != null:
        player.stream.loop = false

func track_count():
    return 4 + user_library.slots.size()

func get_title(index):
    if typeof(index) != TYPE_INT or index < 0 or index >= track_count(): return "Unavailable track"
    return TITLES[index] if index < 4 else user_library.slots[index - 4].title

func available(index):
    return typeof(index) == TYPE_INT and index >= 0 and index < playlists.available_tracks.size() and playlists.available_tracks[index]

func _refresh_availability():
    var values = sample_store.availability() if sample_store != null else ([true,true,true,true] if OS.get_environment("METHEXIS_SOURCE_TEST") == "1" and SOURCES.size() == 4 else [false,false,false,false])
    values.append_array(user_library.availability())
    playlists.set_availability(values)

func refresh_user_library():
    var result = user_library.refresh()
    _refresh_availability()
    emit_signal("library_changed")
    return result

func adopt_verified_queue_copy(record):
    var index=user_library.adopt_verified_copy(record)
    if index<0:return -1
    var track=4+index
    var values=playlists.available_tracks.duplicate()
    while values.size()<track_count():values.append(false)
    values[track]=true
    playlists.set_availability(values)
    emit_signal("library_changed")
    return index

func remove_library_track(index):
    if typeof(index) != TYPE_INT or index < 0 or index >= track_count(): return false
    var ok = sample_store != null and sample_store.remove_track(index) if index < 4 else user_library.remove_track(index - 4)
    if not ok: return false
    if index == track_index:
        stop()
        _refresh_availability()
        var remaining = playlists.indices()
        if not remaining.empty(): track_index = remaining[0]
        _load_track()
    else:
        _refresh_availability()
    emit_signal("library_changed")
    return true

func remove_bundled_track(index):
    return remove_library_track(index) if typeof(index) == TYPE_INT and index >= 0 and index < 4 else false

func restore_bundled_tracks():
    if sample_store == null: return false
    var restored = sample_store.restore(SOURCES)
    _refresh_availability()
    if player != null and player.stream == null and available(track_index): _load_track()
    emit_signal("library_changed")
    return restored

func play():
    if player == null or player.stream == null:
        return false
    if player.playing:
        if player.stream_paused:
            player.stream_paused = false
    else:
        player.play()
    _advance_on_natural_finish = is_playing()
    # Immediately after Stop/Play, the audio backend can report playing=false
    # for a frame. Do not permanently disarm real completion in that case.
    _pending_play_until_ms = 0 if _advance_on_natural_finish else OS.get_ticks_msec() + 700
    emit_signal("track_changed", current_title())
    emit_signal("music_state_changed", is_playing())
    return is_playing()

func _process(_delta):
    if _pending_play_until_ms == 0:
        return
    if is_playing():
        _pending_play_until_ms = 0
        _advance_on_natural_finish = true
        if _pending_queue_index >= 0 and not upcoming_queue.empty() and upcoming_queue[0] == _pending_queue_index:
            upcoming_queue.pop_front()
            _changed_queue()
        _pending_queue_index = -1
        emit_signal("music_state_changed", true)
    elif OS.get_ticks_msec() >= _pending_play_until_ms:
        # An unsuccessful Play request must not arm a later unrelated source.
        _pending_play_until_ms = 0
        _pending_queue_index = -1

func is_playing():
    return player != null and player.playing and not player.stream_paused

func toggle():
    if is_playing():
        _advance_on_natural_finish = false
        _pending_play_until_ms = 0
        player.stream_paused = true
        emit_signal("music_state_changed", false)
        return false
    return play()

func stop():
    _advance_on_natural_finish = false
    _pending_play_until_ms = 0
    _pending_queue_index = -1
    if player == null:
        return
    player.stop()
    emit_signal("music_state_changed", false)

func select_track(index):
    if typeof(index) != TYPE_INT or index < 0 or index >= track_count() or player == null:
        return false
    if not available(index):
        return false
    _advance_on_natural_finish = false
    player.stop()
    track_index = index
    _load_track()
    emit_signal("favorite_changed", playlists.is_favorite(track_index))
    return play()

# Explicitly cue a local track without starting it. This never
# starts audio and never changes preferences or Music Assistant state.
func cue_track(index):
    if typeof(index) != TYPE_INT or index < 0 or index >= track_count():
        return false
    if not index in playlists.indices() or player == null:
        return false
    stop()
    track_index = index
    _load_track()
    if playlists.shuffle_enabled:
        playlists.set_shuffle(true, track_index)
    emit_signal("track_changed", current_title())
    emit_signal("favorite_changed", playlists.is_favorite(track_index))
    return true

# Queue stores local library indices only, never MA commands.
func restore_queue():
    if OS.get_environment("METHEXIS_SOURCE_TEST")=="1" and queue_path=="user://methexis_up_next.cfg": return true
    var data=queue_store.read(queue_path)
    queue_load_blocked=not data["ok"]
    queue_save_ok=data["ok"]
    if not data["ok"]: return false
    for index in data["items"]:
        if index >= track_count():
            queue_load_blocked = true
            queue_save_ok = false
            return false
    upcoming_queue=data["items"].duplicate()
    return true

func _save_queue():
    if OS.get_environment("METHEXIS_SOURCE_TEST")=="1" and queue_path=="user://methexis_up_next.cfg": return true
    if queue_load_blocked:
        queue_save_ok=false
        return false
    queue_save_ok=queue_store.write(queue_path,upcoming_queue)
    return queue_save_ok

func _changed_queue():
    _save_queue()
    emit_signal("queue_changed")
func queue_track(index):
    if typeof(index)!=TYPE_INT or index<0 or index>=track_count() or not available(index) or upcoming_queue.size()>=MAX_QUEUE:
        return false
    _pending_queue_index = -1 # An edit invalidates a pending reservation.
    upcoming_queue.append(index)
    _changed_queue()
    return true

func replace_queue(items):
    if queue_load_blocked or not queue_store.valid(items,track_count()):return false
    for index in items:
        if not available(index):return false
    if not queue_store.write(queue_path,items):
        queue_save_ok=false
        return false
    upcoming_queue=items.duplicate()
    _pending_queue_index=-1
    queue_save_ok=true
    emit_signal("queue_changed")
    return true

func queue_remove(position):
    if typeof(position)!=TYPE_INT or position<0 or position>=upcoming_queue.size():
        return false
    _pending_queue_index = -1
    upcoming_queue.remove(position)
    _changed_queue()
    return true

func queue_move(position,direction):
    if typeof(position)!=TYPE_INT or not direction in [-1,1] or position<0 or position>=upcoming_queue.size():
        return false
    var dest=position+direction
    if dest<0 or dest>=upcoming_queue.size():
        return false
    _pending_queue_index = -1
    var item=upcoming_queue[position]
    upcoming_queue[position]=upcoming_queue[dest]
    upcoming_queue[dest]=item
    _changed_queue()
    return true

func queue_clear():
    _pending_queue_index = -1
    upcoming_queue.clear()
    _changed_queue()

# 0: empty, 1: started or pending, -1: audio failed (keep queued item).
func _play_queued():
    if _pending_queue_index >= 0 and _pending_play_until_ms > 0:
        return 1 # A delayed start is already in flight.
    while not upcoming_queue.empty():
        var index=upcoming_queue[0]
        if not available(index):
            upcoming_queue.pop_front()
            _changed_queue()
            continue
        if select_track(index):
            upcoming_queue.pop_front()
            _changed_queue()
            return 1
        if _pending_play_until_ms > 0:
            _pending_queue_index = index
            return 1
        return -1
    return 0

func next_track():
    var queued=_play_queued()
    if queued!=0:
        return queued>0
    var index = playlists.step_track(track_index, 1)
    return select_track(index) if index >= 0 else false

func previous_track():
    var index = playlists.step_track(track_index, -1)
    return select_track(index) if index >= 0 else false

func choose_playlist(index):
    var chosen = playlists.choose_playlist(index, track_index)
    if chosen < 0 or player == null:
        return false
    # Switching collections never starts audio without an explicit Play.
    stop()
    track_index = chosen
    _load_track()
    persist_preferences()
    emit_signal("playlist_changed", playlists.playlist_name())
    emit_signal("track_changed", current_title())
    emit_signal("favorite_changed", playlists.is_favorite(track_index))
    return true

func cycle_playlist():
    var chosen = playlists.cycle_playlist(track_index)
    if chosen < 0:
        return false
    return choose_playlist(playlists.playlist_index)

func toggle_favorite():
    var favorite = playlists.toggle_favorite(track_index)
    # Removing the selected favourite must never leave an empty playable
    # collection or an out-of-list current track. No implicit playback.
    if playlists.playlist_index == 3 and not favorite:
        var allowed = playlists.indices()
        if allowed.empty():
            playlists.choose_playlist(0, track_index)
        elif not track_index in allowed:
            stop()
            track_index = allowed[0]
            _load_track()
            emit_signal("track_changed", current_title())
            emit_signal("favorite_changed", playlists.is_favorite(track_index))
    persist_preferences()
    emit_signal("favorite_changed", playlists.is_favorite(track_index))
    emit_signal("playlist_changed", playlists.playlist_name())
    return favorite

func toggle_shuffle():
    if not playlists.set_shuffle(not playlists.shuffle_enabled, track_index):
        return false
    persist_preferences()
    emit_signal("shuffle_changed", playlists.shuffle_enabled)
    return playlists.shuffle_enabled

func cycle_repeat():
    var mode = playlists.cycle_repeat()
    persist_preferences()
    emit_signal("repeat_changed", mode)
    return mode

func duration_seconds():
    if player == null or player.stream == null:
        return 0.0
    return max(0.0, float(player.stream.get_length()))

func progress_seconds():
    if player == null or not player.playing:
        return 0.0
    return clamp(float(player.get_playback_position()), 0.0, duration_seconds())

func progress_fraction():
    var length = duration_seconds()
    return clamp(progress_seconds() / length, 0.0, 1.0) if length > 0.001 else 0.0

func current_title():
    return get_title(track_index) if available(track_index) else "No local track selected"

func set_volume(value):
    if typeof(value) in [TYPE_INT, TYPE_REAL] and player != null:
        if not is_nan(float(value)) and not is_inf(float(value)):
            var db=clamp(float(value), -60.0, 0.0)
            # All app-owned playback routes share this bus, including the
            # Sendspin player created later. Keep per-player gain neutral so
            # offline playback is attenuated exactly once.
            var bus=AudioServer.get_bus_index("Milkdrop")
            if bus>=0:
                AudioServer.set_bus_volume_db(bus,db)
                player.volume_db=0.0
            else:
                player.volume_db=db

func _on_finished():
    # Some audio backends surface finished after stop. Never interpret that
    # late event as a natural end-of-track and start new audio.
    if not _advance_on_natural_finish or player == null or player.playing:
        return
    _advance_on_natural_finish = false
    if _play_queued()!=0:
        return
    var upcoming = playlists.step_track(track_index, 1, true)
    if upcoming < 0:
        stop()
        return
    select_track(upcoming)

func suspend_for_background():
    # Never resume sound implicitly after a real app pause,
    # including if finished arrives in a subsequent Godot audio callback.
    stop()

func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED:
        suspend_for_background()

# Offline position controls are explicitly guarded against autoplay.
func seek_relative(offset_seconds):
    if not typeof(offset_seconds) in [TYPE_INT, TYPE_REAL]:
        return false
    var delta = float(offset_seconds)
    if is_nan(delta) or is_inf(delta):
        return false
    if player == null or player.stream == null or not player.playing:
        return false
    var duration = duration_seconds()
    if is_nan(duration) or is_inf(duration) or duration <= 0.5:
        return false
    var was_paused = player.stream_paused
    var target = clamp(progress_seconds() + delta, 0.0, duration - 0.5)
    player.seek(target)
    player.stream_paused = was_paused
    return player.playing and player.stream_paused == was_paused
