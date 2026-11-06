extends SceneTree
# Real Godot input dispatch; only I/O and app-quit side effects are synthetic.
# Main._input, _handle_tv_back and _notification are never overridden.
class SurvivalWatchdog:
    extends Node
    var completed=false
    func _exit_tree():
        if not completed:printerr("NATIVE_MA_FAIL_premature_native_scene_exit")
class CatalogFixture:
    extends "res://scripts/MACatalog.gd"
    var writes=[]
    var reads=[]
    var route_ready=true
    func discover_players():return true
    func resolve_local_player(client_id):
        return "synthetic-own-queue" if route_ready and client_id=="synthetic-own-client" else ""
    func _start(command,args,context):
        var entry={"command":command,"args":args.duplicate(true),"kind":context.get("kind","")}
        if command=="player_queues/play_media":writes.append(entry)
        else:reads.append(entry)
        # Deliberately complete immediately: a pending HTTP request must not
        # mask duplicate mutations from repeated held controller packets.
        return true
class RuntimeFixture:
    extends Reference
    var active=true
    var buffering=false
class ClientFixture:
    extends Reference
    func status():return {"paired":true,"client_id":"synthetic-own-client"}
class FacadeFixture:
    extends Node
    var runtime=RuntimeFixture.new()
    var client=ClientFixture.new()
    var sink=null
    var stops=0
    func stop():
        stops+=1;runtime.active=false
class TransportFixtureMain:
    extends "res://scripts/Main.gd"
    var queue_requests=[]
    func _request_tv_queue(command,_argument=null):
        queue_requests.append(command)
        if command=="items":
            var title="Synthetic queued track"
            if OS.get_environment("SHIELDAMP_MA_LONG_NAMES")=="1":title="Synthetic queued title with several words for narrow-screen readability / generic"
            music_ui.show_tv_queue_items([{"queue_item_id":"synthetic-queue-1","name":title,"current":false}],true,"Synthetic queue response")
        return true
