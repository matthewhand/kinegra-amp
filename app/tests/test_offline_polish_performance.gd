extends SceneTree
# Pure fictional timing/spectrum tests. Existing real original Ogg is only
# started by an explicit test action on Ubuntu's isolated offline Godot host.
# No network, MA, HA, services, Shield, credentials, or synthetic tones.
var checks = 0
var failures = []
func ck(ok, note):
    checks += 1
    if not ok:
        failures.append(note)
        printerr("FAIL ",note)

func _init():
    call_deferred("run")

func run():
    var metrics = load("res://scripts/FramePacingMetrics.gd").new()
    var zero = metrics.snapshot()
    ck(zero["count"] == 0, "no implied frame data at startup")
    ck(zero["fps_estimate"] == 0.0, "unknown FPS accurately zero")
    for value in [-1.0, 0.0, 1.1, NAN, INF, -INF]:
        ck(not metrics.observe(value), "invalid timing fails closed")
    ck(metrics.samples.empty(), "invalid timings cannot mutate window")
    for _i in range(100):
        ck(metrics.observe(0.016), "nominal frame accepted")
    var normal = metrics.snapshot()
    ck(normal["count"] == 100 and abs(normal["mean_ms"] - 16.0)<0.01, "nominal 16ms mean")
    ck(normal["late_ratio"] == 0.0, "no imaginary slow frames")
    ck(normal["fps_estimate"] > 60.0 and normal["fps_estimate"] < 63.0, "bounded FPS estimate")
    for _i in range(20):
        metrics.observe(0.050)
    var slow = metrics.snapshot()
    ck(slow["count"] == 120, "strict window memory bound")
    ck(abs(slow["late_ratio"] - 20.0/120.0)<0.0001, "late frame ratio actual")
    ck(abs(slow["p95_ms"] - 50.0)<0.01, "p95 selects worst tail")
    for _i in range(120):
        metrics.observe(0.01)
    var refreshed = metrics.snapshot()
    ck(refreshed["count"]==120 and refreshed["late_ratio"]==0.0, "rolling eviction removes slow frames")
    ck(abs(refreshed["mean_ms"] - 10.0)<0.05, "running sum stable")
    for _i in range(10000):
        metrics.observe(0.02)
    ck(metrics.samples.size()==120 and metrics.late_frames==0,"10k update stress retains 120 frames")
    metrics.reset()
    ck(metrics.samples.empty() and metrics.snapshot()["count"]==0, "metrics reset clean")

    var env = load("res://scripts/FftEnvelope.gd").new()
    ck(abs(env.sensitivity-1.0)<0.001,"default FFT response unchanged")
    for bad in [-1.0, 0.0, 0.49, 2.01, INF, NAN]:
        ck(not env.set_sensitivity(bad), "invalid visual sensitivity rejected")
    ck(env.sensitivity==1.0, "no partial input corruption")
    var bands = []
    for _i in range(16):
        bands.append(0.04)
    env.reset()
    ck(env.set_sensitivity(0.65), "low sensitivity available")
    var low = env.apply(bands, 0.033)[0]
    env.reset()
    ck(env.set_sensitivity(1.0), "normal sensitivity available")
    var medium = env.apply(bands, 0.033)[0]
    env.reset()
    ck(env.set_sensitivity(1.5), "high sensitivity available")
    var high = env.apply(bands, 0.033)[0]
    ck(low > 0.0 and low < medium and medium < high, "real bands grow monotonically with gain")
    env.reset()
    ck(env.sensitivity==1.5 and env.bands.max()==0.0,"reset retains owner-selected gain but clears previous frames")
    var bad = bands.duplicate()
    bad[10] = NAN
    ck(env.apply(bad, 0.01)==env.bands,"nonfinite spectral frame rejected atomically")

    var tv = load("res://Main.tscn").instance()
    get_root().add_child(tv)
    yield(create_timer(0.25),"timeout")
    ck(tv.offline_music != null and not tv.offline_music.is_playing(),"no audio at app launch")
    ck(tv.music_ui.library_button.has_focus(),"MA-first focus preserved")
    ck(tv.music_ui.artwork != null and tv.music_ui.artwork.texture != null, "real shipped branding art used")
    ck(tv.music_ui.artwork.texture.resource_path == "res://assets/branding/icon_192.png", "no fabricated provider album cover")
    ck(tv.music_ui.artwork_caption.text == "BRAND ART","honest art provenance")
    ck(tv.music_ui.sensitivity_button != null and tv.music_ui.sensitivity_button.focus_mode == Control.FOCUS_ALL,"D-pad sensitive control")
    ck(tv.sensitivity_index==1 and tv.fft_envelope.sensitivity==1.0, "default visual sensitivity")
    tv.music_ui._cycle_sensitivity()
    ck(tv.sensitivity_index==2 and tv.fft_envelope.sensitivity==1.5,"HIGH button configured")
    ck("HIGH" in tv.music_ui.sensitivity_button.text,"remote feedback for high")
    tv.music_ui._cycle_sensitivity()
    ck(tv.sensitivity_index==0 and tv.fft_envelope.sensitivity==0.65,"LOW wraps")
    tv.music_ui._cycle_sensitivity()
    ck(tv.sensitivity_index==1 and tv.fft_envelope.sensitivity==1.0,"NORMAL wraps")
    ck(tv.preset_index==0, "original visual intact")
    ck(tv.music_ui.playback_progress.value==0, "no fabricated progress at idle")
    ck(tv.music_ui.favorite_button.is_connected("pressed",tv.music_ui,"_toggle_favorite"),"remote favorite remains connected")
    tv.offline_music.choose_playlist(1)
    ck(not tv.offline_music.is_playing(), "playlist selection never auto starts")
    ck("MIX: NIGHT" in tv.music_ui.playlist_button.text,"playlist displayed in compact TV control")
    ck(tv.offline_music.duration_seconds()>0, "owner-original Ogg metadata valid")
    # Offline host explicitly starts only the original user-owned audio, as
    # inherited tests already do. No external or generated audio is used.
    ck(tv.offline_music.play(), "original Omega track can start only when asked")
    tv.offline_music.suspend_for_background()
    ck(not tv.offline_music.is_playing(),"loss of focus stops owned audio")
    ck(tv.offline_music.progress_seconds() == 0.0,"stopped playback cannot retain stale time")
    tv.offline_music._notification(MainLoop.NOTIFICATION_APP_RESUMED)
    ck(not tv.offline_music.is_playing(),"return from standby never autoplays")
    tv._stop_all_music()
    ck(tv.offline_music.playlists.playlist_name()=="NIGHT FLIGHT", "in-memory playlist survives harmless Stop")
    ck(tv.ma_panel.catalog.token.empty(),"no MA connection touched")
    ck(tv.native_transport != null and not tv.native_transport.active,"native transport remains idle")
    ck(tv.music_ui.playback_progress.percent_visible==false,"TV progress avoids tiny percent overlay")

    # Layout evidence is only meaningful for landscape Android TV targets.
    for width in [960, 1280, 1920]:
        OS.window_size = Vector2(width,720)
        tv.rect_size = get_root().size
        yield(create_timer(0.10),"timeout")
        var dock = tv.music_ui.root.get_node("NowPlayingDock")
        var option = tv.music_ui.sensitivity_button.get_parent()
        var row_right = option.rect_global_position.x + option.rect_size.x
        var dock_right = dock.rect_global_position.x + dock.rect_size.x
        print("LANDSCAPE_LAYOUT width=",width," row_right=",row_right," dock_right=",dock_right,
            " dock_h=",dock.rect_size.y)
        ck(dock.rect_size.y>275,"TV dock minimum vertical space")
        ck(row_right <= dock_right + 2.0,"secondary control row does not exceed card")
        var last_right = tv.music_ui.sensitivity_button.rect_global_position.x + tv.music_ui.sensitivity_button.rect_size.x
        ck(last_right <= dock_right - 8.0, "right-most focusable control fits in card")
        var progress = tv.music_ui.playback_progress
        var timeline_bottom = progress.rect_global_position.y + progress.rect_size.y
        var dock_bottom = dock.rect_global_position.y + dock.rect_size.y
        ck(timeline_bottom <= dock_bottom - 5.0, "progress timeline vertically contained")
        ck(tv.music_ui.play_button.rect_size.y >= 56,"primary playback has D-pad sized target")
    print("OFFLINE_POLISH_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
