extends Reference
# App-owned MP3/Ogg copies only. The Android picker writes trusted hash receipts;
# this bounded manifest assigns append-only slots so queues never change identity.
const MAX_IMPORTS = 1024
const MAX_FILE_BYTES = 67108864
const MAX_MANIFEST_BYTES = 1048576
const MAX_RECEIPT_BYTES = 2048
var directory = "user://offline_music"
var slots = []
var blocked = false
var last_error = ""

func _hex(value):
    if typeof(value) != TYPE_STRING or value.length() != 64: return false
    for c in value:
        if not c in "0123456789abcdef": return false
    return true

func _filename(value, digest):
    return typeof(value) == TYPE_STRING and _hex(digest) and value in ["import_" + digest + ".mp3", "import_" + digest + ".ogg"]

func _title(value):
    if typeof(value) != TYPE_STRING: return ""
    var clean = ""
    for c in value.substr(0, 240):
        if c.ord_at(0) >= 32 and c.ord_at(0) != 127 and not c in "/\\": clean += c
    return clean.strip_edges().substr(0, 120)

func _record(value, manifest):
    if typeof(value) != TYPE_DICTIONARY: return {}
    var digest = value.get("sha256")
    var name = value.get("file")
    var bytes = value.get("bytes")
    var title = _title(value.get("title"))
    if not _filename(name, digest) or not typeof(bytes) in [TYPE_INT, TYPE_REAL] or bytes != int(bytes) or bytes < 4 or bytes > MAX_FILE_BYTES or title.empty(): return {}
    if manifest and typeof(value.get("deleted")) != TYPE_BOOL: return {}
    return {"sha256":digest,"file":name,"bytes":int(bytes),"title":title,"deleted":value.get("deleted",false) if manifest else false}

func _json(path, limit):
    var f = File.new()
    if f.open(path, File.READ) != OK: return null
    if f.get_len() < 2 or f.get_len() > limit:
        f.close()
        return null
    var text = f.get_as_text()
    f.close()
    var parsed = JSON.parse(text)
    return parsed.result if parsed.error == OK else null

func _decode(value):
    if typeof(value) != TYPE_DICTIONARY or value.get("version") != 1 or typeof(value.get("slots")) != TYPE_ARRAY or value.slots.size() > MAX_IMPORTS: return null
    var result = []
    var seen = {}
    for entry in value.slots:
        var record = _record(entry, true)
        if record.empty() or seen.has(record.sha256): return null
        seen[record.sha256] = true
        result.append(record)
    return result

func initialize():
    slots = []
    blocked = false
    last_error = ""
    var dir = Directory.new()
    if dir.make_dir_recursive(directory) != OK and not dir.dir_exists(directory):
        blocked = true
        last_error = "STORAGE UNAVAILABLE"
        return false
    var path = directory.plus_file("catalog-v1.json")
    if not File.new().file_exists(path) and File.new().file_exists(directory.plus_file("slots-assigned-v1")):
        blocked = true
        last_error = "CATALOG MISSING / IMPORTS PAUSED"
        return false
    if File.new().file_exists(path):
        var decoded = _decode(_json(path, MAX_MANIFEST_BYTES))
        if decoded == null:
            blocked = true
            last_error = "CATALOG NEEDS REPAIR / KEPT UNCHANGED"
            return false
        slots = decoded
    # Finish or roll back an interrupted delete according to the committed slot.
    for record in slots:
        for suffix in ["", ".meta.json"]:
            var original = directory.plus_file(record.file + suffix)
            var staged = original + ".delete"
            if File.new().file_exists(staged):
                if record.deleted:
                    dir.remove(staged)
                elif not File.new().file_exists(original):
                    dir.rename(staged, original)
    return refresh()

func _audio_valid(record):
    var f = File.new()
    if f.open(directory.plus_file(record.file), File.READ) != OK: return false
    var size = f.get_len()
    var head = f.get_buffer(min(4, size))
    f.close()
    if size != record.bytes or head.size() < 4: return false
    if record.file.ends_with(".ogg"): return head == PoolByteArray([79,103,103,83])
    return (head[0] == 73 and head[1] == 68 and head[2] == 51) or (head[0] == 255 and (head[1] & 224) == 224)

