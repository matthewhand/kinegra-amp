extends SceneTree
class BufferRuntime:
    extends Reference
    var active=true
    var buffering=true
class BufferFacade:
    extends Node
    var runtime=BufferRuntime.new()
var failures=[]
var checks=0
func check(ok,label):
    checks+=1;print("HERO_BUDGET_COPY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    AudioServer.set_bus_mute(0,true)
    var app=load("res://Main.tscn").instance();app.set_script(load("res://tests/FakePresentationMain.gd"));get_root().add_child(app)
    yield(create_timer(.25),"timeout")
    app.set_process(false);var ui=app.music_ui;ui.set_process(false)
    app.visual_governor.set_mode("full",OS.get_ticks_msec());app._apply_visual_budget(app.visual_governor.snapshot())
    app._play_offline_music();ui._process(.01)
    check(ui.track_hero.playing and "REAL AUDIO ANALYSIS" in ui.track_hero.state_label.text,"full_local_playback_keeps_existing_analysis_copy")
    var cover=ui.track_hero.cover
    app.set_visuals_enabled(false);ui._process(.01)
    check(ui.track_hero.playing and ui.track_hero.state_label.text=="PLAYING / VISUALS OFF" and ui.track_hero.render_budget_fps==0,"owner_off_reports_playing_without_analysis_claim")
    check(ui.status_label.text=="PLAYING  •  LOCAL AUDIO","local_status_does_not_claim_fft_when_visuals_off")
    check(not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Milkdrop"),0) and ui.track_hero.cover==cover,"off_copy_matches_fft_budget_and_preserves_cover")
    var image_path=OS.get_environment("SHIELDAMP_HERO_OFF_IMAGE")
    if not image_path.empty():
        yield(self,"idle_frame")
        var image=get_root().get_texture().get_data();image.flip_y();image.save_png(image_path)
    app.offline_music.stop();ui._process(.01)
    check(not ui.track_hero.playing and not "PLAYING /" in ui.track_hero.state_label.text,"paused_local_is_not_relabelled_playing")
    app.visual_governor.set_mode("audio_first",OS.get_ticks_msec());app.set_visuals_enabled(true);app._apply_visual_budget(app.visual_governor.snapshot())
    app._play_offline_music();yield(create_timer(.08),"timeout");ui._process(.01)
    check(ui.track_hero.playing and ui.track_hero.state_label.text=="PLAYING / AUDIO FIRST" and app.visuals_enabled and app.visual_quality_level==0,"governor_audio_first_reports_actual_budget_reason")
    app.offline_music.stop();ui.set_playback_context("catalog");ui._process(.01)
    check(not ui.track_hero.playing and "NO PLAYBACK" in ui.track_hero.state_label.text,"catalog_selection_preserves_no_playback")
    ui.set_playback_context("preview");app.native_transport.ma_preview_mode=true;app.native_stream_engine.active=true;app.analysis_owner=app.native_stream_engine;app.native_stream_engine.last_pcm_at=OS.get_ticks_msec();ui._process(.01)
    check(ui.track_hero.playing and ui.track_hero.state_label.text=="PLAYING / AUDIO FIRST","fresh_preview_at_zero_budget_uses_truthful_copy")
    app.native_stream_engine.last_pcm_at=OS.get_ticks_msec()-501;ui._process(.01)
    check(not ui.track_hero.playing and "WAITING" in ui.track_hero.state_label.text,"stale_preview_preserves_waiting")
    app.native_stream_engine.active=false;app.native_transport.ma_preview_mode=false;app.analysis_owner=null
    ui.set_playback_context("ma");app.fixture_fresh=true;ui._process(.01)
    check(ui.track_hero.playing and ui.track_hero.state_label.text=="PLAYING / AUDIO FIRST","fresh_own_tv_audio_at_zero_budget_uses_truthful_copy")
    app.fixture_fresh=false;ui._process(.01)
    check(not ui.track_hero.playing and "WAITING" in ui.track_hero.state_label.text,"unknown_tv_audio_preserves_waiting")
    app.tv_queue_last_action="pause";app.tv_queue_state="idle";ui._process(.01)
    check(not ui.track_hero.playing and "PAUSE REQUESTED" in ui.track_hero.state_label.text,"paused_tv_state_is_preserved")
    app.tv_queue_last_action="";var facade=BufferFacade.new();app.add_child(facade);app.sendspin_facade=facade;app.fixture_fresh=true;ui._process(.01)
    check(not ui.track_hero.playing and ui.track_hero.state_label.text=="BUFFERING AUDIO…","buffering_wins_over_zero_budget_playing_copy")
    app.sendspin_facade=null;facade.queue_free();app.fixture_fresh=false
    app.queue_free();print("HERO_BUDGET_COPY_CHECKS=",checks," FAILURES=",failures.size());quit(0 if failures.empty() else 1)
