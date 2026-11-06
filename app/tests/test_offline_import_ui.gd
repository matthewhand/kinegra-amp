extends SceneTree
var failures = 0
var checks = 0
var base = "user://offline_import_ui_"+str(OS.get_ticks_msec())
class Picker extends Reference:
    var starts = 0
    var cancels = 0
    var destination = ""
    var status = {"state":"choosing","imported":0,"skipped":0,"errors":0}
    func beginOfflineImport(path):
        starts += 1
        destination = path
        return true
    func offlineImportStatus():return to_json(status)
    func cancelOfflineImport():
        cancels += 1
        return true
class SpyMain extends "res://scripts/Main.gd":
    var stop_calls = 0
    func _stop_all_music():
        stop_calls += 1
        ._stop_all_music()
func check(ok,name):
    checks += 1
    if not ok:
        failures += 1
        print("FAIL_OFFLINE_IMPORT_UI ",name)
func event(action):
    var result = InputEventAction.new()
    result.action = action
    result.pressed = true
    return result
func _init():call_deferred("run")
func run():
    var app = SpyMain.new()
    get_root().add_child(app)
    var ui = app.music_ui
    var music = app.offline_music
    app.set_visuals_enabled(false)
    music.user_library.directory = base
    check(music.user_library.initialize(),"isolated_user_catalog")
    var template = load(music.SOURCES[0]).data
    for i in range(52):
        var data = PoolByteArray(template)
        data.append(i)
        var digest_context = HashingContext.new()
        digest_context.start(HashingContext.HASH_SHA256)
        digest_context.update(data)
        var digest = digest_context.finish().hex_encode()
        var name = "import_"+digest+".ogg"
        var f = File.new()
        f.open(base.plus_file(name),File.WRITE)
        f.store_buffer(data)
        f.close()
        f.open(base.plus_file(name+".meta.json"),File.WRITE)
        f.store_string(to_json({"version":1,"file":name,"title":"Synthetic imported song %02d"%i,"sha256":digest,"bytes":data.size()}))
        f.close()
    ui.set_playback_context("ma");ui.source_label.text = "MUSIC ASSISTANT  •  PLAYING HERE"
    var stopped = app.stop_calls
    check(music.refresh_user_library() and music.track_count() == 56,"large_library_adopted")
    ui._open_offline_collection()
    yield(create_timer(.1),"timeout")
    check(ui.offline_list.get_item_count() == 25 and ui.offline_page_label.text == "1 / 3","exact_twentyfive_row_page")
    ui._offline_page_next()
    ui.offline_list.select(0)
    ui._offline_item_selected(0)
    check(ui._offline_page_indices.size() == 25 and ui._offline_selected == 25,"second_page_stable_index")
    check(app.stop_calls == stopped and ui.playback_context == "ma" and ui.source_label.text.begins_with("MUSIC ASSISTANT") and not music.is_playing(),"browse_preserves_existing_source")
    ui._queue_selected_offline()
    check(music.upcoming_queue == [25] and app.stop_calls == stopped,"add_selected_local_queue_no_source_change")
    ui._toggle_offline_drawer_favorite()
    check(music.playlists.is_favorite(25) and not music.playlists.is_favorite(0),"selected_import_favourite_not_current")
    ui._offline_page_next()
    check(ui.offline_list.get_item_count() == 6 and ui.offline_next_page.disabled,"last_page_real_count")
    ui._offline_page_next()
    check(ui._offline_page == 2,"last_page_bounded")
    var picker = Picker.new()
    ui.offline_import.platform = picker
    ui._begin_offline_import()
    check(picker.starts == 1 and picker.destination == ProjectSettings.globalize_path(base) and ui.offline_cancel_import_button.visible,"picker_private_destination_and_cancel")
    check(not ui.offline_import.begin() and picker.starts == 1,"busy_begin_no_duplicate_worker")
    picker.status = {"state":"copying","imported":1,"skipped":2,"errors":1}
    ui.offline_import._poll()
    check(ui.offline_import.state == "copying" and ui.offline_import_status.text.find("1 IMPORTED") >= 0,"honest_partial_progress")
    ui._cancel_offline_import()
    check(picker.cancels == 1 and ui.offline_import.state == "cancelling" and ui.offline_cancel_import_button.disabled,"cancel_waits_provider")
    picker.status.state = "timed_out"
    ui.offline_import._poll()
    check(ui.offline_import.state == "timed_out" and not ui.offline_import.is_processing() and not ui.offline_cancel_import_button.visible,"timeout_terminal_stops_polling")
    check(app.stop_calls == stopped and ui.playback_context == "ma" and ui.source_label.text.begins_with("MUSIC ASSISTANT"),"partial_import_refresh_preserves_source")
    picker.status = {"state":"complete","imported":0,"skipped":1,"errors":0}
    ui.offline_import.begin()
    ui.offline_import._poll()
    check(ui.offline_import.state == "complete" and not ui.offline_import.is_processing(),"complete_stops_polling")
    ui.offline_import.platform = null
    check(not ui.offline_import.begin() and ui.offline_import.state == "picker_unavailable","unavailable_not_fake_success")
    for size in [Vector2(480,800),Vector2(720,1280),Vector2(960,720),Vector2(1280,720),Vector2(1720,720)]:
        OS.window_size = size
        app._apply_resolution_base()
        yield(create_timer(.1),"timeout")
        for large in [false,true]:
            ui.set_tv_text_mode(large)
            ui._apply_compact_layout()
            yield(create_timer(.1),"timeout")
            var suffix = str(size) + ("_large" if large else "_normal")
            var viewport = Rect2(Vector2.ZERO,size)
            check(viewport.encloses(ui.offline_drawer.get_global_rect()),"drawer_bounds_"+suffix)
            check(ui.offline_list.rect_size.x <= ui.offline_drawer.rect_size.x and ui.offline_list.rect_size.x > 200,"list_width_"+suffix)
            ui._offline_page = 0
            ui._offline_selected = 0
            ui._refresh_offline_collection()
            ui.offline_list.select(0)
            ui.offline_list.grab_focus()
            check(ui.route_drawer_input(event("ui_up")) and ui.root.get_focus_owner() == ui.offline_mix_button,"first_row_up_reaches_mix_"+suffix)
            ui.offline_list.grab_focus()
            check(ui.route_drawer_input(event("ui_right")) and ui.root.get_focus_owner() == ui.offline_play_button,"right_reaches_play_"+suffix)
            ui.offline_import_button.grab_focus()
            yield(create_timer(.1),"timeout")
            if not ui.offline_drawer.get_global_rect().encloses(ui.offline_import_button.get_global_rect()): print("IMPORT_FOCUS_RECT ",suffix," drawer=",ui.offline_drawer.get_global_rect()," button=",ui.offline_import_button.get_global_rect())
            check(ui.offline_drawer.get_global_rect().encloses(ui.offline_import_button.get_global_rect()),"import_scrolls_into_view_"+suffix)
    var capture_dir = OS.get_environment("SHIELDAMP_QA_SCREENSHOT_DIR")
    if not capture_dir.empty():
        Directory.new().make_dir_recursive(capture_dir)
        for spec in [["portrait",Vector2(720,1280)],["wide",Vector2(1720,720)]]:
            OS.window_size = spec[1]
            app._apply_resolution_base()
            ui._apply_compact_layout()
            yield(create_timer(.2),"timeout")
            var image = get_root().get_texture().get_data()
            image.flip_y()
            image.save_png(capture_dir.plus_file("offline-library-"+spec[0]+".png"))
    ui.set_tv_text_mode(false)
    ui._cue_offline_track(4)
    ui._play_cued_from_drawer()
    check(app.stop_calls > stopped and ui.playback_context == "offline" and music.track_index == 4 and music.is_playing(),"explicit_play_changes_source_and_starts_selected_import")
    ui._sync_offline_art()
    check(ui.artwork.texture != null and ui.artwork_caption.text == "BRAND ART","import_brand_art_no_array_bounds")
    music.stop()
    ui._offline_selected = 4
    ui._confirm_remove_sample()
    ui._offline_selected = 5
    ui._remove_selected_sample()
    check(not music.available(4) and music.available(5),"delete_confirmation_target_cannot_shift")
    var dir = Directory.new()
    dir.open(base)
    dir.list_dir_begin(true,true)
    var names = []
    var name = dir.get_next()
    while not name.empty():
        names.append(name)
        name = dir.get_next()
    dir.list_dir_end()
    for item in names:dir.remove(item)
    Directory.new().remove(base)
    app.free()
    print("OFFLINE_IMPORT_UI_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures == 0 else 1)
