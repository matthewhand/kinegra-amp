extends SceneTree
class RuntimeFixture:
    extends Reference
    var active=true
    var buffering=false
    func invalidate_buffer_measurement():pass
class ClientFixture:
    extends Reference
    func status():return {"paired":true,"client_id":"own-client","active":true,"generation":1}
class FacadeFixture:
    extends Node
    var client=ClientFixture.new()
    var runtime=RuntimeFixture.new()
    var sink=null
    func stop():runtime.active=false
var failures=[]
var checks=0
func check(ok,label):
    checks+=1
    if not ok:failures.append(label)
    print("OFFLINE_SAVE_"+("PASS_" if ok else "FAIL_")+label)
func _init():call_deferred("run")
func run():
    AudioServer.set_bus_mute(0,true)
    var app=load("res://scripts/Main.gd").new();get_root().add_child(app)
    yield(create_timer(.1),"timeout")
    app.set_process(false);app.music_ui.set_process(false)
    app.offline_music.user_library.initialize()
    var panel=app.ma_panel
    for timer in [app.tv_queue_timer,app.tv_reconnect_timer,app.tv_audio_wait_timer,panel.sendspin_refresh_timer]:
        if timer!=null:timer.stop()
    panel.library_disconnected=false
    panel.endpoint_edit.text=OS.get_environment("OFFLINE_MA_URL")
    panel.lan_trust.pressed=true
    panel.catalog.configure(panel.endpoint_edit.text,"synthetic-library-token",[],true)
    panel.library_disconnected=false
    app._on_library_credentials_authorized(panel.catalog.token,panel.endpoint_edit.text)
    var facade=FacadeFixture.new();app.add_child(facade);app.sendspin_facade=facade
    panel.sendspin_paired=true;panel.sendspin_player_id="own-client"
    app.music_ui.set_playback_context("ma")
    var saver=app.offline_save
    check(not saver.configure("http://public.invalid","synthetic-source-key-1234567890123456"),"nonprivate_source_rejected")
    check(saver.configure(OS.get_environment("OFFLINE_SOURCE_URL"),"synthetic-source-key-1234567890123456") and saver.configured(),"explicit_source_saved")
    check(saver.begin(),"explicit_save_begins")
    print("SAVE_MESSAGE=",saver.message)
    check(not saver.begin(),"second_save_does_not_overlap")
    var deadline=OS.get_ticks_msec()+25000
    var played_during_copy=false
    while saver.active and OS.get_ticks_msec()<deadline:
        if OS.get_environment("OFFLINE_MODE")=="during" and saver.copied>=2 and not played_during_copy:
            check(saver.play_saved(),"completed_prefix_can_play_while_copying")
            played_during_copy=true
        if OS.get_environment("OFFLINE_MODE")=="cancel" and saver.copied>=1:saver.cancel()
        yield(create_timer(.025),"timeout")
    check(not saver.active,"operation_completes_within_bound")
    if OS.get_environment("OFFLINE_MODE")=="cancel":
        check(saver.state=="cancelled" and saver.copied>=1,"cancel_keeps_completed_files")
    elif OS.get_environment("OFFLINE_MODE")=="corrupt":
        check(saver.copied==0 and saver.failed==34 and saver.state=="error" and app.offline_music.user_library.slots.empty(),"corrupt_audio_never_enters_library")
    else:
        check(saver.state=="complete" and saver.copied==34 and saver.skipped==1 and saver.failed==0,"paged_queue_copied_without_provider_downloads")
        check(saver.saved_indices.size()==34 and saver.saved_indices[0]==saver.saved_indices[2],"snapshot_order_and_duplicates_preserved")
        var stored=saver.queue_store.read(saver.saved_queue_path)
        check(stored.ok and stored.items==saver.saved_indices,"saved_snapshot_order_persists_to_disk")
        check(app.offline_music.user_library.slots.size()==2,"identical_audio_reuses_verified_offline_file")
        check(saver.play_saved() and app.offline_music.upcoming_queue.size()==33 and app.music_ui.playback_context=="offline","explicit_play_saved_switches_to_full_local_queue")
        if OS.get_environment("OFFLINE_MODE")=="during":check(played_during_copy,"copy_finished_after_switch_to_local_audio")
        app.music_ui._open_queue()
        app.music_ui._queue_next_page()
        check(app.music_ui.queue_local_first==32 and app.music_ui.queue_selected==32 and app.music_ui.queue_items[0].text.find("33")>=0,"large_local_queue_has_visible_second_page")
        app.music_ui._queue_select_index(0)
        app.music_ui._queue_remove()
        check(app.offline_music.upcoming_queue.size()==32,"second_page_remove_targets_absolute_index")
        app.music_ui._queue_previous_page()
        check(app.music_ui.queue_local_first==0,"previous_page_returns_to_start")
        app.music_ui._close_queue()
        check(app.offline_music.player.stream!=null and app.offline_music.player.stream.get_length()>0,"saved_audio_decodes_locally")
        app.offline_music.player.seek(.1)
        check(app.offline_music.player.stream!=null,"local_seek_needs_no_network")
    print("OFFLINE_SAVE_STATE=",saver.state," SAVED=",saver.copied," SKIPPED=",saver.skipped," FAILED=",saver.failed)
    saver.cancel();app._stop_all_music();app.queue_free()
    yield(self,"idle_frame")
    print("OFFLINE_SAVE_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
