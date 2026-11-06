extends SceneTree
# Actual Main/Panel intent and callback policy; native open and transport I/O
# are synthetic. No HTTP, real pairing, saved credential or device operation.
class RuntimeFixture:
    extends Reference
    var active=true
    var buffering=false
    var invalidations=0
    func invalidate_buffer_measurement():invalidations+=1
class ClientFixture:
    extends Reference
    var paired=false
    var id="synthetic-own-client"
    func status():return {"paired":paired,"client_id":id,"active":false,"generation":0}
class FacadeFixture:
    extends Node
    var client=ClientFixture.new()
    var runtime=RuntimeFixture.new()
    var sink=null
    var stopped=0
    func stop():
        stopped+=1
        runtime.active=false
class CatalogFixture:
    extends "res://scripts/MACatalog.gd"
    var route_ready=false
    var own_client="synthetic-own-client"
    var writes=[]
    var reads=0
    func discover_players():
        reads+=1
        return true
    func resolve_local_player(client_id):
        return "synthetic-own-queue" if route_ready and client_id==own_client else ""
    func _start(command,args,_context):
        if command=="player_queues/play_media":writes.append({"command":command,"args":args.duplicate(true)})
        else:reads+=1
        return true
class MainFixture:
    extends "res://scripts/Main.gd"
    var starts=[]
    var transport=[]
    var offline_starts=0
    func _start_sendspin_player(endpoint,trusted):
        if sendspin_facade!=null and sendspin_facade.runtime.active:return
        starts.append({"endpoint":endpoint,"trusted":trusted})
        var facade=FacadeFixture.new();add_child(facade);sendspin_facade=facade
        _on_sendspin_state("connecting","Synthetic connection in progress",facade)
    func _sendspin_command(command,argument=null):
        if command=="play":
            transport.append(command)
            return true
        return ._sendspin_command(command,argument)
    func _play_offline_music():offline_starts+=1
