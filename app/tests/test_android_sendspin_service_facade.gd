extends SceneTree
const Adapter = preload("res://scripts/AndroidSendspinServiceFacade.gd")
class Platform:
    extends Reference
    var enabled = false
    var connects = 0
    var reflection_checks = 0
    func has_method(_method):
        reflection_checks += 1
        return false
    var commands = []
    var reply = {"source": "none", "state": "idle"}
    var setting_reply = true
    var settings = []
    var gains = []
    var analysis_requests = []
    var analysis_reply = {}
    func backgroundPlaybackAvailable(): return enabled
    func setBackgroundPlaybackAnalysisEnabled(value):
        analysis_requests.append(value)
        return true
    func backgroundPlaybackAnalysis(): return JSON.print(analysis_reply)
    func setBackgroundPlaybackGain(value):
        gains.append(value)
        return true
    func setKeepPlayingInBackground(value):
        settings.append(value)
        return setting_reply
    func connectBackgroundSendspin(_endpoint):
        connects += 1
        return true
    func backgroundPlaybackSnapshot(): return JSON.print(reply)
    func backgroundPlaybackCommand(name, value):
        commands.append([name, value])
        return true

class MainFixture:
    extends "res://scripts/Main.gd"
    var setting_platform = null
    var route_ready = false
    var resume_commands = []
    func _background_playback_platform():
        return setting_platform
    func _queue_controls_available():
        return route_ready
    func _sendspin_command(command, _argument=null):
        resume_commands.append(command)
        return true

func _init():
    call_deferred("run")

