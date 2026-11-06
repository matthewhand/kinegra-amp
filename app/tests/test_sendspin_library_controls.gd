extends SceneTree
var errors=[]
var starts=0
var requested_routes=[]
var tested_panel=null
func on_queue_play(_item): requested_routes.append(tested_panel.catalog.resolve_local_player(tested_panel.sendspin_player_id))
func on_start(_address,_trusted): starts+=1
func check(ok,label):
    print("TV_PLAYER_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: errors.append(label)
class FakeCatalog:
    extends Reference
    var available_players={}
    var current_page={"items":[]}
    var token="fixture"
    var request_node=null
    var discoveries=0
    var local_routes={}
    func discover_players():
        discoveries+=1
        return true
    var item={"item_id":"7","provider":"library","media_type":"track","name":"Synthetic"}
    var played=[]
    func selection(): return item.duplicate(true)
    func resolve_local_player(id):
        if local_routes.has(id): return local_routes[id]
        return id if available_players.has(id) and not id.empty() else ""
    func select_index(_index): return true
    func play_on_player(id):
        played.append(id)
        return true
func _init(): call_deferred("run")
func run():
    var panel=load("res://scripts/MASetupPanel.gd").new()
    tested_panel=panel
    panel.connect("sendspin_play_here_requested",self,"on_queue_play")
    get_root().add_child(panel)
    check(not panel.sendspin_box.visible and not panel.sendspin_trust.pressed,"off_by_default")
    check(panel.play_button.text=="PLAY" and panel.sendspin_toggle.text=="PLAYBACK SETUP ▸","plain_play_and_setup_labels")
    panel.settings_path="user://sendspin_ui_test.cfg"
    var disk=Directory.new()
    if File.new().file_exists(panel.settings_path): disk.remove(panel.settings_path)
    panel.connect("sendspin_start_requested",self,"on_start")
    panel.endpoint_edit.text="http://10.1.2.3:8095"
    panel._toggle_sendspin()
    check(panel.sendspin_endpoint.text=="ws://10.1.2.3:8927/sendspin","derive_host_without_private_address_constant")
    panel._sendspin_start()
    check(starts==0 and not File.new().file_exists(panel.settings_path),"untrusted_start_does_not_save_or_connect")
    panel.sendspin_trust.pressed=true
    panel._sendspin_start()
    check(starts==1,"explicit_trusted_start")
    var config=ConfigFile.new()
    check(config.load(panel.settings_path)==OK and config.get_value("sendspin","endpoint","")=="ws://10.1.2.3:8927/sendspin","sendspin_settings_persist")
    check(panel._save_connection_setting("connection","endpoint","http://10.1.2.3:8095","trust_private_http",true),"save_ma_preserves_sections")
    config=ConfigFile.new()
    check(config.load(panel.settings_path)==OK and config.get_value("sendspin","trust_private_lan",false),"ma_save_preserves_sendspin")
    var broken=File.new()
    broken.open(panel.settings_path,File.WRITE)
    broken.store_string("[unterminated")
    broken.close()
    check(not panel._save_connection_setting("sendspin","endpoint","safe","trust_private_lan",true),"malformed_config_never_overwritten")
    broken.open(panel.settings_path,File.READ)
    check(broken.get_as_text()=="[unterminated","malformed_bytes_preserved")
    broken.close()
    broken.open(panel.settings_path,File.WRITE)
    broken.store_string("not a valid config file")
    broken.close()
    check(not panel._save_connection_setting("sendspin","endpoint","safe","trust_private_lan",true),"unparsed_config_never_overwritten")
    broken.open(panel.settings_path,File.READ)
    check(broken.get_as_text()=="not a valid config file","unparsed_bytes_preserved")
    broken.close()
    disk.remove(panel.settings_path)
    var catalog=FakeCatalog.new()
    panel.catalog=catalog
    panel._on_selection(catalog.item)
    panel.set_sendspin_status("paired","ready","this-player")
    check(not panel.sendspin_refresh_target.empty(),"new_pair_schedules_discovery")
    check(panel.pairing_code_dialog.get_ok().rect_min_size.x>=160 and panel.pairing_code_dialog.get_ok().text=="DISMISS","pairing_dismiss_is_sized_and_labelled")
    panel.sendspin_refresh_timer.stop()
    catalog.request_node=Reference.new()
    panel._try_sendspin_refresh()
    check(catalog.discoveries==0,"busy_catalog_waits_without_cancelling")
    panel.sendspin_refresh_timer.stop()
    catalog.request_node=null
    panel._try_sendspin_refresh()
    panel._try_sendspin_refresh()
    panel._try_sendspin_refresh()
    panel._try_sendspin_refresh()
    check(catalog.discoveries==3 and panel.sendspin_refresh_target.empty(),"discovery_attempts_bounded")
    check(requested_routes.empty(),"pairing_never_autoplays")
    catalog.available_players={"cast-shield":true}
    panel._on_players([{"player_id":"cast-shield","name":"Shield"}])
    panel._play_on_player()
    check(requested_routes.empty(),"primary_play_never_uses_cast_named_shield")
    check(panel.play_button.text=="PLAY" and not panel.sendspin_advanced.visible,"single_play_action_with_advanced_settings_hidden")
    panel._refresh_sendspin_play_here()
    check(not panel._local_play_ready(),"never_target_other_player")
    panel._sendspin_play_here()
    check(requested_routes.empty(),"disabled_does_not_send")
    panel.set_sendspin_status("connecting","waiting")
    panel.set_sendspin_status("paired","ready","this-player")
    panel.sendspin_refresh_timer.stop()
    catalog.available_players["this-player"]=true
    panel._on_players([{"player_id":"this-player","name":"This TV"}])
    check(panel.sendspin_refresh_target.empty(),"matching_discovery_stops_retry")
    check(panel._local_play_ready(),"local_player_selectable")
    panel._sendspin_play_here()
    check(requested_routes==["this-player"],"explicit_play_only_targets_local")
    panel._play_on_player()
    check(requested_routes==["this-player","this-player"],"primary_play_uses_same_verified_in_app_route")
    requested_routes.remove(1)
    catalog.available_players.clear()
    panel._refresh_sendspin_play_here()
    check(panel.sendspin_hint.text.begins_with("Playback requested"),"post_play_hint_does_not_claim_bad_route")
    catalog.available_players["this-player"]=true
    catalog.local_routes={"this-player":"universal-wrapper"}
    panel._sendspin_play_here()
    check(requested_routes==["this-player","universal-wrapper"],"matched_wrapper_receives_explicit_play")
    panel.set_sendspin_status("connecting","waiting")
    check(not panel._local_play_ready(),"unpaired_cannot_play")
    var previous_plays=requested_routes.size()
    panel._play_on_player()
    check(requested_routes.size()==previous_plays and panel.sendspin_connect_button.has_focus(),"unpaired_primary_opens_in_app_connection_without_playing")
    panel.show_sendspin_token("SP:synthetic-test-token")
    check("synthetic-test-token" in panel.sendspin_token_label.text,"explicit_token_display")
    panel._clear_sendspin_token()
    check(panel.sendspin_token_label.text.empty(),"closed_token_cleared")
    panel.queue_free()
    print("TV_PLAYER_FAILURES=",errors.size())
    quit(0 if errors.empty() else 1)