var failures=[]
var checks=0
var quit_requests=0
var watchdog=null
var app=null
var ui=null
var panel=null
var catalog=null
var facade=null
func quit(_code=0):quit_requests+=1
func check(ok,label):
    checks+=1;print("NATIVE_MA_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func joy(index,pressed=true):
    var event=InputEventJoypadButton.new();event.device=5;event.button_index=index;event.pressed=pressed
    return event
func key(code,pressed=true):
    var event=InputEventKey.new();event.scancode=code;event.pressed=pressed
    return event
func press(event):
    Input.parse_input_event(event);yield(self,"idle_frame")
    var release=event.duplicate();release.pressed=false;Input.parse_input_event(release)
    yield(create_timer(.025),"timeout")
func setup_page(kind="tracks"):
    var rows=[]
    for index in range(10):rows.append({"item_id":str(101+index if kind=="playlists" else 201+index),"provider":"library","name":("Synthetic selected title with several words for narrow-screen readability / " if OS.get_environment("SHIELDAMP_MA_LONG_NAMES")=="1" else "Synthetic "+("playlist " if kind=="playlists" else "track "))+str(index+1),"media_type":"playlist" if kind=="playlists" else "track","available":true})
    catalog.current_page={"kind":kind,"items":rows,"offset":0,"may_have_more":false,"search":""}
    catalog.token="synthetic-authorized-token";catalog.endpoint="https://synthetic.invalid"
    panel.library_disconnected=false;panel.sendspin_paired=true;panel.sendspin_player_id="synthetic-own-client"
    panel._on_page(catalog.current_page)
    ui.ma_drawer.show_modal(true)
    panel.list.grab_focus()
    panel._refresh_sendspin_play_here()
func selected_id():return str(panel._selected_item().get("item_id",""))
func shot(name):
    # Viewport pixels trail GUI state; await two complete idle boundaries.
    yield(self,"idle_frame");yield(self,"idle_frame")
    var folder=OS.get_environment("SHIELDAMP_MA_NATIVE_IMAGES")
    if not folder.empty():
        var image=get_root().get_texture().get_data();image.flip_y();image.save_png(folder+"/"+name+".png")
func _init():call_deferred("run")
func run():
    watchdog=SurvivalWatchdog.new();get_root().add_child(watchdog)
    AudioServer.set_bus_mute(0,true)
    app=TransportFixtureMain.new();get_root().add_child(app)
    yield(create_timer(.25),"timeout");app.set_process(false);ui=app.music_ui;ui.set_process(false);panel=app.ma_panel
    var old=panel.catalog;old.close();old.queue_free()
    catalog=CatalogFixture.new();panel.add_child(catalog);panel.catalog=catalog
    catalog.connect("state_changed",panel,"_on_state");catalog.connect("page_ready",panel,"_on_page");catalog.connect("selection_changed",panel,"_on_selection");catalog.connect("players_ready",panel,"_on_players")
    panel.endpoint_edit.text="https://synthetic.invalid";catalog.endpoint="https://synthetic.invalid";catalog.token="synthetic-authorized-token";panel.library_disconnected=false
    app._on_library_credentials_authorized(catalog.token,"https://synthetic.invalid")
    facade=FacadeFixture.new();app.add_child(facade);app.sendspin_facade=facade
    if panel.get("view_queue_button")==null or not panel.has_method("_selected_item"):
        check(false,"required_library_action_contract_missing");watchdog.completed=true;.quit(1);return
    setup_page("playlists");yield(create_timer(.08),"timeout")
    check(panel.list.get_selected_items().size()==1 and selected_id()=="101","fresh_page_selects_actual_first_row_and_model")
    var reads=catalog.reads.size();yield(press(joy(0)),"completed")
    check(catalog.reads.size()==reads+1 and catalog.reads.back().command=="music/playlists/playlist_tracks","slot5_accept_opens_initial_playlist_without_extra_down")
    setup_page("tracks");yield(create_timer(.05),"timeout")
    yield(press(key(KEY_DOWN)),"completed");yield(press(key(KEY_DOWN)),"completed")
    var chosen=selected_id();var selected=panel.list.get_selected_items()[0]
    check(chosen=="203","native_down_updates_fresh_visible_selection")
    yield(press(joy(15)),"completed")
    check(panel.play_button.has_focus() and selected_id()==chosen and panel.list.get_selected_items()[0]==selected,"right_reaches_primary_play_without_changing_row")
    yield(press(joy(12)),"completed")
    check(panel.selection_label.has_focus() and selected_id()==chosen,"up_from_play_still_reaches_full_title")
    yield(press(joy(0)),"completed")
    check(ui.item_title_dialog.is_visible_in_tree() and ui.item_title_dialog.dialog_text==panel._selected_item().name,"native_up_and_accept_open_selected_full_title")
    yield(press(joy(1)),"completed")
    check(panel.selection_label.has_focus(),"full_title_back_restores_title_focus")
    yield(press(joy(13)),"completed")
    check(panel.play_button.has_focus(),"down_from_title_returns_to_primary_play")
    yield(press(joy(14)),"completed")
    check(panel.list.has_focus() and selected_id()==chosen,"left_returns_to_identical_row")
    catalog.selected=catalog.current_page.items[0].duplicate(true);catalog.selected_at=OS.get_ticks_msec()
    yield(press(joy(15)),"completed")
    check(panel.play_button.has_focus() and selected_id()==chosen,"right_reaches_play_after_return_without_catalog_drift")
    var before=catalog.writes.size();yield(press(joy(0)),"completed")
    app.tv_queue_timer.stop();app.tv_audio_wait_timer.stop()
    check(catalog.writes.size()==before+1 and catalog.writes.back().args.media=="library://track/203" and catalog.writes.back().args.option=="play" and catalog.writes.back().args.queue_id=="synthetic-own-queue","play_uses_visible_snapshot_and_exact_own_route")
    check(not "play" in app.queue_requests,"selected_play_does_not_send_extra_queue_resume_rpc")
    setup_page("tracks");panel.list.grab_focus();before=catalog.writes.size()
    Input.parse_input_event(joy(0));yield(self,"idle_frame");Input.parse_input_event(joy(0));yield(self,"idle_frame");Input.parse_input_event(joy(0,false));yield(create_timer(.04),"timeout")
    check(catalog.writes.size()==before+1 and catalog.writes.back().args.option=="play" and catalog.writes.back().args.media=="library://track/201","held_itemlist_accept_plays_selected_once_even_after_instant_reply")
    setup_page("tracks");yield(create_timer(.04),"timeout")
    var context=ui.playback_context;var row=selected_id();before=catalog.writes.size()
    yield(press(joy(15)),"completed")
    check(panel.play_button.has_focus() and selected_id()==row,"complete_remote_path_list_right_to_play")
    yield(press(joy(15)),"completed")
    check(panel.add_queue_button.has_focus() and selected_id()==row,"same_row_right_play_to_add_skips_title_label")
    yield(press(joy(13)),"completed")
    check(panel.view_queue_button.has_focus() and selected_id()==row,"down_from_add_reaches_view_queue")
    yield(press(joy(12)),"completed")
    check(panel.add_queue_button.has_focus(),"up_returns_to_add_without_changing_selection")
    yield(press(joy(0)),"completed")
    check(catalog.writes.size()==before+1 and catalog.writes.back().args.option=="add" and catalog.writes.back().args.media==["library://track/201"] and selected_id()==row,"remote_action_grid_add_sends_one_selected_write")
    catalog.emit_signal("state_changed","queue_added","Synthetic server accepted selected addition")
    yield(self,"idle_frame")
    check(panel.view_queue_button.has_focus(),"accepted_add_focuses_view_queue_without_pointer")
    yield(press(joy(0)),"completed")
    check(ui.queue_drawer.visible and not ui.ma_drawer.visible and ui.queue_view=="tv" and ui.playback_context==context,"view_queue_uses_tv_read_without_reassigning_audio_source")
    check(app.queue_requests.back()=="items" and selected_id()==row,"view_queue_preserves_selected_snapshot")
    yield(press(joy(1)),"completed")
    check(ui.ma_drawer.visible and not ui.queue_drawer.visible and panel.view_queue_button.has_focus() and selected_id()==row,"queue_back_returns_to_same_library_selection")
    setup_page("playlists");yield(create_timer(.04),"timeout")
    var stable=selected_id()
    yield(press(joy(15)),"completed");yield(press(joy(13)),"completed")
    check(panel.playlist_button.has_focus(),"down_from_playlist_play_reaches_open")
    yield(press(joy(15)),"completed")
    check(panel.view_queue_button.has_focus() and selected_id()==stable,"same_row_right_open_to_view_queue")
    yield(press(joy(15)),"completed")
    check(panel.view_queue_button.has_focus(),"right_edge_view_queue_stays_in_row")
    setup_page("tracks");yield(create_timer(.04),"timeout")
    yield(press(joy(15)),"completed");yield(press(joy(13)),"completed")
    check(panel.queue_all_button.has_focus(),"down_skips_disabled_open_to_queue_page")
    yield(press(joy(15)),"completed")
    var back_to_list=panel.action_grid.get_child(5)
    check(back_to_list.has_focus(),"same_row_right_queue_page_to_back_to_list")
    yield(press(joy(15)),"completed")
    check(back_to_list.has_focus(),"right_edge_back_to_list_stays_in_row")
    panel.play_button.grab_focus();var disabled=panel.add_queue_button.disabled;panel.add_queue_button.disabled=true
    yield(press(joy(15)),"completed")
    check(panel.play_button.has_focus(),"disabled_adjacent_action_does_not_jump_rows")
    panel.add_queue_button.disabled=disabled
    for denied in ["provider","unavailable"]:
        setup_page("tracks")
        if denied=="provider":catalog.current_page.items[0].provider="external-demo"
        else:catalog.current_page.items[0].available=false
        panel._on_page(catalog.current_page);panel.list.grab_focus();before=catalog.writes.size()
        yield(press(joy(0)),"completed")
        check(panel.play_button.disabled and catalog.writes.size()==before,"unsupported_"+denied+"_cannot_mutate_queue")
    setup_page("tracks")
    # Simulate a completed page replacement before its UI delivery: a stale
    # selected item may never control a different newly returned page.
    catalog.current_page={"kind":"tracks","items":[{"item_id":"999","provider":"library","name":"New synthetic row","media_type":"track","available":true}]}
    panel.play_button.grab_focus();before=catalog.writes.size();yield(press(joy(0)),"completed")
    check(catalog.writes.size()==before,"replaced_page_rejects_stale_play_snapshot")
    setup_page("tracks");yield(create_timer(.05),"timeout")
    # Real nested popup, then real controller and native SceneTree Back paths.
    ui._show_library_configuration("library");yield(create_timer(.04),"timeout")
    panel.forget_access_dialog.popup_centered();yield(create_timer(.04),"timeout")
    yield(press(joy(1)),"completed")
    check(not panel.forget_access_dialog.visible and ui.library_config_popup.visible and ui.ma_drawer.visible,"back_dismisses_innermost_popup_only")
    yield(press(joy(1)),"completed")
    check(not ui.library_config_popup.visible and ui.ma_drawer.visible,"next_back_closes_configuration_only")
    Input.parse_input_event(joy(1));yield(self,"idle_frame");Input.parse_input_event(joy(1));yield(self,"idle_frame");Input.parse_input_event(joy(1,false));yield(create_timer(.04),"timeout")
    check(not ui.ma_drawer.visible and quit_requests==0,"held_outer_back_closes_once_without_app_exit")
    setup_page("tracks");yield(create_timer(.04),"timeout")
    Input.parse_input_event(joy(1));yield(create_timer(.35),"timeout")
    notification(MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST);yield(self,"idle_frame")
    check(quit_requests==0,"native_back_during_long_handled_hold_does_not_quit")
    Input.parse_input_event(joy(1,false));yield(self,"idle_frame")
    notification(MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST);yield(self,"idle_frame")
    check(quit_requests==0,"native_back_after_long_hold_release_does_not_quit")
    setup_page("tracks");yield(create_timer(.25),"timeout")
    notification(MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST);yield(create_timer(.04),"timeout")
    check(not ui.ma_drawer.visible and quit_requests==0,"native_scene_tree_back_closes_modal_and_survives")
    setup_page("tracks");yield(create_timer(.25),"timeout")
    notification(MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST);yield(self,"idle_frame")
    Input.parse_input_event(joy(1));yield(create_timer(.35),"timeout")
    notification(MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST);yield(self,"idle_frame")
    check(quit_requests==0,"native_first_input_long_hold_does_not_quit")
    Input.parse_input_event(joy(1,false));yield(self,"idle_frame")
    notification(MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST);yield(self,"idle_frame")
    check(quit_requests==0,"native_first_input_release_paired_back_does_not_quit")
    for size in [Vector2(480,800),Vector2(720,1280),Vector2(960,720),Vector2(1280,720),Vector2(1720,720)]:
        OS.window_size=size;app._apply_resolution_base();yield(create_timer(.12),"timeout")
        for large in [false,true]:
            app._set_large_text(large);setup_page("playlists");yield(create_timer(.06),"timeout")
            var visible=true
            for control in [panel.play_button,panel.add_queue_button,panel.playlist_button,panel.view_queue_button,panel.queue_all_button]:
                visible=visible and control.is_visible_in_tree() and ui.ma_drawer.get_global_rect().encloses(control.get_global_rect()) and ui.root.get_global_rect().encloses(control.get_global_rect())
            check(visible,str(size)+("_large" if large else "_normal")+"_all_library_actions_visible_in_modal")
            var id=selected_id();yield(press(key(KEY_RIGHT)),"completed")
            check(panel.play_button.has_focus() and selected_id()==id,str(size)+("_large" if large else "_normal")+"_remote_right_reaches_play_keeps_playlist_selection")
            yield(press(key(KEY_LEFT)),"completed")
            check(panel.list.has_focus() and selected_id()==id,str(size)+("_large" if large else "_normal")+"_remote_left_returns_to_list")
            var capture=(size==Vector2(1280,720) and not large) or (size==Vector2(480,800) and large)
            if capture:
                yield(shot("library_"+str(int(size.x))+("_large" if large else "_normal")),"completed")
                panel.selection_label.grab_focus();yield(self,"idle_frame");yield(shot("library_title_focused_"+str(int(size.x))),"completed");yield(press(key(KEY_ENTER)),"completed");yield(self,"idle_frame");yield(self,"idle_frame");yield(create_timer(.04),"timeout")
                check(ui.item_title_dialog.is_visible_in_tree() and ui.item_title_dialog.get_label().get_visible_line_count()>=ui.item_title_dialog.get_label().get_line_count() and ui.item_title_dialog.dialog_text==panel._selected_item().name and ui.root.get_global_rect().encloses(ui.item_title_dialog.get_global_rect()),str(size)+"_library_full_title_dialog_contains_exact_name_and_fits")
                yield(shot("library_title_dialog_"+str(int(size.x))),"completed")
                yield(press(joy(1)),"completed")
                check(not ui.item_title_dialog.visible and panel.selection_label.has_focus() and ui.ma_drawer.visible,str(size)+"_library_full_title_back_restores_opener")
            var context_before=ui.playback_context
            panel.view_queue_button.grab_focus();yield(press(joy(0)),"completed")
            check(ui.queue_drawer.visible and ui.playback_context==context_before,str(size)+("_large" if large else "_normal")+"_controller_view_queue_keeps_source")
            if capture:
                yield(shot("queue_"+str(int(size.x))+("_large" if large else "_normal")),"completed")
                check(ui.queue_help_label.get_visible_line_count()>=ui.queue_help_label.get_line_count(),str(size)+"_queue_help_sentence_is_fully_visible")
                check(ui.queue_selected_label.get_line_count()>=2 and ui.queue_selected_label.get_visible_line_count()>=ui.queue_selected_label.get_line_count(),str(size)+"_queue_selected_name_lines_are_actually_visible")
                ui.queue_selected_label.grab_focus();yield(self,"idle_frame");yield(shot("queue_title_focused_"+str(int(size.x))),"completed");yield(press(joy(0)),"completed");yield(self,"idle_frame");yield(self,"idle_frame");yield(create_timer(.04),"timeout")
                check(ui.item_title_dialog.is_visible_in_tree() and ui.item_title_dialog.get_label().get_visible_line_count()>=ui.item_title_dialog.get_label().get_line_count() and ui.item_title_dialog.dialog_text==str(ui.tv_queue_items[ui.queue_selected]) and ui.root.get_global_rect().encloses(ui.item_title_dialog.get_global_rect()),str(size)+"_queue_full_title_dialog_contains_exact_name_and_fits")
                yield(shot("queue_title_dialog_"+str(int(size.x))),"completed")
                yield(press(joy(1)),"completed")
                check(not ui.item_title_dialog.visible and ui.queue_selected_label.has_focus() and ui.queue_drawer.visible,str(size)+"_queue_full_title_back_restores_opener")
            yield(press(joy(1)),"completed")
            check(ui.ma_drawer.visible and selected_id()==id and quit_requests==0,str(size)+("_large" if large else "_normal")+"_controller_back_keeps_selection_and_app")
    check(facade.runtime.active and facade.stops==0,"library_navigation_never_stops_owned_audio_session")
    watchdog.completed=true;app.sendspin_facade=null;app.queue_free()
    print("NATIVE_MA_CHECKS=",checks," FAILURES=",failures.size()," QUIT_REQUESTS=",quit_requests)
    print("NATIVE_MA_FLOW_COMPLETE")
    .quit(0 if failures.empty() else 1)
