extends SceneTree
var failures=0
var checks=0
class FakePlatform:
    extends Reference
    var reply=""
    func offlineImportStatus():return reply
func check(ok,label):
    checks+=1
    if not ok:
        failures+=1
        print("FAIL "+label)
func _init():call_deferred("run")
func run():
    var session=load("res://scripts/OfflineImportSession.gd").new()
    get_root().add_child(session)
    var platform=FakePlatform.new()
    session.platform=platform
    var cases=[
        [{"state":"complete","imported":0,"skipped":0,"errors":33},true,"oversized_selection_all_files_fail"],
        [{"state":"complete","imported":32,"skipped":0,"errors":1},true,"oversized_selection_all_files_copied"],
        [{"state":"complete","imported":0,"skipped":32,"errors":1},true,"oversized_selection_all_files_duplicates"],
        [{"state":"complete","imported":33,"skipped":0,"errors":0},false,"copy_cap_not_relaxed"],
        [{"state":"complete","imported":0,"skipped":0,"errors":34},false,"error_cap_not_unbounded"],
        [{"state":"complete","imported":32,"skipped":1,"errors":0},false,"combined_copy_cap"],
        [{"state":"complete","imported":32,"skipped":0,"errors":2},false,"combined_outcome_cap"],
        [{"state":"complete","imported":0,"skipped":0,"errors":-1},false,"negative_rejected"],
        [{"state":"complete","imported":0,"skipped":0,"errors":0.5},false,"fraction_rejected"],
        [{"state":"complete","imported":0,"skipped":0,"errors":"33"},false,"string_rejected"]]
    for case in cases:
        session.state="copying";session.set_process(true)
        platform.reply=JSON.print(case[0]);session._poll()
        check((session.state=="complete")==case[1],case[2]+"_state")
        check(session.is_processing()!=case[1],case[2]+"_polling")
    session.queue_free()
    print("IMPORT_COUNT_BOUNDARY %d checks / %d failures" % [checks,failures])
    quit(1 if failures else 0)
