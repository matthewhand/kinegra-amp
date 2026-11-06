extends SceneTree
var failures=[]
var checks=0
const Store=preload("res://scripts/MusicUiMemory.gd")
class FailedCommit:
    extends "res://scripts/MusicUiMemory.gd"
    func _rename(from,to):
        if from.ends_with(".tmp"):return ERR_CANT_CREATE
        return Directory.new().rename(from,to)
func check(ok,label):
    checks+=1;print("UI_MEMORY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func write(path,text):
    var f=File.new();f.open(path,File.WRITE);f.store_string(text);f.close()
func read(path):
    var f=File.new()
    if f.open(path,File.READ)!=OK:return ""
    var text=f.get_as_text();f.close();return text
func _init():call_deferred("run")
func run():
    var store=Store.new();store.path="user://navigation-test-"+str(OS.get_ticks_usec())+".json"
    check(not store.load_state() and store.source()=="ma","missing_memory_defaults_to_music_assistant")
    check(store.set_source("offline"),"explicit_source_saves")
    var reload=Store.new();reload.path=store.path
    check(reload.load_state() and reload.source()=="offline","source_survives_relaunch")
    check(store.set_source("catalog") and store.source()=="ma","transient_catalog_normalizes_to_ma")
    check(not store.set_source("arbitrary") and store.source()=="ma","unsupported_source_rejected")
    var origin="https://synthetic.invalid"
    var page={"kind":"playlist_items","offset":50,"search":"","playlist":{"item_id":"71","provider":"library","name":"Private title never retained"}}
    check(store.remember_location(origin,page,{"provider":"library","item_id":"203","name":"Private track never retained"},25) and store.save(),"playlist_identity_and_position_saved")
    check(store.remember_offline(1027) and not store.remember_offline(1028) and store.save(),"offline_slot_is_bounded_and_stable")
    reload.load_state();var location=reload.location(origin)
    check(location.kind=="playlist_items" and location.offset==50 and location.selected_id=="203" and location.playlist_id=="71" and location.return_offset==25,"playlist_bookmark_survives_relaunch")
    check(reload.offline_index()==1027,"offline_slot_survives_relaunch")
    check(reload.location("https://different.invalid").empty(),"bookmark_cannot_cross_server_origin")
    check(store.identity("https://user:password@synthetic.invalid").empty() and store.identity(origin+"/private").empty(),"credentials_and_non_origin_urls_rejected")
    var text=read(store.path)
    check(not "synthetic.invalid" in text and not "Private" in text and not "token" in text and not "queue" in text,"file_contains_no_url_title_token_or_queue_copy")
    page.search="sensitive free text";page.offset=75
    check(store.remember_location(origin,page,{"provider":"library","item_id":"204"},25) and store.save(),"filtered_browse_has_safe_unfiltered_fallback")
    location=store.location(origin)
    check(location.offset==0 and location.selected_id.empty() and not "sensitive" in read(store.path),"query_text_is_not_persisted")
    page.search="";page.offset=10025
    check(not store.remember_location(origin,page,{},0),"out_of_bound_page_rejected")
    page.offset=1
    check(not store.remember_location(origin,page,{},0),"non_page_offset_rejected")
    page.offset=0;page.playlist.provider="external"
    check(not store.remember_location(origin,page,{},0),"external_playlist_cannot_be_restored_as_library")
    store.set_source("offline");store.set_source("ma")
    write(store.path,"broken")
    check(reload.load_state() and reload.source()=="offline","last_atomic_backup_recovers_corrupt_primary")
    write(store.path,JSON.print({"version":2,"source":"offline"}))
    check(not reload.load_state() and reload.blocked and not reload.set_source("offline") and JSON.parse(read(store.path)).result.version==2,"future_version_is_not_overwritten")
    var rollback=FailedCommit.new();rollback.path="user://navigation-rollback-"+str(OS.get_ticks_usec())+".json"
    write(rollback.path,JSON.print({"version":1,"source":"ma","origin":"","location":{}}));rollback.load_state()
    check(not rollback.set_source("offline") and JSON.parse(read(rollback.path)).result.source=="ma","failed_commit_restores_previous_primary")
    write(store.path,JSON.print({"version":1,"source":"ma","origin":"","location":{},"token":"must-not-survive"}));reload.load_state();reload.set_source("offline")
    check(not "must-not-survive" in read(store.path) and not "token" in read(store.path),"unknown_sensitive_fields_never_round_trip")
    reload.path=store.path+"-oversize"
    write(reload.path,"x".repeat(4097))
    check(not reload.load_state() and reload.source()=="ma","oversize_file_falls_back_without_unbounded_read")
    print("UI_MEMORY_CHECKS=",checks," FAILURES=",failures.size());quit(0 if failures.empty() else 1)
