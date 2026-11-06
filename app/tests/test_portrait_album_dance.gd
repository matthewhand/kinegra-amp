extends SceneTree
class MainFixture:
    extends "res://scripts/Main.gd"
    func _restore_music_assistant_session():return false
class CatalogFixture:
    extends "res://scripts/MACatalog.gd"
    var command=""
    var arguments={}
    func _start(cmd,args,context):
        command=cmd;arguments=args;request_context=context
        return true
var failures=[]
var checks=0
func ck(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        printerr("PORTRAIT_ALBUM_FAIL_",label)
func _init():call_deferred("run")
func run():
    var stage=preload("res://scripts/StageLayout.gd")
    var wide=Vector2(2560,1080)
    var tall=Vector2(1102,1440)
    var wide_box=stage.avatar_rect(wide,true,true,1,"body",230)
    var tall_box=stage.avatar_rect(tall,true,true,1,"body",230)
    ck(tall_box.size.y>tall.x*.50,"tall_stage_uses_more_height")
    ck(abs(tall_box.get_center().x/tall.x-.5)<abs(wide_box.get_center().x/wide.x-.5),"characters_move_toward_centre_in_portrait")
    var previous=-1.0
    for width in [700,800,900,1000,1102,1200,1440,1800,2400]:
        var spread=stage.avatar_rect(Vector2(width,1440),true,true,1,"body",230).get_center().x/width-.5
        ck(spread>=previous-.001,"spacing_changes_gradually_"+str(width));previous=spread
    var dance=preload("res://scripts/BackupChoreography.gd").new()
    dance.step(.2,{"kind":"none","signal":false},true,false)
    var before=dance.pose(0)
    for _i in range(20):dance.step(.1,{"kind":"none","signal":false},true,false)
    ck(not before.empty() and dance.pose(0)!=before and dance.kind=="default_dance","dances_before_beat_lock")
    var fallback_rate=dance.rate
    for _i in range(30):dance.step(.1,{"kind":"estimated_onsets","bpm":160,"family":"fast","phase":.5},true,false)
    ck(dance.rate>fallback_rate and dance.family=="fast","tempo_adjusts_moves_and_speed")
    dance.step(.1,{},false,false);ck(dance.pose(0).empty(),"stopped_audio_stops_dancing")
    var catalog=CatalogFixture.new();get_root().add_child(catalog);catalog.token="synthetic";catalog.endpoint="https://synthetic.invalid"
    ck(catalog.browse("albums","Suno",25) and catalog.command=="music/albums/library_items" and catalog.arguments.search=="Suno" and catalog.arguments.offset==25,"album_search_is_server_paged")
    catalog.current_page={"items":[{"provider":"library","item_id":"12","media_type":"album","name":"Synthetic album"}]}
    ck(catalog.select_index(0) and catalog.album_items() and catalog.command=="music/albums/album_tracks" and catalog.arguments.in_library_only,"open_album_is_bounded_read_only_library_request")
    catalog.playlist_snapshot=[]
    for index in range(100):catalog.playlist_snapshot.append({"provider":"library","item_id":str(index+1),"media_type":"track","name":"Synthetic track "+str(index),"artist":"Suno","album":"Synthetic album"})
    catalog.playlist_snapshot_valid=true;catalog.playlist_returned_count=100
    catalog.playlist_page(75)
    ck(catalog.current_page.items.size()==25 and catalog.current_page.items[20].name=="Synthetic track 95","all_100_retrieved_tracks_are_browsable")
    catalog.playlist_page(0,"track 95")
    ck(catalog.current_page.items.size()==1 and catalog.current_page.items[0].item_id=="96","collection_filter_finds_late_track")
    var app=MainFixture.new();get_root().add_child(app);yield(create_timer(.3),"timeout");app.set_process(false);AudioServer.set_bus_mute(0,true)
    var ui=app.music_ui;ui.set_process(false)
    app.volume_path="user://volume-check-"+str(OS.get_ticks_usec())+".cfg"
    ck(app.app_volume_percent==100 and not ui.volume_tag.visible,"app_volume_defaults_to_100_without_indicator")
    app.set_app_volume(50)
    ck(ui.volume_tag.visible and "50%" in ui.volume_tag.text and abs(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Milkdrop"))+6.0206)<.01,"half_volume_uses_local_gain_and_persistent_indicator")
    app._flush_app_volume()
    ck(app.volume_store.read(app.volume_path).found,"app_volume_persists")
    app.set_app_volume(0)
    ck(AudioServer.is_bus_mute(AudioServer.get_bus_index("Milkdrop")),"zero_volume_mutes_app_bus")
    ck(not app.set_app_volume(NAN),"invalid_gain_rejected")
    app.set_app_volume(100);app._flush_app_volume()
    ck(not ui.volume_tag.visible and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Milkdrop")),"full_volume_restores_gain_and_hides_indicator")
    Directory.new().remove(app.volume_path)
    for size in [Vector2(1102,1440),Vector2(720,1280),Vector2(1920,1080),Vector2(960,720)]:
        get_root().size=size;app.rect_size=size;ui.root.rect_size=size;ui._apply_tv_typography()
        for _i in range(6):yield(self,"idle_frame")
        ck(ui.player_card.rect_position.y+ui.player_card.rect_size.y<=size.y+2,"transport_fits_"+str(size))
        if size.y>size.x:
            ck(ui.player_card.rect_position.y<300 and not ui.track_hero.visible,"portrait_controls_have_no_dead_top_gap_or_duplicate_hero_"+str(size))
            ck(ui.player_card.rect_position.y>=ui.header_card.rect_position.y+ui.header_card.rect_size.y,"toolbar_and_transport_do_not_overlap_"+str(size))
        ui.ma_drawer.show()
        for _i in range(4):yield(self,"idle_frame")
        app.ma_panel.search_edit.grab_focus()
        for code in [KEY_UP,KEY_UP,KEY_RIGHT]:
            var event=InputEventKey.new();event.scancode=code;event.pressed=true
            ui.route_drawer_input(event)
        var category=ui.root.get_focus_owner()
        ck(category is Button and category.text=="ALBUMS","right_reaches_albums_without_diagonal_search_jump_"+str(size))
        var search=app.ma_panel.search_edit.get_global_rect()
        ck(search.position.x>=0 and search.end.x<=size.x+2 and search.position.y>=0 and search.end.y<=size.y,"search_remains_on_screen_"+str(size))
        ui.ma_drawer.hide()
    get_root().size=tall;app.rect_size=tall;ui.root.rect_size=tall
    app.pose_visual.set_mode("off");app.backing_dancers.pressed=true
    ui._enter_fullscreen()
    yield(create_timer(.45),"timeout")
    ck(not ui.stage_cover.visible and ui.fullscreen_cover==null and ui.fullscreen_art.rect_size.x>200,"fullscreen_uses_one_expanded_cover")
    ck(ui.fullscreen_track.rect_position.y>250 and ui.fullscreen_track_title.rect_position.y>ui.fullscreen_art.rect_position.y+ui.fullscreen_art.rect_size.y,"card_centres_and_text_moves_below_cover")
    app.set_visuals_enabled(false)
    ui._exit_fullscreen();ui._apply_tv_typography();ui.sync_static_art()
    ck(ui.stage_cover.visible and not ui.artwork.get_parent().visible,"portrait_warmup_shows_one_large_cover")
    ui._enter_fullscreen()
    ui._set_cover_morph(0.0)
    ck(ui.fullscreen_art.rect_size.x==94 and ui.fullscreen_track_title.rect_position.x>100,"same_card_returns_to_compact_top_bar")
    catalog.queue_free();app.queue_free();yield(self,"idle_frame")
    print("PORTRAIT_ALBUM_DANCE_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
