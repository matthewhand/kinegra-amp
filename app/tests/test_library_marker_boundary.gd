extends SceneTree
const Store = preload("res://scripts/UserLibraryStore.gd")
var checks = 0
var failures = 0

func ck(ok, label):
    checks += 1
    if not ok:
        failures += 1
        printerr("MARKER_FAIL_" + label)
    else:
        print("MARKER_PASS_" + label)

func write(path, bytes):
    var file = File.new()
    if file.open(path, File.WRITE) != OK:
        return false
    file.store_buffer(bytes)
    var ok = file.get_error() == OK
    file.close()
    return ok

func source_audio():
    var f = File.new()
    if f.open("res://assets/music/track_01.ogg", File.READ) != OK: return PoolByteArray()
    var out = f.get_buffer(f.get_len())
    f.close()
    return out

func add_receipt(dir, audio, title):
    var filename = "import_" + File.new().get_sha256("res://assets/music/track_01.ogg") + ".ogg"
    var name = dir.plus_file(filename)
    if not write(name, audio): return ""
    if not write(name + ".meta.json", to_json({"version":1, "file":filename, "sha256":File.new().get_sha256("res://assets/music/track_01.ogg"),"bytes":audio.size(),"title":title}).to_utf8()): return ""
    return name

func new_dir(base, suffix):
    var folder = base.plus_file(suffix)
    Directory.new().make_dir_recursive(folder)
    return folder

func _init():
    call_deferred("run")

func run():
    var root = "user://marker-boundary-" + str(OS.get_ticks_msec())
    Directory.new().make_dir_recursive(root)
    var audio = source_audio()
    ck(audio.size() > 1000, "fixture_generated_audio_present")
    var first = new_dir(root, "first")
    var s = Store.new()
    s.directory = first
    ck(s.initialize(), "first_initialize")
    var f = add_receipt(first, audio, "A")
    ck(not f.empty(), "first_receipt_written")
    var blocker = first.plus_file("catalog-v1.json.new")
    ck(Directory.new().make_dir(blocker) == OK, "first_write_obstruction")
    ck(not s.refresh(), "first_catalog_write_failed")
    ck(not File.new().file_exists(first.plus_file("slots-assigned-v1")), "marker_not_published_before_first_catalog")
    ck(Directory.new().remove(blocker) == OK, "first_obstruction_removed")
    var restart = Store.new()
    restart.directory = first
    ck(restart.initialize() and not restart.blocked and restart.slots.size() == 1 and restart.available(0), "first_failure_restart_recovers_receipt")
    var staged = new_dir(root, "seeded")
    ck(not add_receipt(staged, audio, "B").empty(), "seeded_receipt")
    ck(write(staged.plus_file("catalog-v1.json"), to_json({"version":1, "slots":[]}).to_utf8()), "seeded_empty_catalog")
    ck(write(staged.plus_file("slots-assigned-v1"), "stable-slots-v1\n".to_utf8()), "seeded_marker")
    var seeded = Store.new()
    seeded.directory = staged
    ck(seeded.initialize() and seeded.slots.size() == 1 and seeded.available(0), "seeded_bootstrap_recovery")
    var marker = new_dir(root, "marker")
    var m = Store.new()
    m.directory = marker
    ck(m.initialize(), "marker_initialize")
    ck(not add_receipt(marker, audio, "C").empty(), "marker_receipt")
    var marker_block = marker.plus_file("slots-assigned-v1.new")
    ck(Directory.new().make_dir(marker_block) == OK, "marker_obstruction_created")
    ck(not m.refresh(), "first_marker_write_failure")
    ck(not File.new().file_exists(marker.plus_file("slots-assigned-v1")), "marker_failure_no_commit")
    ck(Directory.new().remove(marker_block) == OK, "marker_obstruction_removed")
    var mr = Store.new()
    mr.directory = marker
    ck(mr.initialize() and mr.slots.size() == 1 and mr.available(0), "marker_failure_recoverable")
    var existing = new_dir(root, "existing")
    var e = Store.new()
    e.directory = existing
    ck(e.initialize(), "existing_initialize")
    ck(not add_receipt(existing, audio, "D").empty(), "existing_receipt")
    ck(e.refresh() and e.slots.size() == 1, "existing_first_slot_committed")
    var old = File.new()
    ck(old.open(existing.plus_file("catalog-v1.json"), File.READ) == OK, "existing_catalog_read")
    var original = old.get_as_text()
    old.close()
    var cat = existing.plus_file("catalog-v1.json.new")
    ck(Directory.new().make_dir(cat) == OK, "existing_obstruction_created")
    var same = e.slots.duplicate(true)
    ck(not e._write_manifest(same), "existing_write_failure")
    ck(File.new().file_exists(existing.plus_file("slots-assigned-v1")), "existing_marker_preserved")
    var reread = File.new()
    ck(reread.open(existing.plus_file("catalog-v1.json"), File.READ) == OK, "existing_catalog_still_readable")
    ck(reread.get_as_text() == original, "existing_catalog_bytes_unchanged")
    reread.close()
    ck(Directory.new().remove(cat) == OK, "existing_obstruction_removed")
    var rr = Store.new()
    rr.directory = existing
    ck(rr.initialize() and rr.slots.size() == 1 and rr.slots[0].sha256 == e.slots[0].sha256, "existing_slot_identity_unchanged")
    ck(Directory.new().remove(existing.plus_file("catalog-v1.json")) == OK, "existing_catalog_removed_deliberately")
    var blocked = Store.new()
    blocked.directory = existing
    ck(not blocked.initialize() and blocked.blocked, "missing_committed_catalog_still_fails_closed")
    print("MARKER_CHECKS=" + str(checks) + " FAILURES=" + str(failures))
    quit(0 if failures == 0 else 1)
