extends SceneTree
class Catalog:
    extends "res://scripts/MACatalog.gd"
    var sent=[]
    func _start(command,args,context):
        sent.append({"command":command,"args":args.duplicate(true),"context":context.duplicate(true)})
        if command=="players/all":return true
        request_context=context.duplicate(true)
        if context.get("kind") in ["tracks","playlists","playlist_items"]:
            current_page.clear();selected.clear()
            if context.get("kind")=="playlist_items":playlist_snapshot.clear();playlist_snapshot_valid=false
        request_node=HTTPRequest.new();add_child(request_node)
        _state("loading","Synthetic read")
        return true
var failures=[]
func check(ok,label):
    print("LIBRARY_PAGING_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func rows(count):
    var result=[]
    for i in range(count):result.append({"item_id":str(i+1),"provider":"library","name":"Synthetic track %04d" % i,"media_type":"track","is_playable":true})
    return result
func reply(catalog,value):
    catalog._complete(HTTPRequest.RESULT_SUCCESS,200,[],to_json(value).to_utf8(),catalog.epoch)
func _init():call_deferred("run")
func run():
    var panel=load("res://scripts/MASetupPanel.gd").new();get_root().add_child(panel)
    var catalog=Catalog.new();panel.add_child(catalog);panel.catalog=catalog
    catalog.configure("https://ma.example","synthetic-owner-token")
    catalog.connect("state_changed",panel,"_on_state");catalog.connect("page_ready",panel,"_on_page");catalog.connect("selection_changed",panel,"_on_selection")
    catalog.current_page={"items":[{"item_id":"71","provider":"library","name":"Synthetic playlist","media_type":"playlist"}]}
    catalog.select_index(0)
    check(catalog.playlist_items(),"explicit_playlist_open_starts_read")
    check(catalog.sent.back().command=="music/playlists/playlist_tracks" and not catalog.sent.back().args.has("limit") and not catalog.sent.back().args.has("offset") and catalog.sent.back().args.force_refresh==false,"request_matches_supported_unpaged_api_without_mutations")
    reply(catalog,rows(500))
    check(catalog.current_page.items.size()==25 and catalog.current_page.returned_count==500 and catalog.current_page.matched_count==500 and catalog.current_page.total_count==-1,"large_playlist_is_paged_locally_with_honest_unknown_provider_total")
    check(panel.results_label.text.find("Page 1/20")>=0 and panel.results_label.text.find("500 returned")>=0 and panel.results_label.hint_tooltip.find("PROVIDER TOTAL UNKNOWN")>=0,"page_count_and_returned_count_are_distinct")
    var requests=catalog.sent.size();panel._next()
    check(catalog.current_page.offset==25 and catalog.current_page.items[0].item_id=="26" and catalog.sent.size()==requests+1,"next_uses_cached_playlist_not_wrong_library_endpoint")
    check(panel._shown_queue_tracks().size()==25 and panel._shown_queue_tracks()[0].item_id=="26","queue_all_shown_remains_current_page_only")
    panel._previous();check(catalog.current_page.offset==0,"playlist_previous_page_supported")
    panel.search_edit.text="0050";panel._search()
    check(catalog.current_page.items.size()==1 and catalog.current_page.items[0].item_id=="51" and catalog.current_page.returned_count==500 and catalog.current_page.matched_count==1,"playlist_search_filters_snapshot_without_changing_membership")
    catalog.playlist_page(0,"");catalog.refresh_playlist();reply(catalog,rows(1))
    check(catalog.current_page.items.size()==1 and catalog.current_page.returned_count==1 and not catalog.current_page.may_have_more and panel.results_label.text.find("1 returned")>=0,"one_item_server_response_never_implies_full_provider_collection")
    catalog.refresh_playlist();reply(catalog,[])
    check(catalog.current_page.returned_count==0 and panel.list.get_item_count()==0 and panel.next_button.disabled and panel.previous_button.disabled,"empty_refresh_removes_old_tracks_and_navigation")
    catalog.refresh_playlist();reply(catalog,rows(2002))
    catalog.playlist_page(1975)
    check(catalog.current_page.items.size()==25 and catalog.current_page.preview_count==2000 and catalog.current_page.returned_count==2002 and catalog.current_page.truncated and not catalog.current_page.may_have_more and panel.results_label.text.find("Preview capped at 2000")>=0 and panel.results_label.hint_tooltip.find("PREVIEW LIMIT 2000")>=0,"preview_limit_is_explicit_without_silent_collection_truncation")
    catalog.refresh_playlist()
    check(catalog.current_page.empty() and panel.list.get_item_count()==0 and panel.queue_all_button.disabled,"new_read_clears_stale_rows_before_completion")
    reply(catalog,[{"broken":true}])
    check(not catalog.playlist_page(0) and catalog.current_page.empty() and panel.list.get_item_count()==0,"failed_refresh_cannot_resurrect_old_snapshot")
    catalog.refresh_playlist();catalog._complete(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED,200,[],PoolByteArray(),catalog.epoch)
    check(catalog.state=="malformed_reply" and panel.status_label.text.find("2 MiB")>=0,"oversized_reply_reports_real_response_bound")
    catalog.browse("tracks","needle",0);reply(catalog,rows(25));panel.search_edit.text="unsubmitted edit";requests=catalog.sent.size();panel._next()
    check(catalog.sent.back().args.search=="needle" and catalog.sent.back().args.offset==25 and panel.offset==0,"library_paging_preserves_applied_query_and_waits_for_success")
    reply(catalog,[])
    check(catalog.current_page.total_count==-1 and panel.results_label.text.find("Collection changed?")>=0 and panel.results_label.hint_tooltip.find("TOTAL UNKNOWN")>=0 and not panel.previous_button.disabled,"empty_later_page_does_not_invent_total_count")
    catalog.browse("tracks","",10000);reply(catalog,rows(25))
    check(panel.next_button.disabled and panel.results_label.text.find("Browse limit reached")>=0,"library_offset_limit_is_visible")
    catalog.browse("tracks","",0);reply(catalog,rows(1))
    check(catalog.current_page.total_count==1 and panel.results_label.text.find("1 total")>=0,"short_library_page_reports_known_total")
    catalog.current_page={"items":[{"item_id":"71","provider":"library","name":"Synthetic playlist","media_type":"playlist"}],"kind":"playlists","offset":50,"search":"saved filter"}
    panel._on_page(catalog.current_page);catalog.select_index(0);panel._playlist_items();reply(catalog,rows(1));panel._back_to_playlists()
    check(catalog.sent.back().command=="music/playlists/library_items" and catalog.sent.back().args.offset==50 and catalog.sent.back().args.search=="saved filter","back_to_playlists_restores_library_page_and_query")
    if catalog.request_node!=null:catalog._dispose_request()
    var actual=load("res://scripts/MACatalog.gd").new();get_root().add_child(actual)
    actual.request_node=HTTPRequest.new();actual.add_child(actual.request_node);actual.request_context={"kind":"players"};actual.player_routes_complete=true
    var old_epoch=actual.epoch
    actual._preempt_player_metadata()
    check(actual.request_node==null and actual.epoch==old_epoch+1 and not actual.player_routes_complete,"new_browse_can_preempt_player_read_and_expires_route_proof")
    actual.request_node=HTTPRequest.new();actual.add_child(actual.request_node);actual.request_context={"kind":"enqueue"};old_epoch=actual.epoch
    actual._preempt_player_metadata()
    check(actual.request_node!=null and actual.epoch==old_epoch,"browsing_never_preempts_queue_mutation")
    actual.cancel();actual.queue_free()
    catalog.cancel();check(catalog.playlist_snapshot.empty() and catalog.playlist_context.empty(),"cancel_expires_playlist_snapshot_and_context")
    var no_writes=true
    for sent in catalog.sent:
        if not sent.command in ["players/all","music/tracks/library_items","music/playlists/library_items","music/playlists/playlist_tracks"]:no_writes=false
    check(no_writes,"browsing_refresh_search_and_paging_never_mutate_library_or_queue")
    panel.queue_free();print("LIBRARY_PAGING_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
