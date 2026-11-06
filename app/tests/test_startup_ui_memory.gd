extends SceneTree
# Actual UI and Main setup, synthetic catalog/read boundary only. No service writes.
class MainFixture:
    extends "res://scripts/Main.gd"
    var resumes=0
    var restores=0
    var cancels=0
    var reads=[]
    var own_client="synthetic-own-client"
    func _play_music_assistant():
        resumes+=1
        return true
    func _restore_music_assistant_session():restores+=1
    func cancel_pending_resume():cancels+=1
    func _request_tv_queue(command,_argument=null):
        reads.append(command)
        return true
    func _sendspin_controls():return {"paired":true,"client_id":own_client}
class CatalogFixture:
    extends "res://scripts/MACatalog.gd"
    func discover_players():return false
    func publish(page):
        current_page=page.duplicate(true)
        emit_signal("page_ready",current_page.duplicate(true))
var checks=0
var failures=[]
func check(ok,label):
    checks+=1;print("STARTUP_MEMORY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func tracks(ids,offset=0):
    var rows=[]
    for id in ids:rows.append({"item_id":id,"provider":"library","media_type":"track","name":"Synthetic track "+id,"available":true})
    return {"kind":"tracks","offset":offset,"search":"","items":rows,"may_have_more":false}
func press_key(code):
    var event=InputEventKey.new();event.scancode=code;event.pressed=true;Input.parse_input_event(event);yield(self,"idle_frame")
    event.pressed=false;Input.parse_input_event(event);yield(create_timer(.025),"timeout")
func _init():call_deferred("run")
func run():
    var app=MainFixture.new();get_root().add_child(app);yield(create_timer(.2),"timeout")
    AudioServer.set_bus_mute(0,true);app.set_process(false);var ui=app.music_ui;ui.set_process(false)
    ui.ui_memory.path="user://startup-memory-"+str(OS.get_ticks_usec())+".json";ui.ui_memory.load_state()
    var restore_count=app.restores
    check(ui.restore_startup_context()=="ma" and ui.playback_context=="ma" and ui.now_title.text=="Choose music" and ui.source_label.text=="MUSIC ASSISTANT","fresh_start_is_simple_ma_home_without_bundled_metadata")
    yield(self,"idle_frame")
    check(app.restores==restore_count+1 and app.resumes==0 and not app.offline_music.is_playing() and not ui.ma_drawer.visible and not ui.library_config_popup.visible,"restore_only_requests_background_session_no_autoplay_or_popup")
    check(ui.play_button.has_focus(),"cold_entry_focuses_play_for_one_press_resume")
    ui._show_library_configuration("library")
    var cancellations=app.cancels
    ui._close_completed_library_configuration()
    check(app.cancels==cancellations and not ui.library_config_popup.visible,"successful_configuration_auto_close_preserves_explicit_play_intent")
    ui._show_library_configuration("library")
    ui.library_config_popup.hide()
    check(app.cancels==cancellations+1,"user_dismissed_configuration_cancels_pending_play_intent")
    ui._sync_transport()
    check(ui.play_button.text=="PLAY" and not ui.play_button.disabled,"visible_play_control_remains_play_and_enabled_without_connection")
    ui.play_button.grab_focus()
    var pressed=InputEventKey.new();pressed.scancode=KEY_ENTER;pressed.pressed=true
    Input.parse_input_event(pressed)
    yield(self,"idle_frame")
    var released=InputEventKey.new();released.scancode=KEY_ENTER;released.pressed=false
    Input.parse_input_event(released)
    yield(self,"idle_frame")
    check(app.resumes==1 and not app.offline_music.is_playing(),"actual_play_button_dispatch_connects_without_offline_fallback")
    ui.set_playback_context("offline")
    var reload=load("res://scripts/MusicUiMemory.gd").new();reload.path=ui.ui_memory.path;reload.load_state()
    check(reload.source()=="offline","explicit_source_switch_persists_immediately")
    ui.ui_memory.load_state()
    check(ui.restore_startup_context()=="offline" and ui.playback_context=="offline" and not app.offline_music.is_playing(),"offline_choice_restores_stopped")
    var panel=app.ma_panel;var old=panel.catalog;old.close();old.queue_free()
    var catalog=CatalogFixture.new();panel.catalog=catalog;panel.add_child(catalog)
    catalog.endpoint="https://synthetic.invalid";catalog.token="synthetic-authorized-library"
    panel.endpoint_edit.text="https://synthetic.invalid"
    catalog.connect("page_ready",panel,"_on_page");catalog.connect("selection_changed",panel,"_on_selection")
    catalog.connect("page_ready",ui,"_library_page_loaded");catalog.connect("selection_changed",ui,"_library_memory_selection_changed")
    var page=tracks(["201","202","203"],50)
    ui.ui_memory.remember_location(catalog.endpoint,page,{"provider":"library","item_id":"203"},0);ui.ui_memory.save()
    check(ui.saved_library_location(catalog.endpoint).selected_id=="203","matching_server_returns_bounded_restore_intent")
    catalog.publish(tracks(["203","201","202"],50))
    check(panel.selected_item.item_id=="203" and panel.list.get_selected_items()[0]==0,"restoration_follows_item_identity_after_reorder")
    ui.saved_library_location(catalog.endpoint);catalog.publish(tracks(["201","202","203"],50))
    check(panel.selected_item.item_id=="203" and panel.list.get_selected_items()[0]==2,"restoration_selects_actual_matching_row_not_stored_index")
    ui._close_library();ui.ma_drawer.show_modal(true);panel.list.grab_focus()
    check(panel.selected_item.item_id=="203" and catalog.token=="synthetic-authorized-library","drawer_dismiss_keeps_browse_identity_and_authorized_session")
    ui.saved_library_location(catalog.endpoint);catalog.publish(tracks(["201","202"],50))
    check(panel.selected_item.item_id=="201","removed_saved_item_falls_back_to_first_authoritative_row")
    check(ui.saved_library_location("https://different.invalid").empty(),"different_server_cannot_restore_old_selection")
    ui.set_playback_context("ma");ui._open_queue()
    ui.show_tv_queue_items([{"item_id":"a","name":"Synthetic first"},{"item_id":"b","name":"Synthetic second"},{"item_id":"c","name":"Synthetic third"}],true,"")
    ui.queue_items[1].grab_focus();yield(self,"idle_frame")
    check(ui.queue_selected==1 and ui._tv_queue_selection_id=="b","remote_row_focus_remembers_queue_identity_without_activation")
    ui._refresh_tv_queue_preview()
    ui.show_tv_queue_items([{"item_id":"c","name":"Synthetic third"},{"item_id":"a","name":"Synthetic first"},{"item_id":"b","name":"Synthetic second"}],true,"")
    check(ui.queue_selected==2 and ui.queue_items[2].has_focus(),"read_refresh_restores_queue_row_by_id_after_reorder")
    ui._close_queue();ui._open_queue()
    ui.show_tv_queue_items([{"item_id":"b","name":"Synthetic second"},{"item_id":"a","name":"Synthetic first"}],true,"")
    check(ui.queue_selected==0 and ui.queue_items[0].has_focus() and ui.queue_view=="tv","queue_reopen_returns_to_same_ma_item_and_focus")
    ui._refresh_tv_queue_preview();ui.show_tv_queue_items([{"item_id":"a","name":"Synthetic first"}],true,"")
    check(ui.queue_selected==0 and ui._tv_queue_selection_id=="a","removed_queue_item_falls_back_to_live_first_row")
    app.own_client="different-own-client";ui._refresh_tv_queue_preview();ui.show_tv_queue_items([{"item_id":"new","name":"Synthetic new"},{"item_id":"a","name":"Synthetic first"}],true,"")
    check(ui.queue_selected==0,"new_own_queue_identity_does_not_reuse_old_row_bookmark")
    ui._close_queue();ui.set_playback_context("offline");ui._open_queue()
    check(ui.queue_view=="local" and ui.playback_context=="offline","queue_button_follows_actual_offline_source")
    ui._close_queue();ui._open_library_queue()
    check(ui.queue_view=="tv" and ui.playback_context=="offline","view_ma_queue_does_not_hijack_offline_transport")
    ui._close_queue()
    check(ui.playback_context=="offline" and ui.ma_drawer.visible,"queue_back_restores_library_without_source_switch")
    check(app.reads.size()>0 and app.reads.count("items")==app.reads.size() and not app.offline_music.is_playing(),"all_restoration_queue_actions_are_read_only_and_no_autoplay")
    var music=app.offline_music
    music.user_library.directory=ui.ui_memory.path+"-audio"
    music.user_library.initialize()
    var template=load(music.SOURCES[0]).data
    for i in range(27):
        var bytes=PoolByteArray(template);bytes.append(i)
        var digest_context=HashingContext.new();digest_context.start(HashingContext.HASH_SHA256);digest_context.update(bytes)
        var digest=digest_context.finish().hex_encode();var name="import_"+digest+".ogg";var file=File.new()
        file.open(music.user_library.directory.plus_file(name),File.WRITE);file.store_buffer(bytes);file.close()
        file.open(music.user_library.directory.plus_file(name+".meta.json"),File.WRITE)
        file.store_string(to_json({"version":1,"file":name,"title":"Synthetic imported "+str(i),"bytes":bytes.size(),"sha256":digest}));file.close()
    music.refresh_user_library();ui.ui_memory.remember_offline(30);ui._offline_location_seen=false
    ui._open_offline_collection()
    check(ui._offline_page==1 and ui._offline_selected==30 and ui._offline_page_indices.has(30),"offline_reopen_restores_stable_slot_on_its_actual_page")
    ui._offline_item_selected(4);ui._close_offline_collection();ui._open_offline_collection()
    check(ui._offline_page==1 and ui._offline_selected==29 and ui.offline_list.get_selected_items()[0]==4,"offline_close_and_reopen_keeps_browse_position_not_playing_track")
    check(ui.fullscreen_art!=null and ui.fullscreen_art.texture!=null,"static_fullscreen_art_remains_available")
    ui.ui_memory.save();var f=File.new();f.open(ui.ui_memory.path,File.READ);var saved=f.get_as_text();f.close()
    check(not "synthetic-authorized" in saved and not "Synthetic first" in saved and not "synthetic-own-client" in saved,"persistent_memory_excludes_credentials_titles_and_queue_payload")
    ui.ui_memory.remember_offline(28)
    ui._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    reload.load_state()
    check(reload.offline_index()==28,"background_flushes_latest_debounced_browse_choice")
    ui.ui_memory.remember_offline(27)
    app.queue_free();yield(self,"idle_frame")
    reload.load_state()
    check(reload.offline_index()==27,"normal_app_exit_flushes_latest_navigation_choice")
    print("STARTUP_MEMORY_CHECKS=",checks," FAILURES=",failures.size());quit(0 if failures.empty() else 1)