var app=null
var panel=null
var catalog=null
var checks=0
var failures=[]
var retired=[]
func check(ok,label):
    checks+=1
    print("DIRECT_PLAY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func stop_timers():
    for timer in [app.tv_queue_timer,app.tv_reconnect_timer,app.tv_audio_wait_timer,panel.sendspin_refresh_timer]:
        if timer!=null:timer.stop()
func seed_session():
    app._cancel_requested_play();stop_timers()
    if app.sendspin_facade!=null:
        app.sendspin_facade.runtime.active=false
        retired.append(app.sendspin_facade)
        app.sendspin_facade=null
    app.starts.clear();app.transport.clear();app.tv_queue_request=null
    app.music_ui.set_playback_context("ma")
    if app.music_ui.library_config_popup!=null:app.music_ui.library_config_popup.hide()
    panel.setup_box.hide();panel.sendspin_box.hide()
    panel.library_disconnected=false
    panel.endpoint_edit.text="https://synthetic.invalid"
    panel.sendspin_endpoint.text="ws://10.1.2.3:8927/sendspin"
    panel.sendspin_trust.pressed=true
    panel.sendspin_paired=false;panel.sendspin_player_id=""
    panel.playback_state="idle"
    catalog.route_ready=false;catalog.own_client="synthetic-own-client";catalog.writes.clear()
    catalog.configure("https://synthetic.invalid","synthetic-library-access",[],false)
    app._on_library_credentials_authorized(catalog.token,"https://synthetic.invalid")
    catalog.current_page={"kind":"tracks","offset":0,"search":"","items":[
        {"item_id":"7","provider":"library","media_type":"track","available":true,"name":"Synthetic first track"},
        {"item_id":"8","provider":"library","media_type":"track","available":true,"name":"Synthetic chosen track"}]}
    panel._on_page(catalog.current_page)
    panel.list.select(1);panel._select_index(1)
    stop_timers()
func paired(facade,ready=true):
    catalog.route_ready=ready
    if is_instance_valid(facade):
        facade.client.paired=true
        app._on_sendspin_state("paired","Synthetic authenticated identity",facade)
    stop_timers()
func deliver_players():
    panel._on_players([])
    app._continue_queue_resume()
    stop_timers()
func cancel_case(reason,facade,resume):
    if reason=="back":
        app.music_ui.ma_drawer.show_modal(true)
        app._handle_tv_back("input")
    elif reason=="stop":app._sendspin_command("stop")
    elif reason=="disconnect":panel._disconnect_library()
    elif reason=="cancel":
        if resume:app._cancel_requested_play()
        else:panel._cancel()
    elif reason=="server_change":
        panel.endpoint_edit.text="https://other.invalid"
        panel.endpoint_edit.emit_signal("text_changed",panel.endpoint_edit.text)
    elif reason=="origin":panel.endpoint_edit.text="https://other.invalid"
    elif reason=="epoch":catalog.epoch+=1
    elif reason=="selection":
        panel.list.select(0)
        panel._select_index(0)
    elif reason=="endpoint":panel.sendspin_endpoint.text="ws://10.1.2.4:8927/sendspin"
    elif reason=="client":
        facade.client.id="synthetic-other-client"
        catalog.own_client="synthetic-other-client"
    elif reason=="facade":
        var replacement=FacadeFixture.new();app.add_child(replacement)
        app.sendspin_facade=replacement
        return replacement
    elif reason=="timeout":
        if resume:app.pending_queue_resume.deadline=OS.get_ticks_msec()-1
        else:panel.connect_play_deadline=OS.get_ticks_msec()-1
    return facade
func run():
    AudioServer.set_bus_mute(0,true)
    app=MainFixture.new();get_root().add_child(app)
    yield(create_timer(.2),"timeout");app.set_process(false);app.music_ui.set_process(false)
    panel=app.ma_panel;panel.settings_path="user://direct-play-synthetic.cfg"
    check(app.transport.empty() and app.offline_starts==0 and not app.offline_music.is_playing(),"cold_start_never_plays_or_falls_back_to_builtins")
    check(app.music_ui._tv_mode(),"cold_start_uses_music_assistant_context")
    var old=panel.catalog;old.close();old.queue_free()
    catalog=CatalogFixture.new();panel.add_child(catalog);panel.catalog=catalog
    catalog.connect("state_changed",panel,"_on_state");catalog.connect("page_ready",panel,"_on_page")
    catalog.connect("selection_changed",panel,"_on_selection");catalog.connect("players_ready",panel,"_on_players")
    seed_session()
    # A background model selection cannot replace the visible stable row.
    catalog.selected=catalog.current_page.items[0].duplicate(true)
    panel._play_on_player();panel._play_on_player()
    check(app.starts.size()==1 and catalog.writes.empty(),"library_play_starts_connection_once_without_early_mutation")
    check(panel.connect_play_item.get("item_id")=="8","connect_keeps_exact_visible_selected_item")
    var facade=app.sendspin_facade
    paired(facade,false);yield(self,"idle_frame")
    check(catalog.writes.empty() and not panel.connect_play_item.empty(),"paired_without_exact_route_keeps_waiting")
    catalog.route_ready=true;deliver_players();yield(self,"idle_frame")
    check(catalog.writes.size()==1,"paired_resolved_route_consumes_selected_play_once")
    if catalog.writes.size()==1:
        var args=catalog.writes[0].args
        check(args.get("queue_id")=="synthetic-own-queue" and args.get("media")=="library://track/8" and args.get("option")=="play","deferred_play_uses_exact_selected_media_and_own_queue")
    else:check(false,"deferred_play_uses_exact_selected_media_and_own_queue")
    deliver_players();paired(facade,true);yield(self,"idle_frame")
    check(catalog.writes.size()==1 and panel.connect_play_item.empty(),"duplicate_pair_and_players_callbacks_cannot_repeat_selected_mutation")
    var reasons=["back","stop","disconnect","cancel","server_change","origin","epoch","selection","endpoint","client","facade","timeout"]
    for reason in reasons:
        seed_session();panel._play_on_player();facade=app.sendspin_facade
        check(facade!=null and not panel.connect_play_item.empty(),"library_"+reason+"_intent_is_armed")
        facade=cancel_case(reason,facade,false)
        paired(facade,true);deliver_players();yield(self,"idle_frame")
        check(catalog.writes.empty() and app.transport.empty(),"library_"+reason+"_suppresses_late_deferred_play")
        check(panel.connect_play_item.empty(),"library_"+reason+"_releases_pending_intent")
    seed_session();app.music_ui._toggle();app.music_ui._toggle()
    check(app.starts.size()==1 and not app.pending_queue_resume.empty() and app.transport.empty(),"main_play_connects_once_and_keeps_resume_intent")
    facade=app.sendspin_facade
    paired(facade,false);app._continue_queue_resume()
    check(app.transport.empty(),"main_resume_waits_for_verified_own_route")
    catalog.route_ready=true;deliver_players();deliver_players()
    check(app.transport==["play"] and app.pending_queue_resume.empty() and app.offline_starts==0,"main_play_resumes_own_queue_once_without_builtin_fallback")
    for reason in ["back","stop","disconnect","cancel","server_change","origin","epoch","endpoint","client","facade","timeout"]:
        seed_session();app._play_music_assistant();facade=app.sendspin_facade
        check(facade!=null and not app.pending_queue_resume.empty(),"resume_"+reason+"_intent_is_armed")
        facade=cancel_case(reason,facade,true)
        paired(facade,true);deliver_players();yield(self,"idle_frame")
        check(app.transport.empty() and catalog.writes.empty(),"resume_"+reason+"_suppresses_late_play")
        check(app.pending_queue_resume.empty(),"resume_"+reason+"_releases_pending_intent")
    check(app.offline_starts==0 and not app.offline_music.is_playing(),"all_recovery_paths_never_start_builtin_samples")
    app._cancel_requested_play();stop_timers();app.sendspin_facade=null;app.queue_free()
    print("DIRECT_PLAY_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
