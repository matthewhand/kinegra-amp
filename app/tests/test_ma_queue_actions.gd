extends SceneTree
var failures=[]
func check(ok,label):
    print("MA_QUEUE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class Catalog:
    extends "res://scripts/MACatalog.gd"
    var sent=[]
    func _start(command,args,context):
        if command=="player_queues/play_media": sent.append({"command":command,"args":args.duplicate(true),"context":context.duplicate(true)})
        return true
func _init(): call_deferred("run")
func run():
    var panel=load("res://scripts/MASetupPanel.gd").new();get_root().add_child(panel)
    var catalog=Catalog.new();panel.add_child(catalog);panel.catalog=catalog
    catalog.token="synthetic-token"
    catalog.available_players={"own-wrapper":true}
    catalog.player_routes_complete=true
    catalog.players_at=OS.get_ticks_msec()
    catalog.player_routes=[{"player_id":"own-wrapper","provider":"universal_player","type":"player","available":true,"enabled":true,"active_group":null,"synced_to":null,"group_members":[],"static_group_members":[],"active_output_protocol":"own-client","output_protocols":[{"output_protocol_id":"own-client","protocol_domain":"sendspin","available":true,"derived_from":null}]}]
    var tracks=[{"provider":"library","item_id":"1","media_type":"track","name":"Synthetic A","available":true},{"provider":"library","item_id":"2","media_type":"track","name":"Synthetic B","available":true},{"provider":"library","item_id":"3","media_type":"track","name":"Unavailable","available":false}]
    catalog.current_page={"items":tracks}
    catalog.connect("selection_changed",panel,"_on_selection")
    panel.sendspin_paired=true;panel.sendspin_player_id="own-client"
    panel._on_page({"items":tracks,"kind":"tracks","offset":0})
    panel._select_index(0)
    check(catalog.sent.empty(),"highlight_never_mutates_queue")
    panel._queue_selected()
    check(catalog.sent.size()==1 and catalog.sent[0].args.option=="add" and catalog.sent[0].args.queue_id=="own-wrapper" and catalog.sent[0].args.media==["library://track/1"],"explicit_add_appends_only_to_own_route")
    panel._queue_all_shown()
    check(catalog.sent.size()==2 and catalog.sent[1].args.media==["library://track/1","library://track/2"] and catalog.sent[1].args.option=="add","all_shown_appends_available_tracks_in_order")
    check(panel.queue_all_button.text=="QUEUE PAGE (2)","page_scope_and_count_explicit")
    var invalid=tracks[0].duplicate();invalid.item_id="1/other"
    check(not catalog.enqueue_local_media("own-client",[invalid]) and catalog.sent.size()==2,"unsafe_uri_rejected")
    check(not catalog.enqueue_local_media("cast-named-Shield",[tracks[0]]) and catalog.sent.size()==2,"other_player_rejected")
    catalog.players_at=OS.get_ticks_msec()-11000
    panel._select_index(1);panel._queue_selected()
    check(not panel.pending_queue_media.empty() and catalog.sent.size()==2,"stale_route_refreshes_before_enqueue")
    panel.sendspin_player_id="changed-client";panel._on_players([])
    check(panel.pending_queue_media.empty() and catalog.sent.size()==2,"owner_change_cancels_pending_add")
    panel.sendspin_paired=false;panel._enqueue_snapshot([tracks[0]])
    check(catalog.sent.size()==2 and panel.sendspin_box.visible,"unpaired_only_opens_setup")
    panel.queue_free();print("MA_QUEUE_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
