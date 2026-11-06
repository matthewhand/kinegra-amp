extends SceneTree
var failures = 0
var checks = 0
var base = "user://test_user_library_" + str(OS.get_ticks_msec())
const Store = preload("res://scripts/UserLibraryStore.gd")
class FailingStore extends "res://scripts/UserLibraryStore.gd":
    func _write_manifest(_records): return false

func check(ok, name):
    checks += 1
    if not ok:
        failures += 1
        print("FAIL_USER_LIBRARY ", name)

func put(path, bytes):
    var f = File.new()
    if f.open(path, File.WRITE) != OK: return false
    f.store_buffer(bytes)
    f.close()
    return true

func receipt(store, digest, title="Synthetic song", extension="ogg"):
    var file = "import_" + digest + "." + extension
    var bytes = load("res://scripts/OfflineMusic.gd").SOURCES
    var audio = load(bytes[0]).data
    if extension == "mp3": audio = Marshalls.base64_to_raw("SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjYwLjE2LjEwMAAAAAAAAAAAAAAA//MgxAAAAANIAAAAAExBTUUzLjEwMFVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVVVVVVVVVf/zIsQnAAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//MgxE8AAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/zIMR2AAADSAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/8yDEnQAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//MixMQAAANIAAAAAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/8yDE2AAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV")
    put(store.directory.plus_file(file), audio)
    put(store.directory.plus_file(file + ".meta.json"), to_json({"version":1,"file":file,"title":title,"bytes":audio.size(),"sha256":digest}).to_utf8())
    return file

func clean(directory):
    var dir = Directory.new()
    if dir.open(directory) != OK: return
    dir.list_dir_begin(true, true)
    var name = dir.get_next()
    var names = []
    while not name.empty():
        names.append(name)
        name = dir.get_next()
    dir.list_dir_end()
    for item in names: dir.remove(item)
    Directory.new().remove(directory)

func _init():
    call_deferred("run")

func run():
    var store = Store.new()
    store.directory = base
    check(store.initialize() and store.slots.empty(), "empty_initialize")
    var hash_a = "a".repeat(64)
    var hash_b = "b".repeat(64)
    var name_a = receipt(store, hash_a)
    check(store.refresh() and store.slots.size() == 1 and store.available(0), "receipt_adopted")
    check(store.load_track(0) is AudioStreamOGGVorbis, "actual_ogg_decodes")
    check(store.refresh() and store.slots.size() == 1, "duplicate_receipt_no_slot")
    var stable = Store.new()
    stable.directory = base
    check(stable.initialize() and stable.slots[0].sha256 == hash_a, "stable_restart")
    var outside = base + "_outside.ogg"
    put(outside, PoolByteArray([1,2,3,4]))
    put(base.plus_file("bad.meta.json"), to_json({"version":1,"file":"../outside.ogg","title":"bad","bytes":4,"sha256":hash_b}).to_utf8())
    check(store.refresh() and store.slots.size() == 1, "path_traversal_receipt_ignored")
    var failing = FailingStore.new()
    failing.directory = base
    failing.slots = store.slots.duplicate(true)
    check(not failing.remove_track(0) and File.new().file_exists(base.plus_file(name_a)) and File.new().file_exists(base.plus_file(name_a + ".meta.json")), "delete_write_failure_rolls_back_files")
    check(store.remove_track(0) and store.slots.size() == 1 and store.slots[0].deleted and not store.available(0), "tombstone_keeps_slot")
    check(File.new().file_exists(outside), "delete_never_touches_source")
    receipt(store, hash_b, "Second song")
    check(store.refresh() and store.slots.size() == 2 and store.slots[0].deleted and store.slots[1].sha256 == hash_b, "different_content_appends")
    receipt(store, hash_a, "Reimport same song")
    check(store.refresh() and store.slots.size() == 2 and store.available(0) and store.slots[0].sha256 == hash_a, "same_hash_restores_original_slot")
    receipt(store, "c".repeat(64), "Synthetic MP3", "mp3")
    check(store.refresh() and store.load_track(2) is AudioStreamMP3, "actual_mp3_decodes")
    var dir = Directory.new()
    dir.rename(base.plus_file(name_a), base.plus_file(name_a + ".delete"))
    dir.rename(base.plus_file(name_a + ".meta.json"), base.plus_file(name_a + ".meta.json.delete"))
    check(stable.initialize() and stable.available(0), "crash_before_commit_restores_staged_files")
    var removed = stable.slots.duplicate(true)
    removed[0].deleted = true
    stable._write_manifest(removed)
    dir.rename(base.plus_file(name_a), base.plus_file(name_a + ".delete"))
    dir.rename(base.plus_file(name_a + ".meta.json"), base.plus_file(name_a + ".meta.json.delete"))
    check(stable.initialize() and stable.slots[0].deleted and not File.new().file_exists(base.plus_file(name_a + ".delete")), "crash_after_commit_finishes_delete")
    var bad = {"version":9,"slots":[]}
    put(base.plus_file("catalog-v1.json"), to_json(bad).to_utf8())
    check(not stable.initialize() and stable.blocked and not stable.refresh() and not stable.remove_track(0), "future_manifest_fails_closed")
    check(stable._json(base.plus_file("catalog-v1.json"),1000).version == 9, "future_manifest_not_overwritten")
    put(base.plus_file("catalog-v1.json"), to_json({"version":1,"slots":[null]}).to_utf8())
    check(not stable.initialize() and stable.blocked, "corrupt_manifest_fails_closed")
    dir.remove(base.plus_file("catalog-v1.json"))
    dir.remove(base.plus_file("slots-assigned-v1"))
    put(base.plus_file("huge.meta.json"), "x".repeat(4096).to_utf8())
    check(stable.initialize() and stable.slots.size() == 2, "oversize_receipt_ignored")
    var record = stable.slots[0].duplicate()
    record.bytes = Store.MAX_FILE_BYTES + 1
    check(stable._record(record,true).empty(), "oversize_audio_record_rejected")
    record = stable.slots[0].duplicate()
    record.file = "import_" + hash_b + ".flac"
    check(stable._record(record,true).empty(), "unsupported_format_rejected")
    record = stable.slots[0].duplicate()
    record.bytes += 1
    check(not stable._audio_valid(record), "size_mismatch_unavailable")
    check(stable._title("  bad/\\name\n" + "x".repeat(200)).length() == 120, "bounded_sanitized_title")
    var maximum = []
    for i in range(1024):
        var digest = ("%064x" % i)
        maximum.append({"sha256":digest,"file":"import_"+digest+".ogg","title":"Synthetic","bytes":4,"deleted":true})
    check(stable._decode({"version":1,"slots":maximum}) != null, "maximum_stable_slots_valid")
    var full = Store.new()
    full.directory = base + "_full"
    full.initialize()
    full._write_manifest(maximum)
    full.slots = maximum.duplicate(true)
    receipt(full,"f".repeat(64))
    check(not full.refresh() and full.slots.size() == 1024 and not full.last_error.empty(),"overflow_not_reported_as_available")
    clean(full.directory)
    maximum.append(maximum[0].duplicate())
    check(stable._decode({"version":1,"slots":maximum}) == null, "slot_limit_enforced")
    check(stable._decode({"version":1,"slots":[record,record]}) == null, "duplicate_hash_manifest_rejected")
    dir.remove(base.plus_file("catalog-v1.json"))
    check(not stable.initialize() and stable.blocked, "missing_assigned_manifest_cannot_reindex")
    clean(base)
    Directory.new().remove(outside)
    print("USER_LIBRARY_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures == 0 else 1)
