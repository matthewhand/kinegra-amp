extends Reference
# Extract once to private writable storage. Deletion persists until explicit restore.
const COUNT = 4
const MAX_BYTES = 16777216
var directory = "user://bundled_music"

func track_path(index):
    return directory.plus_file("track_%02d.ogg" % (index + 1)) if typeof(index) == TYPE_INT and index >= 0 and index < COUNT else ""

func available(index):
    var path = track_path(index)
    var f = File.new()
    if path.empty() or f.open(path, File.READ) != OK:
        return false
    var valid = f.get_len() > 4 and f.get_len() <= MAX_BYTES and f.get_buffer(4) == PoolByteArray([79,103,103,83])
    f.close()
    return valid

func availability():
    var result = []
    for i in range(COUNT):
        result.append(available(i))
    return result

func initialize(sources):
    var marker = File.new()
    var path = directory.plus_file("installed-v1")
    if marker.file_exists(path):
        if marker.open(path, File.READ) != OK:
            return false
        var valid = marker.get_as_text() == "samples-v1\n"
        marker.close()
        return valid
    return restore(sources)

func restore(sources):
    if typeof(sources) != TYPE_ARRAY or sources.size() != COUNT:
        return false
    var dir = Directory.new()
    if dir.make_dir_recursive(directory) != OK and not dir.dir_exists(directory):
        return false
    for i in range(COUNT):
        if available(i):
            continue
        # Never overwrite an unexpected existing file; restore is not repair.
        var path = track_path(i)
        if File.new().file_exists(path):
            return false
        var original = load(sources[i])
        if not (original is AudioStreamOGGVorbis):
            return false
        var data = original.data
        if data.size() < 4 or data.size() > MAX_BYTES:
            return false
        var temporary = path + ".new"
        var out = File.new()
        if out.open(temporary, File.WRITE) != OK:
            return false
        out.store_buffer(data)
        var written = out.get_error() == OK
        out.close()
        if not written or dir.rename(temporary, path) != OK:
            dir.remove(temporary)
            return false
    var marker_path = directory.plus_file("installed-v1")
    if File.new().file_exists(marker_path):
        return true
    var marker = File.new()
    if marker.open(marker_path + ".new", File.WRITE) != OK:
        return false
    marker.store_string("samples-v1\n")
    var written = marker.get_error() == OK
    marker.close()
    return written and dir.rename(marker_path + ".new", marker_path) == OK

func remove_track(index):
    var path = track_path(index)
    if path.empty():
        return false
    return not File.new().file_exists(path) or Directory.new().remove(path) == OK

func load_track(index):
    if not available(index):
        return null
    var input = File.new()
    if input.open(track_path(index), File.READ) != OK:
        return null
    var bytes = input.get_buffer(input.get_len())
    input.close()
    var stream = AudioStreamOGGVorbis.new()
    stream.data = bytes
    stream.loop = false
    return stream if stream.get_length() > 0 else null
