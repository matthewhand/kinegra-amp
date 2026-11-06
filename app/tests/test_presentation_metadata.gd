extends SceneTree
class FixtureCatalog:
    extends Reference
    var endpoint=""
    var token=""
    var trusted_private_http=true
    var epoch=1
class FixtureTrust:
    extends Reference
    var pressed=true
class FixtureLibrary:
    extends Reference
    signal credential_session_closed(reason)
    var catalog=FixtureCatalog.new()
    var lan_trust=FixtureTrust.new()
    var library_disconnected=false
    var endpoint="https://fictional-ma.invalid"
    var bound_endpoint="https://fictional-ma.invalid"
    var reads=0
    func _credential_endpoint():return endpoint
    func _read_provisioned_token():
        reads+=1
        return "fictional-origin-bound-token" if endpoint==bound_endpoint else ""
class FixtureRuntime:
    extends Reference
    var active=true
class FixtureFacade:
    extends Reference
    var runtime=FixtureRuntime.new()
class FixtureArtwork:
    extends "res://scripts/MAArtworkController.gd"
    var selections=0
    func select(_descriptor,_context):
        selections+=1
        return true # Credentials are tested without any actual request.
var failures=[]
func check(ok,label):
    print("PRESENTATION_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func key(code):
    var event=InputEventKey.new();event.scancode=code;event.pressed=true
    return event
func route_key(ui,code):
    var event=key(code)
    ui.route_drawer_input(event)
    event.pressed=false
    ui.route_drawer_input(event)
func _init():call_deferred("run")
func run():
    AudioServer.set_bus_mute(0,true)
    var app=load("res://Main.tscn").instance()
    app.set_script(load("res://tests/FakePresentationMain.gd"))
    get_root().add_child(app)
    yield(create_timer(.3),"timeout")
    app.set_process(false)
    var ui=app.music_ui
    ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    app.fixture_fresh=true
    var now=OS.get_ticks_msec()
    var long_title="Example genuine current track — "+"a long title ".repeat(25)
    var snapshot={"current_id":"fictional-current","current":long_title,"artist":"Example artist","album":"Example album","active":true,"state":"playing","duration":180.0,"elapsed":30.0,"elapsed_updated":1700000000.0,"clock_valid":true,"server_time":1700000000,"clock_received_ms":now,"clock_rtt_ms":20}
    ui.show_tv_queue_snapshot(snapshot)
    ui._enter_fullscreen()
    ui._process(.21)
    check(ui.fullscreen_track_title.text==long_title and "Example artist" in ui.fullscreen_track_artist.text and ui.fullscreen_album.text=="ALBUM: Example album","genuine_current_metadata")
    check("00:30 / 03:00" in ui.fullscreen_playback.text and "LIVE AUDIO" in ui.fullscreen_playback.text,"server_clock_progress_with_live_pcm")
    ui.show_ma_selection("Different catalog choice","Other artist","Other album")
    check(ui.fullscreen_track_title.text==long_title,"selection_never_replaces_current_live_track")
    route_key(ui,KEY_ENTER)
    check(app.fixture_commands.back()=="pause","remote_ok_pauses_live_playback")
    app.fixture_fresh=false
    route_key(ui,KEY_ENTER)
    check(app.fixture_commands.back()=="play","remote_ok_plays_paused_playback")
    route_key(ui,KEY_LEFT);route_key(ui,KEY_RIGHT)
    check(app.fixture_commands.slice(app.fixture_commands.size()-2,app.fixture_commands.size()-1)==["previous","next"],"remote_previous_next")
    snapshot.state="paused"
    ui.show_tv_queue_snapshot(snapshot)
    ui._process(.21)
    check("LAST REPORTED 00:30 / 03:00" in ui.fullscreen_playback.text and not "LIVE AUDIO" in ui.fullscreen_playback.text,"paused_timeline_held_honestly")
    snapshot.erase("duration");snapshot.erase("artist");snapshot.erase("album")
    ui.show_tv_queue_snapshot(snapshot);ui._process(.21)
    check("Artist not provided" in ui.fullscreen_track_artist.text and ui.fullscreen_album.text.empty() and not ui.fullscreen_album.visible and not "03:00" in ui.fullscreen_playback.text,"missing_fields_revoke_previous_credits_and_duration")
    ui._tv_snapshot_at=OS.get_ticks_msec()-10001;ui._process(.21)
    check(ui.fullscreen_track_title.text=="Waiting for track information" and ui.artwork_caption.text=="BRAND ART","stale_metadata_and_cover_cleared")
    snapshot["duration"]=180.0;snapshot["artist"]="Example artist";snapshot["album"]="Example album"
    ui.show_tv_queue_snapshot(snapshot);ui._process(.21)
    ui.set_process(false)
    var image=Image.new();image.create(8,8,false,Image.FORMAT_RGB8);image.fill(Color(0.2,0.4,0.7))
    var texture=ImageTexture.new();texture.create_from_image(image,0)
    ui._artwork_context="synthetic-cover";ui._artwork_ready("synthetic-cover",texture)
    check(ui.artwork.texture==texture and ui.fullscreen_art.texture==texture and ui.track_hero.cover==texture and ui.fullscreen_art_caption.text=="COVER","cover_shared_across_player_hero_and_fullscreen")
    ui.track_hero.set_render_budget(0)
    check(not ui.track_hero.is_processing() and ui.track_hero.cover==texture,"zero_budget_preserves_static_cover")
    for dimension in [Vector2(960,720),Vector2(1280,720),Vector2(1920,720),Vector2(720,1280),Vector2(480,640)]:
        OS.window_size=dimension;app._apply_resolution_base()
        yield(create_timer(.15),"timeout")
        ui.set_tv_text_mode(true);ui._fit_fullscreen_layout()
        yield(create_timer(.08),"timeout")
        var extent=ui.root.rect_size
        var card=ui.fullscreen_track.get_global_rect()
        var help=ui.fullscreen_help.get_global_rect()
        var help_text=ui.fullscreen_help.get_child(0).get_child(0)
        check(help_text.get_line_count()>=3 and help_text.get_visible_line_count()>=help_text.get_line_count(),"all_remote_help_visible_"+str(dimension))
        check(card.position.x>=0 and card.end.x<=extent.x+2 and card.position.y>=0 and card.end.y<=extent.y+2,"metadata_card_bounded_"+str(dimension))
        check(help.position.x>=0 and help.end.x<=extent.x+2 and help.position.y>=0 and help.end.y<=extent.y+2,"remote_help_bounded_"+str(dimension))
        check(ui.fullscreen_playback.get_global_rect().end.y<=card.end.y+2,"metadata_lines_inside_"+str(dimension))
        var output=OS.get_environment("SHIELDAMP_PRESENTATION_IMAGES")
        if not output.empty():
            yield(self,"idle_frame")
            var capture=get_root().get_texture().get_data();capture.flip_y()
            capture.save_png(output+"/fullscreen_"+str(int(dimension.x))+"x"+str(int(dimension.y))+".png")
    route_key(ui,KEY_ESCAPE)
    check(not ui.fullscreen_visual and ui.fullscreen_button.has_focus(),"remote_back_restores_controls_and_focus")
    var original_panel=app.ma_panel
    var original_art=ui.artwork_controller
    original_art.close()
    var secure=FixtureLibrary.new()
    var facade=FixtureFacade.new()
    var art=FixtureArtwork.new();get_root().add_child(art)
    app.ma_panel=secure;app.sendspin_facade=facade;ui.artwork_controller=art
    secure.connect("credential_session_closed",ui,"_art_session_closed")
    ui._artwork_descriptor={"proxy_id":"a".repeat(64)};ui._artwork_context="tv|fictional-current";ui._artwork_binding=""
    ui._sync_art_session();ui._sync_art_session()
    check(secure.reads==1 and art.is_configured() and art.selections==2,"saved_token_origin_bound_once_per_paired_session")
    art._cache["fictional"]=texture
    secure.library_disconnected=true;secure.catalog.epoch+=1;secure.emit_signal("credential_session_closed","forget")
    check(not art.is_configured() and art._cache.empty() and ui._artwork_descriptor.empty(),"forget_signal_immediately_clears_artwork_session")
    ui._sync_art_session()
    check(secure.reads==1 and art.selections==2,"forget_cannot_recover_saved_credential")
    secure.library_disconnected=false;secure.endpoint="https://different-fictional-ma.invalid";secure.catalog.epoch+=1
    ui._artwork_descriptor={"proxy_id":"a".repeat(64)};ui._sync_art_session()
    check(not art.is_configured() and art.selections==2,"changed_origin_never_receives_saved_token")
    secure.endpoint=secure.bound_endpoint;secure.catalog.epoch+=1;ui._artwork_descriptor={"proxy_id":"a".repeat(64)}
    ui._sync_art_session()
    var before_failed_reads=secure.reads
    var before_failed_selections=art.selections
    ui._art_authorization_failed()
    ui._artwork_descriptor={"proxy_id":"b".repeat(64)};ui._sync_art_session()
    check(secure.reads==before_failed_reads and art.selections==before_failed_selections and not art.is_configured(),"artwork_auth_failure_never_autoretries_saved_token")
    app.ma_panel=original_panel;ui.artwork_controller=original_art
    app.sendspin_facade=null;app.analysis_owner=null
    art.queue_free()
    print("PRESENTATION_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