func run():
    var facade = Adapter.new()
    get_root().add_child(facade)
    var platform = Platform.new()
    # Documentation-only private test route; the fake never opens a socket.
    var endpoint = "ws://127.0.0.1:8927/sendspin"
    assert(not facade.start(endpoint, true, platform))
    assert(platform.connects == 0)
    platform.enabled = 1
    assert(not facade.start(endpoint, true, platform))
    platform.enabled = true
    assert(not facade.start(endpoint, false, platform))
    assert(platform.connects == 0)
    assert(facade.start(endpoint, true, platform))
    assert(not facade.start(endpoint, true, platform) and platform.connects == 1)
    assert(platform.reflection_checks == 0)
    assert(not platform.has_method("backgroundPlaybackAvailable") and platform.reflection_checks == 1)
    facade.refresh()
    assert(facade.active and facade.state == "connecting")
    assert(not facade.command("permit"))
    platform.reply = {"source": "ma", "state": "connecting", "pairing_code": "012345"}
    facade.refresh()
    assert(facade.confirm_pairing() and platform.commands.back() == ["confirm", 0])
    platform.reply = {"source": "ma", "state": "buffering", "paired": true, "client_id": "fake-client", "generation": 4, "queued_ms": 400}
    facade.refresh()
    assert(facade.client.status().client_id == "fake-client")
    assert(facade.buffering and facade.queued_audio_snapshot().empty() and facade.command("permit"))
    platform.reply.state = "playing"
    platform.reply.stream_active = true
    platform.reply.underruns = 2
    platform.reply.rebuffers = 1
    facade.refresh()
    assert(facade.state == "receiving" and facade.queued_audio_snapshot().queued_ms == 400)
    var buffers = facade.buffer_stats(OS.get_ticks_msec())
    assert(buffers.active and buffers.queued_ms == 400 and buffers.generation == 4)
    assert(buffers.underruns == 2 and buffers.rebuffers == 1 and not buffers.buffering)
    assert(facade.buffer_stats(OS.get_ticks_msec()+1000).empty())
    facade.set_analysis_enabled(true)
    assert(platform.analysis_requests == [true])
    var bands = []
    bands.resize(16)
    for i in range(bands.size()):
        bands[i] = 0.04 * i
    platform.analysis_reply = {"generation": 4, "age_ms": 0, "playback_ms": 530.1, "rms": 0.1, "bands": bands}
    facade._read_analysis()
    var sample = facade.analysis_sample(OS.get_ticks_msec())
    assert(sample.bands.size() == 16 and is_equal_approx(sample.rms, 0.1))
    assert(facade.analysis_sample(OS.get_ticks_msec()+1000).empty())
    platform.analysis_reply.generation = 3
    facade._read_analysis()
    assert(facade.analysis_sample(OS.get_ticks_msec()).empty())
    platform.analysis_reply.generation = 4
    platform.analysis_reply.age_ms = 600
    facade._read_analysis()
    assert(facade.analysis_sample(OS.get_ticks_msec()).empty())
    facade.set_analysis_enabled(false)
    assert(platform.analysis_requests == [true,false])
    facade.invalidate_buffer_measurement()
    assert(facade.queued_audio_snapshot().empty())
    platform.reply.source = "local"
    facade.refresh()
    assert(not facade.active and facade.status().empty())
    facade.stop()
    assert(facade.state == "idle" and platform.commands.back() == ["permit", 0])
    var app = MainFixture.new()
    get_root().add_child(app)
    yield(create_timer(0.1), "timeout")
    app.set_process(false)
    var service = Adapter.new()
    var service_platform = Platform.new()
    service_platform.enabled = true
    app.add_child(service)
    assert(service.start(endpoint, true, service_platform))
    app.setting_platform = service_platform
    assert(app.set_app_volume(0) and service_platform.gains.back() == 0)
    assert(app.set_app_volume(44) and service_platform.gains.back() == 44)
    assert(service_platform.reflection_checks == 0)
    app.background_playback_toggle = CheckBox.new()
    app.add_child(app.background_playback_toggle)
    assert(app._set_keep_playing_in_background(false))
    assert(service_platform.settings.back() == false and not app.keep_playing_in_background)
    for bad_reply in [false, 1]:
        service_platform.setting_reply = bad_reply
        app.background_playback_toggle.set_pressed_no_signal(true)
        assert(not app._set_keep_playing_in_background(true))
        assert(not app.keep_playing_in_background and not app.background_playback_toggle.pressed)
    service_platform.setting_reply = true
    assert(app._set_keep_playing_in_background(true))
    assert(app.keep_playing_in_background)

    app.sendspin_facade = service
    app.ma_panel.endpoint_edit.text = "https://music.example"
    app.ma_panel.sendspin_endpoint.text = endpoint
    app.ma_panel.library_disconnected = false
    var request = {"epoch": app.ma_panel.catalog.epoch, "origin": app.ma_panel._credential_endpoint(),
        "deadline": OS.get_ticks_msec()+10000, "facade": service, "endpoint": endpoint,
        "client": "", "wait_for_android_identity": true, "recovery": false}
    app.pending_queue_resume = request.duplicate()
    app._continue_queue_resume()
    assert(not app.pending_queue_resume.empty() and app.resume_commands.empty())
    service_platform.reply = {"source": "ma", "state": "paired", "paired": true, "client_id": "fake-client"}
    service.refresh()
    app.ma_panel.set_sendspin_status("paired", "Synthetic ready", "fake-client")
    app._continue_queue_resume()
    assert(app.pending_queue_resume.get("client") == "fake-client" and app.resume_commands.empty())

    # A different authenticated ID cannot consume a pinned intent.
    service_platform.reply.client_id = "other-client"
    service.refresh()
    app.ma_panel.set_sendspin_status("paired", "Synthetic different player", "other-client")
    app._continue_queue_resume()
    assert(app.pending_queue_resume.empty() and app.resume_commands.empty())

    service_platform.reply.client_id = "fake-client"
    service.refresh()
    app.ma_panel.set_sendspin_status("paired", "Synthetic ready", "fake-client")
    app.pending_queue_resume = request.duplicate()
    app.route_ready = true
    app._continue_queue_resume()
    app._continue_queue_resume()
    assert(app.pending_queue_resume.empty() and app.resume_commands == ["play"])
    service_platform.reply = {"source": "ma", "state": "playing", "paired": true, "client_id": "fake-client"}
    service.refresh()
    app.sendspin_facade = service
    for keep in [true, false]:
        app.keep_playing_in_background = keep
        app._notification(MainLoop.NOTIFICATION_APP_PAUSED)
        app.ma_panel._notification(MainLoop.NOTIFICATION_APP_PAUSED)
        assert(app.sendspin_facade == service and service.active and service_platform.commands.empty())
        app._notification(MainLoop.NOTIFICATION_APP_RESUMED)
    service_platform.analysis_reply = {"generation": 3, "age_ms": 0, "playback_ms": 530.1,
        "rms": 0.1, "bands": bands}
    service_platform.reply.generation = 3
    service_platform.reply.queued_ms = 452
    service.refresh()
    service.set_analysis_enabled(true)
    service._read_analysis()
    app.visual_quality_level = 2
    app._update_visuals(0.016)
    var frame = app.analysis_frame.snapshot(OS.get_ticks_msec())
    assert(frame.source == "live_pcm" and frame.bands[10] > 0.1 and frame.playback_ms > 530.0)
    app._on_library_credentials_closed("disconnect")
    assert(app.sendspin_facade == null and not service.active and service_platform.commands.back() == ["stop", 0])
    app.queue_free()
    print("AMP_ANDROID_SENDSPIN_FACADE_PASS")
    quit()
