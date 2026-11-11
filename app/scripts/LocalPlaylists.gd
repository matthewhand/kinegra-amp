extends Reference
# Bounded, in-memory offline collection. No storage, imports,
# Media Assistant writes, random global seed or service calls.
const TRACK_COUNT = 4
const MAX_TRACKS = TRACK_COUNT + preload("res://scripts/UserLibraryStore.gd").MAX_IMPORTS
const PRESET_NAMES = ["ALL TRACKS", "NIGHT FLIGHT", "HEAVY ROTATION", "FAVOURITES"]
const PRESET_INDICES = [[0, 1, 2, 3], [0, 2, 3], [1, 3]]
const REPEAT = ["ALL", "ONE", "OFF"]
var playlist_index = 0
var repeat_index = 0
var favorites = [false, false, false, false]
var shuffle_enabled = false
var available_tracks = [true, true, true, true]
# A local RNG does not modify Godot's global random seed. The traversal
# remains a bounded permutation of the current collection, not a random walk.
var _rng = RandomNumberGenerator.new()
var _deck = []
var _deck_position = -1

func _init():
    _rng.randomize()

# Test-only deterministic seed; no production caller uses this API.
func set_shuffle_seed(value):
    if typeof(value) != TYPE_INT:
        return false
    _rng.seed = value
    _deck.clear()
    _deck_position = -1
    return true

func shuffle_name():
    return "ON" if shuffle_enabled else "OFF"

func _reset_deck(current):
    _deck.clear()
    _deck_position = -1
    var members = indices()
    if members.empty():
        return
    var first = current if current in members else members[0]
    var remaining = []
    for item in members:
        if item != first:
            remaining.append(item)
    # Fisher-Yates over at most three remaining songs, using the local RNG.
    for i in range(remaining.size() - 1, 0, -1):
        var j = _rng.randi_range(0, i)
        var swap = remaining[i]
        remaining[i] = remaining[j]
        remaining[j] = swap
    _deck.append(first)
    _deck.append_array(remaining)
    _deck_position = 0

func _deck_matches(current):
    if _deck_position < 0 or _deck_position >= _deck.size():
        return false
    if _deck[_deck_position] != current:
        return false
    var members = indices()
    if members.size() != _deck.size():
        return false
    for item in members:
        if not item in _deck:
            return false
    return true

func set_shuffle(enabled, current):
    if typeof(enabled) != TYPE_BOOL or not _valid_track(current):
        return false
    if shuffle_enabled != enabled:
        shuffle_enabled = enabled
        _deck.clear()
        _deck_position = -1
    if shuffle_enabled and not _deck_matches(current):
        _reset_deck(current)
    return true

func _step_shuffled(current, direction, automatic):
    if not _deck_matches(current):
        _reset_deck(current)
    if _deck.empty():
        return -1
    if direction < 0:
        # Previous follows played shuffle history only. At the beginning of
        # a fresh deck there is no prior song; never jump into the future.
        if _deck_position == 0:
            return current
        _deck_position -= 1
        return _deck[_deck_position]
    if _deck_position + 1 < _deck.size():
        _deck_position += 1
        return _deck[_deck_position]
    if automatic and repeat_name() == "OFF":
        return -1
    # A fresh cycle starts with the last played track as an anchor, so there
    # is never an immediate duplicate across the cycle boundary (>1 track).
    _reset_deck(current)
    if _deck.size() > 1:
        _deck_position = 1
    return _deck[_deck_position]

func playlist_name():
    return PRESET_NAMES[playlist_index]

func repeat_name():
    return REPEAT[repeat_index]

func _valid_track(index):
    return typeof(index) == TYPE_INT and index >= 0 and index < available_tracks.size()

func indices():
    if playlist_index == 3:
        var result = []
        for i in range(available_tracks.size()):
            if favorites[i] and available_tracks[i]:
                result.append(i)
        return result
    var result = []
    for i in (range(available_tracks.size()) if playlist_index == 0 else PRESET_INDICES[playlist_index]):
        if available_tracks[i]:
            result.append(i)
    return result

func set_availability(values):
    if typeof(values) != TYPE_ARRAY or values.size() < TRACK_COUNT or values.size() > MAX_TRACKS:
        return false
    for value in values:
        if typeof(value) != TYPE_BOOL:
            return false
    available_tracks = values.duplicate()
    while favorites.size() < values.size(): favorites.append(false)
    _deck.clear()
    _deck_position = -1
    return true

func choose_playlist(index, current):
    if typeof(index) != TYPE_INT or index < 0 or index >= PRESET_NAMES.size():
        return -1
    var proposed = [] if index == 3 else (range(available_tracks.size()) if index == 0 else PRESET_INDICES[index])
    if index == 3:
        for i in range(available_tracks.size()):
            if favorites[i]:
                proposed.append(i)
    var available = []
    for i in proposed:
        if available_tracks[i]:
            available.append(i)
    proposed = available
    if proposed.empty():
        return -1
    playlist_index = index
    var selected = current if current in proposed else proposed[0]
    if shuffle_enabled:
        _reset_deck(selected)
    return selected

func cycle_playlist(current):
    for step in range(1, PRESET_NAMES.size() + 1):
        var index = (playlist_index + step) % PRESET_NAMES.size()
        var result = choose_playlist(index, current)
        if result >= 0:
            return result
    return -1

func toggle_favorite(index):
    if not _valid_track(index):
        return false
    favorites[index] = not favorites[index]
    return favorites[index]

func is_favorite(index):
    return _valid_track(index) and favorites[index]

func cycle_repeat():
    repeat_index = (repeat_index + 1) % REPEAT.size()
    return repeat_name()

func step_track(current, direction, automatic=false):
    var ordered = indices()
    if ordered.empty() or not _valid_track(current) or not direction in [-1, 1]:
        return -1
    if automatic and repeat_name() == "ONE":
        return current
    if shuffle_enabled:
        return _step_shuffled(current, direction, automatic)
    var position = ordered.find(current)
    if position < 0:
        return ordered[0] if direction > 0 else ordered[ordered.size() - 1]
    var next = position + direction
    if next >= 0 and next < ordered.size():
        return ordered[next]
    if automatic and repeat_name() == "OFF":
        return -1
    return ordered[posmod(next, ordered.size())]

# Transactional loading: invalid states leave every existing choice unchanged.
func snapshot():
    return {"playlist": playlist_index, "repeat": repeat_index, "favorites": favorites.duplicate(), "shuffle": shuffle_enabled}

func restore(state):
    if typeof(state) != TYPE_DICTIONARY:
        return false
    var idx = state.get("playlist", null)
    var rep = state.get("repeat", null)
    var saved = state.get("favorites", null)
    var shuffled = state.get("shuffle", false)
    if typeof(shuffled) != TYPE_BOOL:
        return false
    if typeof(idx) != TYPE_INT or idx < 0 or idx > 3:
        return false
    if typeof(rep) != TYPE_INT or rep < 0 or rep > 2:
        return false
    if typeof(saved) != TYPE_ARRAY or saved.size() < TRACK_COUNT or saved.size() > MAX_TRACKS:
        return false
    for flag in saved:
        if typeof(flag) != TYPE_BOOL:
            return false
    if idx == 3 and not true in saved:
        return false
    playlist_index = idx
    repeat_index = rep
    favorites = saved.duplicate()
    while favorites.size() < available_tracks.size(): favorites.append(false)
    shuffle_enabled = shuffled
    _deck.clear()
    _deck_position = -1
    return true
