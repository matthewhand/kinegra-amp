extends SceneTree
class FakeMusic:
    extends Node
    var user_library=preload("res://scripts/UserLibraryStore.gd").new()
class FakeApp:
    extends Node
    var offline_music=FakeMusic.new()
var failures=0
var checks=0
func check(v,label):
    checks+=1
    if not v: failures+=1
    print("LEGACY_V1_"+("PASS_" if v else "FAIL_")+label)
func _init(): call_deferred("run")
func write_json(path,record):
    var f=File.new()
    if f.open(path,File.WRITE)!=OK: return false
    f.store_string(to_json(record))
    f.close()
    return true
func run():
    var app=FakeApp.new()
    var s=preload("res://scripts/OfflineQueueSave.gd").new()
    s.app=app
    s.checkpoint_path="user://isolated_legacy_v1_checkpoint.json"
    var v1={"version":1,"binding":"a".repeat(64),"entries":[{"name":"Unavailable","media":{},"queue_item_id":"occ-1"},{"name":"Later","media":{"item_id":"2","provider":"library"},"queue_item_id":"occ-2"}],"outcomes":["skipped","failed"],"download_hash":""}
    check(write_json(s.checkpoint_path,v1),"fixture_written")
    s._restore_checkpoint()
    check(s.entries.size()==2 and s.outcomes==["skipped","failed"] and s.skipped==1 and s.failed==1 and s.has_pending(),"v1_skipped_entry_restored")
    s.entries=[];s.outcomes=[];s.checkpoint_binding="";s.state="idle";s.skipped=0;s.failed=0
    v1.outcomes[0]=""
    check(write_json(s.checkpoint_path,v1),"pending_written")
    s._restore_checkpoint()
    check(s.entries.empty() and s.checkpoint_binding=="","v1_missing_pending_media_rejected")
    v1.outcomes[0]="failed"
    check(write_json(s.checkpoint_path,v1),"failed_written")
    s._restore_checkpoint()
    check(s.entries.empty() and s.checkpoint_binding=="","v1_missing_failed_media_rejected")
    v1.outcomes[0]="skipped"
    v1.entries[0].media=null
    check(write_json(s.checkpoint_path,v1),"malformed_written")
    s._restore_checkpoint()
    check(s.entries.empty() and s.checkpoint_binding=="","malformed_media_rejected")
    var v2={"version":2,"id":"b".repeat(64),"binding":"a".repeat(64),"entries":[{"name":"Unavailable","media":{},"queue_item_id":"occ-1"},{"name":"Later","media":{"item_id":"2","provider":"library"},"queue_item_id":"occ-2"}]}
    check(write_json(s.checkpoint_path,v2),"v2_written")
    s._restore_checkpoint()
    check(s.entries.size()==2 and s.outcomes[0]=="skipped","v2_empty_media_restored")
    s.entries=[];s.outcomes=[];s.checkpoint_binding="";s.state="idle";s.skipped=0;s.failed=0
    v1.entries[0].media={"item_id":"1","provider":"library"}
    v1.outcomes[0]=""
    check(write_json(s.checkpoint_path,v1),"valid_v1_written")
    s._restore_checkpoint()
    check(s.entries.size()==2 and s.outcomes==["","failed"] and s.has_pending(),"valid_v1_pending_restored")
    print("LEGACY_V1_SECURITY_CHECKS=",checks," FAILURES=",failures)
    s.free()
    app.offline_music.free()
    app.free()
    s=null
    app=null
    quit(int(failures>0))