func available(index):
    return typeof(index) == TYPE_INT and index >= 0 and index < slots.size() and not slots[index].deleted and _audio_valid(slots[index])

func availability():
    var values = []
    for index in range(slots.size()): values.append(available(index))
    return values

func refresh():
    if blocked: return false
    last_error = ""
    var overflow = false
    var dir = Directory.new()
    if dir.open(directory) != OK: return false
    var names = []
    dir.list_dir_begin(true, true)
    var name = dir.get_next()
    var visited = 0
    while not name.empty() and visited < 4096:
        visited += 1
        if not dir.current_is_dir() and name.ends_with(".meta.json") and name.length() <= 90: names.append(name)
        name = dir.get_next()
    dir.list_dir_end()
    if not name.empty():
        last_error = "TOO MANY STORAGE ENTRIES"
        return false
    names.sort()
    var next = slots.duplicate(true)
    var positions = {}
    for i in range(next.size()): positions[next[i].sha256] = i
    for receipt_name in names:
        var raw = _json(directory.plus_file(receipt_name), MAX_RECEIPT_BYTES)
        if typeof(raw) != TYPE_DICTIONARY or raw.get("version") != 1: continue
        var record = _record(raw, false)
        if record.empty() or receipt_name != record.file + ".meta.json" or not _audio_valid(record): continue
        if positions.has(record.sha256):
            var i = positions[record.sha256]
            if next[i].file == record.file and next[i].bytes == record.bytes: next[i].deleted = false
        elif next.size() < MAX_IMPORTS:
            positions[record.sha256] = next.size()
            next.append(record)
        else:
            last_error = "LIBRARY SLOT LIMIT REACHED / RESTORE EXISTING TRACKS ONLY"
            overflow = true
    if to_json(next) == to_json(slots): return not overflow
    if not _write_manifest(next):
        last_error = "COULD NOT SAVE CATALOG"
        return false
    slots = next
    return not overflow

func _write_manifest(records):
    if blocked: return false
    var path = directory.plus_file("catalog-v1.json")
    if File.new().file_exists(path) and _decode(_json(path, MAX_MANIFEST_BYTES)) == null:
        blocked = true
        return false
    var encoded = to_json({"version":1,"slots":records})
    if encoded.to_utf8().size() > MAX_MANIFEST_BYTES: return false
    # Once any slot has been assigned, a lost manifest must not permit reindexing.
    var marker = directory.plus_file("slots-assigned-v1")
    if not records.empty() and not File.new().file_exists(marker):
        var flag = File.new()
        if flag.open(marker + ".new", File.WRITE) != OK: return false
        flag.store_string("stable-slots-v1\n")
        var flagged = flag.get_error() == OK
        flag.close()
        if not flagged or Directory.new().rename(marker + ".new", marker) != OK: return false
    var f = File.new()
    var temp = path + ".new"
    if f.open(temp, File.WRITE) != OK: return false
    f.store_string(encoded)
    var ok = f.get_error() == OK
    f.close()
    var dir = Directory.new()
    if not ok or dir.rename(temp, path) != OK:
        dir.remove(temp)
        return false
    return true

func remove_track(index):
    if blocked or typeof(index) != TYPE_INT or index < 0 or index >= slots.size(): return false
    var record = slots[index]
    if record.deleted: return true
    var dir = Directory.new()
    var renamed = []
    for suffix in ["", ".meta.json"]:
        var original = directory.plus_file(record.file + suffix)
        if File.new().file_exists(original):
            if File.new().file_exists(original + ".delete") or dir.rename(original, original + ".delete") != OK:
                for previous in renamed: dir.rename(previous + ".delete", previous)
                return false
            renamed.append(original)
    var next = slots.duplicate(true)
    next[index].deleted = true
    if not _write_manifest(next):
        for original in renamed: dir.rename(original + ".delete", original)
        return false
    slots = next
    for original in renamed: dir.remove(original + ".delete")
    return true

func load_track(index):
    if not available(index): return null
    var f = File.new()
    if f.open(directory.plus_file(slots[index].file), File.READ) != OK: return null
    var data = f.get_buffer(f.get_len())
    f.close()
    var stream = AudioStreamMP3.new() if slots[index].file.ends_with(".mp3") else AudioStreamOGGVorbis.new()
    stream.data = data
    stream.loop = false
    return stream if stream.get_length() > 0 else null
