extends Reference
# Local-only, versioned Omega preferences. No tokens, stream addresses or MA state.
# A caller-provided path makes tests independent of actual user settings.
const CURRENT_VERSION = 4
const MAX_BYTES = 16384

func _valid_int(value, lo, hi):
    return typeof(value) == TYPE_INT and value >= lo and value <= hi

func _decode(config):
    if not config.has_section_key("omega", "version"):
        return {}
    var version = config.get_value("omega", "version")
    if not _valid_int(version, 1, CURRENT_VERSION):
        return {}
    var playlist = config.get_value("omega", "playlist", null)
    var repeat = config.get_value("omega", "repeat", null)
    var saved = config.get_value("omega", "favorites", null)
    if not _valid_int(playlist, 0, 3) or not _valid_int(repeat, 0, 2):
        return {}
    if typeof(saved) != TYPE_ARRAY or saved.size() < 4 or saved.size() > 1028 or (version < 4 and saved.size() != 4):
        return {}
    var flags = []
    for item in saved:
        if version == 1:
            if not _valid_int(item, 0, 1):
                return {}
            flags.append(item == 1)
        else:
            if typeof(item) != TYPE_BOOL:
                return {}
            flags.append(item)
    # Schema 1/2 had no shuffle flag; default it off on migration.
    var shuffle = false
    if version >= 3:
        if not config.has_section_key("omega", "shuffle"):
            return {}
        shuffle = config.get_value("omega", "shuffle")
        if typeof(shuffle) != TYPE_BOOL:
            return {}
    # Old files could encode an empty selected favourites collection.
    if playlist == 3 and not true in flags:
        playlist = 0
    return {"playlist": playlist, "repeat": repeat, "favorites": flags, "shuffle": shuffle, "migrated": version != CURRENT_VERSION}

func read(path):
    var f = File.new()
    if not f.file_exists(path):
        return {"ok": true, "found": false, "state": {}}
    if f.open(path, File.READ) != OK:
        return {"ok": false, "found": true, "state": {}}
    var length = f.get_len()
    if length < 1 or length > MAX_BYTES:
        f.close()
        return {"ok": false, "found": true, "state": {}}
    var contents = f.get_as_text()
    f.close()
    var config = ConfigFile.new()
    if config.parse(contents) != OK:
        return {"ok": false, "found": true, "state": {}}
    var state = _decode(config)
    return {"ok": not state.empty(), "found": true, "state": state}

func write(path, state):
    if typeof(state) != TYPE_DICTIONARY or not read(path)["ok"]:
        return false
    var flags = state.get("favorites", null)
    if not _valid_int(state.get("playlist", null), 0, 3) or not _valid_int(state.get("repeat", null), 0, 2):
        return false
    if typeof(flags) != TYPE_ARRAY or flags.size() < 4 or flags.size() > 1028:
        return false
    for flag in flags:
        if typeof(flag) != TYPE_BOOL:
            return false
    if typeof(state.get("shuffle", null)) != TYPE_BOOL:
        return false
    if state["playlist"] == 3 and not true in flags:
        return false
    var config = ConfigFile.new()
    config.set_value("omega", "version", CURRENT_VERSION)
    config.set_value("omega", "playlist", state["playlist"])
    config.set_value("omega", "repeat", state["repeat"])
    config.set_value("omega", "favorites", flags.duplicate())
    config.set_value("omega", "shuffle", state["shuffle"])
    # Temp file shares a directory with the target for same-volume rename.
    var temp = path + ".tmp"
    if config.save(temp) != OK:
        return false
    var f = File.new()
    if f.open(temp, File.READ) != OK:
        return false
    var length = f.get_len()
    f.close()
    var dir = Directory.new()
    if length < 1 or length > MAX_BYTES:
        dir.remove(temp)
        return false
    var result = dir.rename(temp, path)
    if result != OK:
        dir.remove(temp)
        return false
    return true
