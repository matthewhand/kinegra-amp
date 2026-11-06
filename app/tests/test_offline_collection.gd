extends SceneTree
# Bundled compatibility and independent browsing, using only synthetic host media.
var checks = 0
var failures = []
func ck(ok,note):
    checks += 1
    if not ok:
        failures.append(note)
        printerr("FAIL ",note)
func _init():call_deferred("run")
func back(app):
    var e = InputEventJoypadButton.new()
    e.device = 0
    e.button_index = 1
    e.pressed = true
    app._input(e)
    e.pressed=false
    app._input(e)
func run():
    var app = load("res://Main.tscn").instance()
    get_root().add_child(app)
    yield(create_timer(.15),"timeout")
    var ui = app.music_ui
    var music = app.offline_music
    ck(ui.offline_drawer != null and not ui.offline_drawer.visible,"drawer_initially_closed")
    ck(ui.library_button.has_focus() and not music.is_playing(),"initial_focus_and_silence")
    ui._open_offline_collection()
    ck(ui.offline_drawer.visible and ui.offline_mix_button.has_focus(),"drawer_focus_enters_mix")
    ck(ui.offline_list.get_item_count() == 4 and ui._offline_page_indices == [0,1,2,3],"original_four_slots_unchanged")
    ck(ui.offline_summary.text.begins_with("4 IN THIS MIX / 4 AVAILABLE"),"real_count")
    ck(app.ma_panel.catalog.token.empty(),"local_browser_no_credentials")
    for i in range(4):ck(music.TITLES[i] in ui.offline_list.get_item_text(i),"bundled_title_"+str(i))
    ui._cue_offline_2()
    ck(ui._offline_selected == 2 and music.track_index == 0 and not music.is_playing(),"selection_independent_of_player")
    ck(ui.offline_play_button.has_focus(),"selection_has_explicit_play_target")
    ui._cycle_offline_collection()
    ck(music.playlists.playlist_index == 1 and ui._offline_page_indices == [0,2,3],"night_flight_subset")
    ui._cue_offline_3()
    ck(ui._offline_selected == 3 and not music.is_playing(),"valid_filtered_selection_silent")
    ui._toggle_offline_drawer_favorite()
    ck(music.playlists.is_favorite(3) and ui.offline_favorite_button.text == "REMOVE FAV","selected_row_favourite")
    ui._cycle_offline_collection()
    ck(ui._offline_page_indices == [1,3],"heavy_rotation_subset")
    ui._cycle_offline_collection()
    ck(music.playlists.playlist_index == 3 and ui._offline_page_indices == [3],"favourites_subset")
    back(app)
    ck(not ui.offline_drawer.visible and ui.offline_button.has_focus() and not music.is_playing(),"back_closes_without_playing")
    ui._open_offline_collection()
    ui._play_cued_from_drawer()
    yield(create_timer(.1),"timeout")
    ck(music.is_playing() and music.track_index == 3 and not ui.offline_drawer.visible,"explicit_play_selected_bundled")
    ui._open_offline_collection()
    back(app)
    ck(music.is_playing() and ui.offline_button.has_focus(),"closing_drawer_preserves_audio")
    app._stop_all_music()
    app.free()
    print("METHEXIS_COLLECTION_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
