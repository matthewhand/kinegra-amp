extends Control
# Kinegra Amp audiovisual interface; no embedded Chromium.
var api = null
var stream_engine = null
var native_stream_engine = null
var native_transport = null
var analysis_owner = null
var sendspin_facade = null
var tv_queue_request = null
var tv_queue_pending_session = null
var _library_session_token=""
var _library_session_origin=""
var _library_origin_policy=preload("res://scripts/ConnectionPolicy.gd").new()
var playback_detail=""
var web_require_key=null
var web_trusted_ranges=null
var web_remote=null
var web_remote_toggle=null
var web_remote_status=null
var web_remote_new_key=null
var app_volume_db=0.0
var volume_path="user://shieldamp_player_gain.cfg"
var app_volume_percent=100
var app_volume_slider=null
var app_volume_label=null
var volume_store=preload("res://scripts/VolumeStore.gd").new()
var volume_timer=null
var volume_dirty=false
var volume_save_ok=true
var volume_load_blocked=false
var pose_suspended_mode = ""
var app_has_focus = true
var app_is_paused = false
var tv_queue_timer = null
var tv_reconnect_timer = null
var tv_audio_wait_timer = null
var tv_reconnect_waiting = false
var tv_audio_requested = false
var tv_audio_since = -1
var tv_previous_generation = -1
var tv_playback_error = ""
var tv_queue_last_action = ""
var tv_queue_state = ""
var tv_queue_timing={}
var tv_queue_timing_read_at=-1
var tv_queue_policy=preload("res://scripts/MAQueuePolicy.gd").new()
var analysis_frame = preload("res://scripts/AnalysisFrame.gd").new()
var analysis_epoch = 0
var analysis_label = null
var reduced_motion = null
var codec_choice = null
var metronome_bpm = null
var command_grid = null
var page_scroller = null
var screen_base = Vector2()
var large_text = null
var accessibility_font = null
var ma_panel = null
var ma_button = null
var offline_music = null
var offline_save=null
var offline_source_edit=null
var offline_source_key_edit=null
var offline_source_status=null
var local_pcm = null
var music_ui = null
signal analysis_updated(frame)
var spectrum = null
var visual = null
var shader_material = null
var pose_visual = null
var avatar_visual = null
var backing_avatars = []
var backing_dancers = null
var webcam_gestures=null
var gesture_choices={}
var gesture_status=null
var gesture_mode="panel"
var gesture_mode_choice=null
var gesture_mode_labels=[]
var body_control_policy=preload("res://scripts/BodyControlPanelPolicy.gd").new()
var body_control_panel=null
var gesture_feedback_presenter=preload("res://scripts/StatusStability.gd").new()
var gesture_policy=preload("res://scripts/WebcamGesturePolicy.gd").new()
var _gesture_ui_elapsed=0.0
var backing_cast=[]
var backup_tempo=preload("res://scripts/TempoTracker.gd").new()
var backup_choreography=preload("res://scripts/BackupChoreography.gd").new()
var device_info_label = null
var device_refresh_button = null
var support_status_label = null
const SUPPORT_PROFILE = "https://github.com/matthewhand"
var title_label = null
var state_label = null
var detail_label = null
var token_edit = null
var ha_endpoint_edit = null
var stream_origin_edit = null
var transport_trust = null
var entity_edit = null
var url_edit = null
var progress = null
var fft = []
var fft_envelope = preload("res://scripts/FftEnvelope.gd").new()
const VISUAL_PRESETS = ["HORIZON GRID", "NEBULA FLOW", "STARFIELD"]
var preset_index = 0
const SENSITIVITY_LEVELS = [0.65, 1.0, 1.5]
const SENSITIVITY_LABELS = ["LOW", "NORMAL", "HIGH"]
var sensitivity_index = 1
var music_reactivity_choice=null
var frame_metrics = preload("res://scripts/FramePacingMetrics.gd").new()
var visual_governor = preload("res://scripts/AdaptiveVisuals.gd").new()
var visual_quality_choice = null
var visual_quality_status = null
var light_shader_material = null
var visuals_enabled = true
var visual_quality_level = -1
var pending_queue_resume={}
var playback_recovery=preload("res://scripts/PlaybackRecovery.gd").new()
var recovery_restarting=false
var recovery_client_id=""
var restoring_ma_session=false
var stream_warmup_budget = preload("res://scripts/StreamWarmupBudget.gd").new()
var visual_update_elapsed = 0.0
var headroom_elapsed = 0.0
var app_cpu_percent = -1.0
var thermal_status = -1
var cpu_sample_at = -1
var cpu_sample_value = -1
var display_refresh_hz = 60.0
var spectrum_budget_saved = null
var elapsed = 0.0
var live_audio = false
var demo = true
var frame_sample_seconds = 0.0
var frame_sample_count = 0

func _ready():
	# Android Back is handled by the topmost UI surface, never SceneTree auto-quit.
	get_tree().set_quit_on_go_back(false)
	preload("res://scripts/UIControllerBindings.gd").apply()
	tv_queue_timer=Timer.new()
	tv_queue_timer.wait_time=15.0
	add_child(tv_queue_timer)
	tv_queue_timer.connect("timeout",self,"_refresh_tv_queue")
	tv_reconnect_timer=Timer.new()
	tv_reconnect_timer.one_shot=true
	add_child(tv_reconnect_timer)
	tv_reconnect_timer.connect("timeout",self,"_on_tv_reconnect_timeout")
	tv_audio_wait_timer=Timer.new()
	tv_audio_wait_timer.one_shot=true
	add_child(tv_audio_wait_timer)
	tv_audio_wait_timer.connect("timeout",self,"_on_tv_audio_wait_timeout")
	get_tree().set_quit_on_go_back(false)
	_apply_resolution_base()
	api = get_node("/root/HAApi")
	api.connect("connectivity", self, "_on_connectivity")
	api.connect("track_changed", self, "_on_track")
	api.connect("command_result", self, "_on_command")
	_build_audio_bus()
	_restore_app_volume()
	offline_save=preload("res://scripts/OfflineQueueSave.gd").new()
	offline_save.app=self
	add_child(offline_save)
	_build_ui()
	ma_panel.connect("credential_session_closed",self,"_on_library_credentials_closed")
	ma_panel.connect("credential_session_authorized",self,"_on_library_credentials_authorized")
	ma_panel.session_credential_provider=self
	# Private Omega Prime music and the Music Assistant-first TV stage.
	# Neither source autoplays; built-in synthetic audio is never started.
	offline_music = load("res://scripts/OfflineMusic.gd").new()
	add_child(offline_music)
	offline_music.set_volume(app_volume_db)
	offline_music.connect("track_changed", self, "_on_offline_track")
	offline_music.connect("music_state_changed", self, "_on_offline_state")
	# Explicit local-only PCM16 -> speaker/FFT capability, never autoplay.
	local_pcm = load("res://scripts/LocalPcmPlayer.gd").new()
	add_child(local_pcm)
	music_ui = load("res://scripts/MusicFirstUI.gd").new()
	add_child(music_ui)
	body_control_panel=load("res://scripts/BodyControlPanel3D.gd").new()
	body_control_panel.app=self
	add_child(body_control_panel)
	# Reflect the already-selected bundled track without starting playback.
	music_ui.show_offline_track(offline_music.current_title(), false)
	music_ui.restore_startup_context()
	# The legacy Settings accessibility toggle also governs the music stage.
	music_ui.set_tv_text_mode(large_text != null and large_text.pressed)
	page_scroller.hide()
	stream_engine = load("res://scripts/StreamPlayer.gd").new()
	add_child(stream_engine)
	stream_engine.connect("message", self, "_on_stream_message")
	stream_engine.connect("playing", self, "_on_stream_active")
	stream_engine.connect("pcm_observed", self, "_on_pcm_observed", [stream_engine])
	native_stream_engine = load("res://scripts/NativeDecoderPlayer.gd").new()
	add_child(native_stream_engine)
	native_stream_engine.connect("message", self, "_on_stream_message")
	native_stream_engine.connect("playing", self, "_on_stream_active")
	native_stream_engine.connect("pcm_observed", self, "_on_pcm_observed", [native_stream_engine])
	native_transport = load("res://scripts/NativeHTTPTransport.gd").new()
	add_child(native_transport)
	native_transport.connect("message", self, "_on_stream_message")
	for i in range(16):
		fft.append(0.0)
	# Shipping music-first UI has no automatic or debug-marker test-tone hook.
	# Physical synthetic G3 decoding acceptance was completed with signed v0.4.
	demo = false
	display_refresh_hz=OS.get_screen_refresh_rate()
	if display_refresh_hz<24.0 or display_refresh_hz>240.0: display_refresh_hz=60.0
	_apply_visual_budget(visual_governor.snapshot())
	_update_layout()
	_start_web_remote()
	set_process(true)

func _clear_library_session():
	_library_session_token=""
	_library_session_origin=""
func _valid_library_credential(value):
	if typeof(value)!=TYPE_STRING or value.length()<10 or value.length()>8192:return false
	for index in range(value.length()):
		if value.ord_at(index)<33 or value.ord_at(index)>126:return false
	return true
func _on_library_credentials_authorized(credential,origin):
	_clear_library_session()
	if ma_panel==null or ma_panel.library_disconnected or not _valid_library_credential(credential):return
	var requested=ma_panel._credential_endpoint()
	var catalog=ma_panel.catalog
	var parsed=_library_origin_policy.origin(catalog.endpoint,["https","http"],ma_panel.lan_trust.pressed)
	if requested.empty() or origin!=requested or parsed.empty() or str(parsed.prefix).to_lower()!=requested or catalog.token!=credential:return
	_library_session_origin=requested
	_library_session_token=credential # RAM only; never writes the vault/settings.
	if restoring_ma_session:call_deferred("_restore_paired_output")
func _restore_music_assistant_session():
	if music_ui==null or music_ui.playback_context!="ma" or ma_panel==null:return
	restoring_ma_session=true
	ma_panel.connect_saved_if_needed()

func _restore_paired_output():
	if not restoring_ma_session or ma_panel==null or ma_panel.library_disconnected or _library_credential(false).empty():return
	restoring_ma_session=false
	var saved=ConfigFile.new()
	if saved.load(ma_panel.settings_path)!=OK:return
	var address=ma_panel.sendspin_endpoint.text.strip_edges()
	if address.empty() or str(saved.get_value("sendspin","paired_endpoint_hash",""))!=address.sha256_text():return
	# Reconnect the saved identity only to read this client's authoritative queue.
	# Loading the app never issues a Play command or rewrites that queue.
	ma_panel._sendspin_start()

func cancel_pending_resume():
	pending_queue_resume.clear()

func _cancel_requested_play(cancel_recovery=true):
	if cancel_recovery:playback_recovery.cancel()
	var pending=not pending_queue_resume.empty() or (ma_panel!=null and not ma_panel.connect_play_item.empty())
	cancel_pending_resume()
	if ma_panel!=null:ma_panel.cancel_pending_play()
	if pending:
		stream_warmup_budget.reset()
		_reset_tv_audio()

func _play_music_assistant():
	if music_ui==null or ma_panel==null:return false
	music_ui.set_playback_context("ma")
	if not pending_queue_resume.empty():return true
	if _library_credential().empty():
		music_ui._open_library()
		if _library_credential(false).empty():
			ma_panel.emit_signal("configuration_requested","library")
			music_ui.show_status("CONNECT YOUR MUSIC LIBRARY")
			return false
	if not _sendspin_controls().empty() and ma_panel.sendspin_paired:
		return _sendspin_command("play")
	pending_queue_resume={"epoch":ma_panel.catalog.epoch,"origin":ma_panel._credential_endpoint(),"deadline":OS.get_ticks_msec()+150000,"recovery":recovery_restarting}
	_prepare_stream_visuals()
	music_ui.show_status("PREPARING PLAYBACK…")
	if not ma_panel._sendspin_start() or ma_panel.playback_state=="error":
		_cancel_requested_play()
		ma_panel.emit_signal("configuration_requested","playback")
		return false
	_watch_tv_audio(false,false)
	pending_queue_resume["client"]=ma_panel._playback_client_id()
	pending_queue_resume["facade"]=sendspin_facade
	pending_queue_resume["endpoint"]=ma_panel.sendspin_endpoint.text.strip_edges()
	return true

func _continue_queue_resume():
	if pending_queue_resume.empty():return
	if ma_panel==null or ma_panel.library_disconnected or OS.get_ticks_msec()>=pending_queue_resume.deadline or ma_panel.catalog.epoch!=pending_queue_resume.epoch or ma_panel._credential_endpoint()!=pending_queue_resume.origin:
		_cancel_requested_play()
		return
	if pending_queue_resume.get("facade")!=sendspin_facade or pending_queue_resume.get("client","").empty() or pending_queue_resume.get("client")!=ma_panel._playback_client_id() or pending_queue_resume.get("endpoint")!=ma_panel.sendspin_endpoint.text.strip_edges():
		_cancel_requested_play()
		return
	# The queue operation fetches and verifies the exact route itself. The
	# drawer may be closed, with an empty or expired player list.
	if not _queue_controls_available():return
	# An asynchronous recovery resume keeps the current retry budget.
	recovery_restarting=pending_queue_resume.recovery
	pending_queue_resume.clear()
	var started=_sendspin_command("play")
	recovery_restarting=false
	if started:
		music_ui._close_library()
		music_ui.play_button.grab_focus()

func _library_credential(include_saved=true):
	if ma_panel==null or ma_panel.library_disconnected:
		_clear_library_session()
		return ""
	var requested=ma_panel._credential_endpoint()
	if requested.empty():
		_clear_library_session()
		return ""
	if _library_session_origin!=requested:_clear_library_session()
	var catalog=ma_panel.catalog
	var parsed=_library_origin_policy.origin(catalog.endpoint,["https","http"],ma_panel.lan_trust.pressed) if not catalog.endpoint.empty() else {}
	if not parsed.empty() and str(parsed.prefix).to_lower()==requested and _valid_library_credential(catalog.token):return catalog.token
	if _library_session_origin==requested and _valid_library_credential(_library_session_token):return _library_session_token
	if not include_saved:return ""
	var saved=ma_panel._read_provisioned_token()
	return saved if _valid_library_credential(saved) else ""
func _on_library_credentials_closed(reason):
	if not reason in ["library_closed","focus_lost"]:_cancel_requested_play()
	# Drawer/focus loss is not revoking authenticated origin-bound RAM access.
	# The catalog/artwork listeners still discard their own copied credentials.
	if reason in ["library_closed","focus_lost"]:return
	if reason!="inactive":_clear_library_session()
	var pending_write=tv_queue_request!=null and is_instance_valid(tv_queue_request) and not tv_queue_request.get("action") in ["read","items"]
	var owned=sendspin_facade!=null and is_instance_valid(sendspin_facade) and sendspin_facade.sink!=null and analysis_owner==sendspin_facade.sink
	_close_sendspin_analysis()
	if owned:
		analysis_owner=null
		live_audio=false
		_reset_analysis()
	if music_ui!=null:
		music_ui.show_status("LIBRARY DISCONNECTED / A PENDING COMMAND MAY HAVE COMPLETED" if pending_write else "LIBRARY DISCONNECTED / CONNECT LIBRARY TO CONTINUE")

func _build_audio_bus():
	var idx=AudioServer.get_bus_index("Milkdrop")
	if idx>=0:
		for effect_index in range(AudioServer.get_bus_effect_count(idx)):
			if AudioServer.get_bus_effect(idx,effect_index) is AudioEffectSpectrumAnalyzer:
				spectrum=AudioServer.get_bus_effect_instance(idx,effect_index)
				return
	# Godot 3.6.3 servers/audio_server.cpp::add_bus mutates the live bus
	# vector without taking the driver lock. The Dummy/native audio worker
	# can retain its freed storage during startup. Assemble a detached layout
	# and publish through set_bus_layout, which holds the audio lock.
	var layout=AudioServer.generate_bus_layout()
	var effect_index=0
	if idx<0:
		idx=AudioServer.get_bus_count()
		layout.set("bus/%d/name" % idx,"Milkdrop")
		layout.set("bus/%d/send" % idx,"Master")
	else:
		effect_index=AudioServer.get_bus_effect_count(idx)
	var analyzer=AudioEffectSpectrumAnalyzer.new()
	analyzer.buffer_length=0.20
	analyzer.fft_size=AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	layout.set("bus/%d/effect/%d/effect" % [idx,effect_index],analyzer)
	layout.set("bus/%d/effect/%d/enabled" % [idx,effect_index],true)
	AudioServer.set_bus_layout(layout)
	spectrum=AudioServer.get_bus_effect_instance(idx,effect_index)

func _restore_app_volume():
	var saved=volume_store.read(volume_path)
	volume_load_blocked=not saved.ok
	app_volume_db=saved.db if saved.ok and saved.found else 0.0
	app_volume_percent=int(round(db2linear(app_volume_db)*100.0))
	_apply_app_gain()
	volume_timer=Timer.new()
	volume_timer.one_shot=true
	volume_timer.wait_time=0.35
	add_child(volume_timer)
	volume_timer.connect("timeout",self,"_flush_app_volume")

func _apply_app_gain():
	var bus=AudioServer.get_bus_index("Milkdrop")
	if bus<0:return
	AudioServer.set_bus_volume_db(bus,app_volume_db)
	AudioServer.set_bus_mute(bus,app_volume_percent==0)

func set_app_volume(value):
	if not typeof(value) in [TYPE_INT,TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)):return false
	app_volume_percent=int(clamp(round(float(value)),0.0,100.0))
	app_volume_db=-60.0 if app_volume_percent==0 else max(-60.0,linear2db(float(app_volume_percent)/100.0))
	_apply_app_gain()
	volume_dirty=true
	if volume_timer!=null:volume_timer.start()
	_sync_app_volume_label()
	if music_ui!=null:music_ui.sync_app_volume()
	return true

func _sync_app_volume_label():
	if app_volume_label!=null:app_volume_label.text="APP VOLUME: %d%%%s" % [app_volume_percent," / NOT SAVED" if not volume_save_ok else ""]

func _flush_app_volume():
	if not volume_dirty:return
	volume_save_ok=not volume_load_blocked and volume_store.write(volume_path,app_volume_db)
	if volume_save_ok:volume_dirty=false
	_sync_app_volume_label()
	if music_ui!=null and is_instance_valid(music_ui):music_ui.sync_app_volume()

func _exit_tree():
	print("SHIELDAMP_LIFECYCLE event=exit_begin")
	if web_remote!=null:web_remote._stop()
	_clear_library_session()
	_flush_app_volume()

func _label(parent, text, font_size=16):
	var n = Label.new()
	n.text = text
	n.autowrap = true
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.add_color_override("font_color", Color(0.51, 1.0, 0.67))
	parent.add_child(n)
	return n

func _button(parent, text, method):
	var b = Button.new()
	b.text = text
	b.clip_text = true
	b.hint_tooltip = text
	b.rect_min_size = Vector2(126, 54)
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	b.connect("pressed", self, method)
	return b

func _edit(parent, placeholder, secret=false):
	var e = LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.rect_min_size = Vector2(160, 49)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e

func _build_ui():
	visual = ColorRect.new()
	visual.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shader_material = ShaderMaterial.new()
	shader_material.shader = load("res://shaders/milkdrop.shader")
	light_shader_material=ShaderMaterial.new()
	light_shader_material.shader=load("res://shaders/adaptive_background.shader")
	visual.material = shader_material
	var original = load("res://scripts/OriginalHorizon.gd").load_texture()
	if original != null:
		shader_material.set_shader_param("original_backdrop", original)
		shader_material.set_shader_param("has_backdrop", true)
	add_child(visual)
	pose_visual=load("res://scripts/PoseVisual.gd").new()
	pose_visual.name="PoseVisual"
	add_child(pose_visual)
	pose_visual.connect("gesture_sample",self,"_on_gesture_sample")
	pose_visual.connect("gesture_tracking_lost",self,"_on_gesture_tracking_lost")
	avatar_visual=load("res://scripts/AvatarRenderer.gd").new()
	add_child(avatar_visual)
	avatar_visual.connect("appearance_changed",self,"_recast_backups")
	avatar_visual.set_active(true)
	for slot in [-1, 1]:
		var performer=load("res://scripts/AvatarRenderer.gd").new()
		performer.render_size=256
		performer.stage_slot=slot
		performer.grouped=true
		add_child(performer)
		performer.set_style("starlight" if slot<0 else "synth")
		performer.set_active(false)
		backing_avatars.append(performer)
	_recast_backups()
	pose_visual.draw_skeleton=false
	var layer = CanvasLayer.new()
	add_child(layer)
	page_scroller = ScrollContainer.new()
	page_scroller.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	page_scroller.follow_focus = true
	page_scroller.scroll_horizontal_enabled = false
	layer.add_child(page_scroller)
	var margins = MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margins.add_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margins.add_constant_override("margin_" + side, 12)
	page_scroller.add_child(margins)
	var shell = VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accessible_theme = Theme.new()
	accessibility_font = DynamicFont.new()
	accessibility_font.font_data = load("res://assets/fonts/DejaVuSans.ttf")
	accessibility_font.size = 20
	accessible_theme.default_font = accessibility_font
	shell.theme = accessible_theme
	margins.add_child(shell)
	var header = PanelContainer.new()
	shell.add_child(header)
	var stack = VBoxContainer.new()
	header.add_child(stack)
	_button(stack, "BACK TO MUSIC VISUALIZER", "_show_music_stage")
	_label(stack, "ADVANCED SETTINGS  •  MUSIC ASSISTANT FIRST")
	_build_web_remote_settings(stack)
	_build_offline_source_settings(stack)
	app_volume_label=_label(stack, "")
	app_volume_slider=HSlider.new()
	app_volume_slider.min_value=0
	app_volume_slider.max_value=100
	app_volume_slider.step=5
	app_volume_slider.rect_min_size=Vector2(240,52)
	app_volume_slider.value=app_volume_percent
	app_volume_slider.hint_tooltip="Volume inside Kinegra Amp. 100% is full level; TV/system volume stays separate."
	stack.add_child(app_volume_slider)
	app_volume_slider.connect("value_changed",self,"set_app_volume")
	_sync_app_volume_label()
	title_label = _label(stack, "  No music loaded")
	state_label = _label(stack, "  Music Assistant available; Home Assistant optional")
	var command_row = GridContainer.new()
	command_row.columns = 4
	command_grid = command_row
	stack.add_child(command_row)
	_button(command_row, "|<<", "_previous")
	_button(command_row, "PLAY / PAUSE", "_toggle")
	_button(command_row, ">>|", "_next")
	_button(command_row, "DEMO / LIVE", "_switch_demo")
	analysis_label = _label(stack, "IDLE • awaiting real music")
	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	stack.add_child(progress)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(spacer)
	var scroller = ScrollContainer.new()
	scroller.rect_min_size = Vector2(0, 270)
	scroller.scroll_horizontal_enabled = false
	scroller.follow_focus = true
	shell.add_child(scroller)
	var settings = PanelContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(settings)
	var settings_box = VBoxContainer.new()
	settings.add_child(settings_box)
	_label(settings_box, "ABOUT / DEVICE AND CONTROLS")
	device_info_label = _label(settings_box, "Reading device information...")
	device_refresh_button = _button(settings_box, "REFRESH DEVICE INFO", "_refresh_device_info")
	_label(settings_box, "TV remotes are often reported as keyboards; their presence is not reliably available to this app.")
	_label(settings_box, "Feedback, updates and optional support: the GitHub profile opens in a browser. The issue tracker is private.")
	_button(settings_box, "GITHUB PROFILE - FEEDBACK", "_open_support_profile")
	_button(settings_box, "GITHUB PROFILE - UPDATES", "_open_support_profile")
	_button(settings_box, "GITHUB PROFILE - SUPPORT", "_open_support_profile")
	support_status_label = _label(settings_box, "")
	_refresh_device_info()
	if not Input.is_connected("joy_connection_changed", self, "_joy_changed"):
		Input.connect("joy_connection_changed", self, "_joy_changed")
	var addr_row = VBoxContainer.new()
	settings_box.add_child(addr_row)
	backing_dancers = CheckBox.new()
	backing_dancers.text = "Backing dancers"
	backing_dancers.hint_tooltip = "Add two synthetic backing dancers. Save Setup remembers this choice."
	backing_dancers.rect_min_size.y = 52
	addr_row.add_child(backing_dancers)
	backing_dancers.connect("toggled", self, "_set_backing_dancers")
	_label(addr_row,"Add two synthetic backing dancers. Save Setup remembers this choice.")
	_build_gesture_settings(addr_row)
	_label(addr_row,"Visual quality")
	visual_quality_choice=OptionButton.new()
	visual_quality_choice.clip_text=true
	for label in ["Adaptive (protect playback)","Full visuals","Light visuals","Audio first"]: visual_quality_choice.add_item(label)
	visual_quality_choice.rect_min_size.y=52
	visual_quality_choice.hint_tooltip=visual_quality_choice.get_item_text(visual_quality_choice.selected)
	addr_row.add_child(visual_quality_choice)
	visual_quality_choice.connect("item_selected",self,"_select_visual_quality")
	visual_quality_status=_label(addr_row,"Adaptive visuals: measuring frame and audio pressure")
	_label(addr_row,"Adaptive reduces dancers and effects under load, then restores them gradually. CPU is this app only; GPU idle capacity is not measured. Save Setup remembers the selected mode.")
	_label(addr_row,"Music reactivity")
	music_reactivity_choice=OptionButton.new()
	music_reactivity_choice.clip_text=true
	for label in SENSITIVITY_LABELS:music_reactivity_choice.add_item(label.capitalize())
	music_reactivity_choice.select(sensitivity_index)
	music_reactivity_choice.rect_min_size.y=52
	music_reactivity_choice.hint_tooltip=music_reactivity_choice.get_item_text(music_reactivity_choice.selected)
	addr_row.add_child(music_reactivity_choice)
	music_reactivity_choice.connect("item_selected",self,"_select_music_reactivity")
	_label(addr_row, "Optional Home Assistant advanced integration")
	ha_endpoint_edit = _edit(addr_row, "Optional HA: wss://your-ha/api/websocket")
	_label(addr_row, "Independent audio origin (HA connection is optional)")
	stream_origin_edit = _edit(addr_row, "Audio origin: https://your-authorized-stream-host:port")
	_label(addr_row, "Home Assistant media_player entity")
	entity_edit = _edit(addr_row, "Optional HA media_player entity")
	_label(addr_row, "Cleartext transport is unencrypted; select only for a trusted private LAN.")
	transport_trust = CheckBox.new()
	transport_trust.rect_min_size.y = 52
	transport_trust.text = "Trust LAN HTTP / WS"
	addr_row.add_child(transport_trust)
	_label(addr_row, "Home Assistant token — memory only")
	token_edit = _edit(addr_row, "Home Assistant long-lived token (memory only)", true)
	_button(addr_row, "CONNECT HA", "_connect_ha")
	_button(addr_row, "SAVE SETUP", "_save_setup")
	ma_button = _button(addr_row, "MUSIC ASSISTANT LIBRARY", "_show_ma_catalog")
	ma_panel = load("res://scripts/MASetupPanel.gd").new()
	addr_row.add_child(ma_panel)
	ma_panel.playback_owner=self
	ma_panel.hide()
	_responsive_catalog(ma_panel)
	ma_panel.connect("media_selected", self, "_on_ma_selected")
	ma_panel.connect("preview_requested", self, "_on_ma_preview")
	ma_panel.connect("close_requested", self, "_on_ma_catalog_closed")
	ma_panel.connect("sendspin_start_requested", self, "_start_sendspin_player")
	ma_panel.catalog.connect("state_changed",self,"_recovery_catalog_state")
	ma_panel.connect("sendspin_stop_requested", self, "_stop_sendspin_player")
	ma_panel.connect("sendspin_reveal_requested", self, "_reveal_sendspin_pairing")
	ma_panel.connect("sendspin_confirm_requested", self, "_confirm_sendspin_pairing")
	ma_panel.connect("sendspin_command_requested", self, "_sendspin_command")
	ma_panel.connect("sendspin_play_here_requested", self, "_on_sendspin_play_here")
	var url_row = VBoxContainer.new()
	settings_box.add_child(url_row)
	_label(url_row, "Audio URL and decoder")
	codec_choice = OptionButton.new()
	codec_choice.add_item("PCM16 WAV (Godot)")
	codec_choice.add_item("MP3 (native decoder)")
	codec_choice.add_item("Ogg Vorbis (native decoder; no Opus)")
	codec_choice.rect_min_size.y = 49
	codec_choice.clip_text = true
	url_row.add_child(codec_choice)
	reduced_motion = CheckBox.new()
	reduced_motion.rect_min_size.y = 52
	reduced_motion.text = "Reduced motion"
	url_row.add_child(reduced_motion)
	large_text = CheckBox.new()
	large_text.rect_min_size.y = 52
	large_text.text = "Large text"
	url_row.add_child(large_text)
	large_text.connect("toggled", self, "_set_large_text")
	_label(url_row, "Optional configured metronome BPM (0 disables; 30–240). This does not detect musical beats.")
	metronome_bpm = SpinBox.new()
	metronome_bpm.min_value = 0
	metronome_bpm.max_value = 240
	metronome_bpm.step = 1
	metronome_bpm.rect_min_size.y = 49
	url_row.add_child(metronome_bpm)
	url_edit = _edit(url_row, "Authorized PCM WAV URL (no account credentials)")
	_button(url_row, "STREAM AUDIO", "_start_audio")
	_button(url_row, "STOP AUDIO", "_stop_audio")
	detail_label = _label(settings_box, "HA is optional. Configure an authorized PCM WAV origin and URL; Stream retries, Stop cancels.")
	detail_label.autowrap = true
	_label(settings_box, "  Music Assistant is primary; HA optional. HA token stays in memory; MA credentials use Android secure storage.")
	_button(settings_box, "LICENSES & NOTICES", "_show_licenses")
	# TV remote can navigate controls with D-pad.
	var setup = ConfigFile.new()
	if setup.load("user://installation.cfg") == OK:
		backing_dancers.pressed = bool(setup.get_value("installation", "backing_dancers", false))
		var saved_reactivity=setup.get_value("installation","music_reactivity",1)
		if typeof(saved_reactivity)==TYPE_INT and saved_reactivity>=0 and saved_reactivity<SENSITIVITY_LEVELS.size():_select_music_reactivity(saved_reactivity)
		var saved_visuals=setup.get_value("installation","visuals_enabled",true)
		visuals_enabled=saved_visuals if typeof(saved_visuals)==TYPE_BOOL else true
		var saved_quality=str(setup.get_value("installation","visual_quality","auto"))
		if visual_governor.set_mode(saved_quality,OS.get_ticks_msec()): visual_quality_choice.select(visual_governor.MODES.find(saved_quality))
		ha_endpoint_edit.text = str(setup.get_value("installation", "ha_websocket", ""))
		stream_origin_edit.text = str(setup.get_value("installation", "stream_origin", ""))
		entity_edit.text = str(setup.get_value("installation", "entity", ""))
		transport_trust.pressed = bool(setup.get_value("installation", "trust_private_cleartext", false))
		reduced_motion.pressed = bool(setup.get_value("installation", "reduced_motion", false))
		metronome_bpm.value = float(setup.get_value("installation", "configured_metronome_bpm", 0))
		large_text.pressed = bool(setup.get_value("installation", "large_text", false))
		_restore_gesture_setup(setup)
		_set_large_text(large_text.pressed)
	entity_edit.grab_focus()

func _device_info_text(model, platform, version, controllers):
	var clean_model = str(model).strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 100)
	if clean_model.empty(): clean_model = "Not reported"
	var clean_platform = str(platform).strip_edges().substr(0, 40)
	if clean_platform.empty(): clean_platform = "Not reported"
	var names = []
	for controller in controllers:
		var name = str(controller).strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 100)
		if not name.empty(): names.append(name)
	return "Kinegra Amp %s\nDevice: %s\nPlatform: %s\nHardware revision: Not reported\nControllers: %s\nRemote: Not reported" % [version, clean_model, clean_platform, (", ".join(names) if not names.empty() else "None reported")]

func _refresh_device_info():
	if device_info_label == null: return
	var controllers = []
	for id in Input.get_connected_joypads(): controllers.append(Input.get_joy_name(id))
	var version = str(ProjectSettings.get_setting("application/config/version")) if ProjectSettings.has_setting("application/config/version") else "Unknown"
	device_info_label.text = _device_info_text(OS.get_model_name(), OS.get_name(), version, controllers)

func _joy_changed(_device, _connected):
	_refresh_device_info()

func _open_support_profile():
	var error = OS.shell_open(SUPPORT_PROFILE)
	if support_status_label != null:
		support_status_label.text = "Opening GitHub profile in a browser." if error == OK else "Could not open browser. Visit github.com/matthewhand."

func _recast_backups():
	var current=[]
	for performer in backing_avatars:current.append(performer.mode)
	backing_cast=preload("res://scripts/BackupCast.gd").assign(avatar_visual.mode if avatar_visual.active else "skeleton",avatar_visual.STYLES,current,backing_avatars.size())
	for index in range(backing_avatars.size()):
		if not backing_cast[index].empty():backing_avatars[index].set_style(backing_cast[index])
	_set_backing_dancers(backing_dancers.pressed if backing_dancers!=null else false)
func _set_backing_dancers(value):
	avatar_visual.grouped=bool(value)
	for index in range(backing_avatars.size()):
		backing_avatars[index].view_mode=avatar_visual.view_mode
		backing_avatars[index].set_active(bool(value) and visual_quality_level==2 and index<backing_cast.size() and not backing_cast[index].empty())
	if not value:backup_choreography.reset()

func _select_visual_quality(index):
	if index<0 or index>=visual_governor.MODES.size():return
	visual_governor.set_mode(visual_governor.MODES[index],OS.get_ticks_msec())
	_apply_visual_budget(visual_governor.snapshot())
	_update_visual_quality_status()

	if visual_quality_choice!=null:visual_quality_choice.hint_tooltip=visual_quality_choice.get_item_text(index)

func set_visuals_enabled(value):
	if typeof(value)!=TYPE_BOOL:return false
	visuals_enabled=value
	# Override the effective render budget, never the governor's selected mode
	# or recovery state. Audio source/pump ownership is deliberately untouched.
	_apply_visual_budget(visual_governor.snapshot())
	_update_visual_quality_status()
	if music_ui!=null:music_ui.sync_visuals_control()
	return true

func _apply_visual_budget(state):
	var level=int(state.level) if visuals_enabled and not stream_warmup_budget.holding else 0
	if visual_quality_level==level:return
	var previous_level=visual_quality_level
	visual_quality_level=level
	if music_ui!=null:music_ui.sync_static_art()
	visual.material=shader_material if level==2 else (light_shader_material if level==1 else null)
	visual.color=Color.white if level>0 else Color(0.02,0.035,0.06,1.0)
	if previous_level==0 and level>0:avatar_visual.set_pose([]) # Wait for a fresh tracking/demo frame.
	avatar_visual.set_render_budget(60 if level==2 else (15 if level==1 else 0))
	for performer in backing_avatars:performer.set_render_budget(30 if level==2 else 0)
	_set_backing_dancers(backing_dancers.pressed)
	# Rendering/tracking budgets preserve the user's selected modes.
	_refresh_pose_control_budget()
	if music_ui!=null and music_ui.track_hero!=null and music_ui.track_hero.has_method("set_render_budget"):
		music_ui.track_hero.set_render_budget(30 if level==2 else (10 if level==1 else 0))
	_budget_spectrum(level>0)
	frame_metrics.reset()
	visual_update_elapsed=1.0

func _budget_spectrum(enabled):
	var bus=AudioServer.get_bus_index("Milkdrop")
	if bus<0:return
	for index in range(AudioServer.get_bus_effect_count(bus)):
		if not AudioServer.get_bus_effect(bus,index) is AudioEffectSpectrumAnalyzer:continue
		if not enabled and spectrum_budget_saved==null:
			spectrum_budget_saved=AudioServer.is_bus_effect_enabled(bus,index)
			AudioServer.set_bus_effect_enabled(bus,index,false)
		elif enabled and spectrum_budget_saved!=null:
			AudioServer.set_bus_effect_enabled(bus,index,bool(spectrum_budget_saved))
			spectrum_budget_saved=null
		return

func _sample_app_load(platform,now_ms):
	app_cpu_percent=-1.0
	thermal_status=-1
	if platform==null:return
	# The packaged JNI API is mandatory; has_method does not enumerate it.
	var cpu=platform.processCpuTimeMs()
	# Godot 3 JNI supports String/int, not Java long; preserve the full counter.
	if typeof(cpu)==TYPE_STRING:
		cpu=cpu.to_int() if cpu.length()>0 and cpu.length()<=16 and cpu.is_valid_integer() else -1
	var heat=platform.thermalStatus()
	if typeof(heat)==TYPE_INT and heat>=-1 and heat<=6:thermal_status=heat
	if typeof(cpu)!=TYPE_INT or cpu<0:
		cpu_sample_at=-1;cpu_sample_value=-1;return
	if cpu_sample_at>=0 and now_ms>cpu_sample_at and cpu>=cpu_sample_value:
		app_cpu_percent=clamp(100.0*float(cpu-cpu_sample_value)/float(now_ms-cpu_sample_at)/float(max(1,OS.get_processor_count())),0.0,100.0)
	cpu_sample_at=now_ms
	cpu_sample_value=cpu

func _prepare_stream_visuals():
	stream_warmup_budget.prepare(OS.get_ticks_msec())
	_apply_visual_budget(visual_governor.snapshot())
	_update_visual_quality_status()

func _update_stream_warmup():
	var audio={}
	if sendspin_facade!=null and is_instance_valid(sendspin_facade) and sendspin_facade.sink!=null and sendspin_facade.sink.active:
		audio=sendspin_facade.sink.buffer_stats().duplicate()
		audio.active=true
		audio.generation=sendspin_facade.sink.stream_generation
		audio.buffering=audio.buffering or (sendspin_facade.runtime!=null and sendspin_facade.runtime.buffering)
	var was_holding=stream_warmup_budget.holding
	stream_warmup_budget.observe(OS.get_ticks_msec(),audio)
	_apply_visual_budget(visual_governor.snapshot())
	if was_holding!=stream_warmup_budget.holding:
		_update_visual_quality_status()

func _update_headroom():
	var now=OS.get_ticks_msec()
	var platform=Engine.get_singleton("ShieldAmpTokenStore") if Engine.has_singleton("ShieldAmpTokenStore") else null
	_sample_app_load(platform,now)
	var audio={}
	if sendspin_facade!=null and is_instance_valid(sendspin_facade) and sendspin_facade.sink!=null and sendspin_facade.sink.active:
		audio=sendspin_facade.sink.buffer_stats().duplicate()
		audio.active=true
		audio.generation=sendspin_facade.sink.stream_generation
	var pacing=frame_metrics.snapshot()
	if pacing.count>=30:
		_apply_visual_budget(visual_governor.observe(now,pacing.p95_ms,pacing.late_ratio,audio,app_cpu_percent,thermal_status,display_refresh_hz))
	_update_visual_quality_status()

func _update_visual_quality_status():
	if visual_quality_status==null:return
	var state=visual_governor.snapshot()
	if visuals_enabled and stream_warmup_budget.holding:
		visual_quality_status.text="PREPARING AUDIO / Visuals return after the buffer settles"
		return
	if not visuals_enabled:
		visual_quality_status.text="VISUALS OFF / Static artwork and playback controls\nSelected quality retained: %s / %s" % [state.mode.to_upper(),state.label]
		return
	var cpu=("%.0f%%" % app_cpu_percent) if app_cpu_percent>=0 else "unavailable"
	var heat=["Normal","Slightly warm","Warm","Hot","Very hot","Very hot","Very hot"][thermal_status] if thermal_status>=0 else "unavailable"
	visual_quality_status.text="%s / %s · %s\nCPU used by Kinegra Amp %s · slow frames %.1f ms · heat %s" % [state.mode.to_upper(),state.label,state.reason,cpu,frame_metrics.snapshot().p95_ms,heat]

func _connect_ha():
	api.start(token_edit.text, entity_edit.text, ha_endpoint_edit.text, transport_trust.pressed)
	token_edit.text = ""

func _on_connectivity(ok, msg):
	state_label.text = ("  HA CONNECTED: " if ok else "  HA OFFLINE: ") + msg

func _on_track(data):
	title_label.text = "  " + data["title"] + "  —  " + data["artist"]
	state_label.text = "  " + data["state"].to_upper() + "  |  " + entity_edit.text
	progress.max_value = max(1.0, float(data["duration"]))
	progress.value = float(data["position"])

func _on_command(ok, desc):
	detail_label.text = "  %s %s" % [("OK:" if ok else "FAILED:"), desc]

func _toggle():
	api.media_command("media_play_pause")

func _next():
	api.media_command("media_next_track")

func _previous():
	api.media_command("media_previous_track")

func _switch_demo():
	# Legacy visual demonstration never plays audio; keep it opt-in.
	demo = not demo
	_update_mode()

func _update_mode():
	detail_label.text = "  " + ("DEMO VISUALS (synthetic)" if demo else ("LIVE FFT" if live_audio else "LIVE FFT: NO PCM AUDIO"))

func _start_audio():
	if offline_music != null:
		offline_music.stop()
	_stop_audio()
	if codec_choice.selected == 0:
		analysis_owner = stream_engine
		stream_engine.configure(stream_origin_edit.text, transport_trust.pressed)
		stream_engine.start(url_edit.text)
	else:
		analysis_owner = native_stream_engine
		native_transport.configure(native_stream_engine, stream_origin_edit.text, transport_trust.pressed)
		native_transport.start(url_edit.text, codec_choice.selected)
	_reset_analysis()

func _stop_audio():
	if not recovery_restarting:playback_recovery.cancel()
	_close_sendspin_analysis()
	if local_pcm != null:
		if local_pcm.active:
			live_audio = false
		local_pcm.stop()
	if native_transport != null:
		native_transport.stop()
	if native_stream_engine != null:
		native_stream_engine.stop()
	if stream_engine != null:
		stream_engine.stop()
	# Disarm any old PCM epoch before an unrelated source can restart.
	analysis_owner = null
	_reset_analysis()

func begin_explicit_local_pcm():
	# Only a caller explicitly providing local PCM may start this source.
	# This is NOT Music Assistant, and does not provide Sendspin clock sync.
	_stop_all_music()
	var ok = local_pcm != null and local_pcm.begin_local_pcm()
	if ok:
		live_audio = true
		_reset_analysis()
	return ok

func feed_explicit_local_pcm(bytes):
	return local_pcm.queue_local_pcm(bytes) if local_pcm != null else false

func begin_native_audio(codec):
	_stop_audio()
	analysis_owner = native_stream_engine
	_reset_analysis()
	return native_stream_engine.begin(codec)

func feed_native_audio(packet):
	return native_stream_engine.feed(packet) if native_stream_engine != null else -1

func finish_native_audio():
	if native_stream_engine != null:
		native_stream_engine.end_stream()

func _reset_analysis():
	fft_envelope.reset()
	analysis_epoch += 1
	analysis_frame.begin_epoch(analysis_epoch)
	backup_tempo.reset()
	backup_choreography.reset()

# Prepared hook only: no startup, UI or network action calls it by default.
# The caller must explicitly create/start the experimental facade first.
func attach_sendspin_analysis(facade):
	if facade==sendspin_facade and facade!=null:
		return false
	if facade==null or not is_instance_valid(facade) or facade.runtime==null or not facade.runtime.active or facade.sink==null:
		return false
	var source=facade.sink
	if not source.has_signal("pcm_observed") or not source.has_signal("analysis_invalidated"):
		return false
	_stop_all_music()
	sendspin_facade=facade
	analysis_owner=source
	source.connect("pcm_observed",self,"_on_pcm_observed",[source])
	source.connect("analysis_invalidated",self,"_on_sendspin_invalidated",[source])
	live_audio=false
	_reset_analysis()
	return true

func _on_sendspin_invalidated(source):
	if source==analysis_owner:
		live_audio=false
		_reset_analysis()

func _sendspin_fresh():
	return sendspin_facade!=null and is_instance_valid(sendspin_facade) and analysis_owner!=null and is_instance_valid(analysis_owner) and analysis_owner==sendspin_facade.sink and analysis_owner.active and analysis_owner.last_pcm_at>=0 and OS.get_ticks_msec()-analysis_owner.last_pcm_at<=500

func _close_sendspin_analysis():
	if tv_queue_timer!=null: tv_queue_timer.stop()
	if tv_reconnect_timer!=null: tv_reconnect_timer.stop()
	if tv_audio_wait_timer!=null: tv_audio_wait_timer.stop()
	tv_reconnect_waiting=false
	_reset_tv_audio()
	tv_queue_last_action=""
	tv_queue_state=""
	tv_queue_timing.clear()
	tv_queue_timing_read_at=-1
	tv_queue_pending_session=null
	if tv_queue_request!=null and is_instance_valid(tv_queue_request):
		tv_queue_request.cancel()
		tv_queue_request.queue_free()
	tv_queue_request=null
	if ma_panel!=null: ma_panel.clear_pairing_code()
	if music_ui!=null: music_ui.invalidate_tv_queue()
	if sendspin_facade==null or not is_instance_valid(sendspin_facade):
		sendspin_facade=null
		return
	var facade=sendspin_facade
	sendspin_facade=null
	var source=facade.sink
	if source!=null and is_instance_valid(source):
		if source.is_connected("pcm_observed",self,"_on_pcm_observed"):
			source.disconnect("pcm_observed",self,"_on_pcm_observed")
		if source.is_connected("analysis_invalidated",self,"_on_sendspin_invalidated"):
			source.disconnect("analysis_invalidated",self,"_on_sendspin_invalidated")
	facade.stop()
	if facade is Node: facade.queue_free()
	if ma_panel!=null: ma_panel.set_sendspin_status("idle","TV player stopped")

func _on_pcm_observed(source_epoch, _rms, _playback_ms, _latency_ms, owner):
	if owner != analysis_owner or source_epoch != owner.epoch:
		return
	live_audio = true
	demo = false

func _on_stream_message(msg):
	detail_label.text = "  " + msg
	if music_ui != null:
		music_ui.show_status(msg)

func _on_stream_active(playing):
	# A stale STOP event from another local/native player must not revoke
	# an explicitly active PCM source or reset its FFT analysis epoch.
	var pcm_active = local_pcm != null and local_pcm.active and local_pcm.audio != null and local_pcm.audio.playing
	live_audio = playing or (offline_music != null and offline_music.is_playing()) or pcm_active or _sendspin_fresh()
	if not playing and not pcm_active and not _sendspin_fresh():
		_reset_analysis()
	if playing:
		demo = false
	_update_mode()

func _play_offline_music():
	if music_ui!=null:music_ui.set_playback_context("offline")
	# Explicit user-initiated bundled music, never synthetic tones.
	_stop_audio()
	if offline_music != null:
		if offline_music.player == null or offline_music.player.stream == null:
			if music_ui != null:
				music_ui.show_status("NO LOCAL TRACK  /  RESTORE SAMPLES IN OFFLINE LIBRARY")
		else:
			offline_music.play()
		live_audio = offline_music.is_playing()
		demo = false

func _toggle_offline():
	if offline_music != null and offline_music.is_playing():
		offline_music.toggle()
		live_audio = false
	else:
		_play_offline_music()

func _next_offline():
	if music_ui!=null:music_ui.set_playback_context("offline")
	_stop_audio()
	if offline_music != null:
		offline_music.next_track()
		live_audio = offline_music.is_playing()
		demo = false

func _previous_offline():
	if music_ui!=null:music_ui.set_playback_context("offline")
	_stop_audio()
	if offline_music != null:
		offline_music.previous_track()
		live_audio = offline_music.is_playing()
		demo = false

func _stop_all_music():
	if offline_music != null:
		offline_music.stop()
	_stop_audio()
	live_audio = false
	demo = false
	if music_ui != null:
		music_ui.show_status("STOPPED  •  READY FOR MUSIC")

func _on_offline_track(name):
	# Catalog maintenance cannot steal the active streaming presentation.
	if music_ui != null and (music_ui.playback_context=="offline" or offline_music.is_playing()):
		music_ui.show_offline_track(name, offline_music.is_playing())
	if title_label != null:
		title_label.text = "  " + str(name)

func _on_offline_state(playing):
	# An idle Ogg player must not clear ownership of explicitly active PCM.
	live_audio = playing or (local_pcm != null and local_pcm.active and local_pcm.audio != null and local_pcm.audio.playing) or _sendspin_fresh()
	if playing:
		demo = false
	if music_ui != null:
		music_ui.show_offline_state(playing)

func _show_music_stage():
	if music_ui != null:
		music_ui.show_stage()

func _cycle_visual_preset():
	preset_index = (preset_index + 1) % VISUAL_PRESETS.size()
	if music_ui != null:
		music_ui.show_visual_preset(VISUAL_PRESETS[preset_index])
	return VISUAL_PRESETS[preset_index]

func _select_music_reactivity(index):
	if typeof(index)!=TYPE_INT or index<0 or index>=SENSITIVITY_LEVELS.size():return false
	sensitivity_index=index
	fft_envelope.set_sensitivity(SENSITIVITY_LEVELS[sensitivity_index])
	if music_reactivity_choice!=null:
		music_reactivity_choice.select(sensitivity_index)
		music_reactivity_choice.hint_tooltip=music_reactivity_choice.get_item_text(sensitivity_index)
	if music_ui!=null:music_ui.show_visual_sensitivity(SENSITIVITY_LABELS[sensitivity_index])
	return true

func _cycle_visual_sensitivity():
	_select_music_reactivity((sensitivity_index+1)%SENSITIVITY_LEVELS.size())
	return SENSITIVITY_LABELS[sensitivity_index]

func _cue_offline_track(index):
	if music_ui!=null:music_ui.set_playback_context("offline")
	if offline_music == null or typeof(index) != TYPE_INT:
		return false
	if not index in offline_music.playlists.indices():
		return false
	# Stop any competing analysis source, without starting audio.
	_stop_all_music()
	var selected = offline_music.cue_track(index)
	if selected:
		live_audio = false
	return selected

func _cycle_offline_playlist():
	return offline_music.cycle_playlist() if offline_music != null else false

func _toggle_offline_favorite():
	return offline_music.toggle_favorite() if offline_music != null else false

func _cycle_offline_repeat():
	return offline_music.cycle_repeat() if offline_music != null else "OFF"

func _toggle_offline_shuffle():
	return offline_music.toggle_shuffle() if offline_music != null else false

func _process(delta):
	_continue_queue_resume()
	if tv_audio_requested and _tv_audio_ready():
		tv_audio_requested=false
		if tv_audio_wait_timer!=null:tv_audio_wait_timer.stop()
		if music_ui!=null and music_ui._tv_mode():music_ui.show_status("")
	_update_playback_recovery()
	_update_stream_warmup()
	_refresh_pose_control_budget()
	_gesture_ui_elapsed+=delta
	if _gesture_ui_elapsed>=0.1:
		_gesture_ui_elapsed=0.0
		body_control_policy.tick(OS.get_ticks_msec(),_gesture_context_allowed()) if gesture_mode=="panel" else gesture_policy.tick(OS.get_ticks_msec(),_gesture_context_allowed())
		_update_gesture_feedback()
	frame_metrics.observe(delta)
	headroom_elapsed+=delta
	if headroom_elapsed>=1.0:
		headroom_elapsed=0.0
		_update_headroom()
	visual_update_elapsed+=delta
	var interval=0.0 if visual_quality_level==2 else (1.0/15.0 if visual_quality_level==1 else 0.2)
	if visual_update_elapsed>=interval:
		var visual_delta=visual_update_elapsed
		visual_update_elapsed=0.0
		_update_visuals(visual_delta)
	_report_frame_metrics(delta)

func _update_visuals(delta):
	_apply_resolution_base()
	var real_offline_music = offline_music != null and offline_music.is_playing()
	var real_local_pcm = local_pcm != null and local_pcm.active and local_pcm.audio != null and local_pcm.audio.playing
	var real_local_audio = real_offline_music or real_local_pcm
	elapsed += delta
	var raw_bands = []
	for i in range(16):
		var next_value = 0.0
		if demo:
			# Explicitly synthetic demonstration, not a claimed spectrum.
			var pulse = max(0.0, sin(elapsed * 3.3 - float(i) * 0.41))
			next_value = 0.09 + pulse * (0.3 + 0.3 * sin(float(i) * 0.6 + elapsed))
		elif live_audio and spectrum != null and visual_quality_level>0:
			var lo = 20.0 * pow(500.0, float(i) / 16.0)
			var hi = 20.0 * pow(500.0, float(i + 1) / 16.0)
			var mag = spectrum.get_magnitude_for_frequency_range(lo, hi)
			next_value = clamp((mag.x + mag.y) * 8.0, 0.0, 1.0)
		raw_bands.append(next_value)
	fft = fft_envelope.apply(raw_bands, delta)
	analysis_frame.configure_metronome(metronome_bpm.value if metronome_bpm != null else 0)
	if not demo and analysis_owner != null and analysis_owner.active and analysis_owner.last_pcm_at >= 0:
		analysis_frame.publish(analysis_epoch, raw_bands, analysis_owner.last_rms, analysis_owner.last_pcm_at, analysis_owner.playback_time_ms, analysis_owner.queued_latency_ms)
	var now_ms=OS.get_ticks_msec()
	var frame = analysis_frame.snapshot(now_ms)
	var dance_source=not demo and visual_quality_level>0 and (real_local_audio or (analysis_owner!=null and analysis_owner.active and analysis_owner.last_pcm_at>=0 and now_ms-analysis_owner.last_pcm_at<=500))
	backup_tempo.observe(now_ms,raw_bands,dance_source,analysis_epoch)
	var tempo_state=backup_tempo.snapshot(now_ms)
	if not demo and not real_local_audio and frame["source"] != "live_pcm":
		for i in range(16):
			fft[i] = 0.0
	analysis_label.text = ("OFFLINE MUSIC / REAL AUDIO FFT" if real_offline_music else ("LOCAL PCM / REAL AUDIO FFT" if real_local_pcm else ("DEMO VISUALS / NO AUDIO" if demo else ("LIVE PCM / RMS %.3f" % frame["rms"] if frame["source"] == "live_pcm" else "IDLE / NO AUDIO"))))
	var material=shader_material if visual_quality_level==2 else light_shader_material
	if visual_quality_level>0:
		material.set_shader_param("visual_preset",float(preset_index))
		material.set_shader_param("motion",0.0 if reduced_motion.pressed else 1.0)
		material.set_shader_param("viewport_aspect",max(0.1,rect_size.x/max(1.0,rect_size.y)))
		material.set_shader_param("bands_0",Color(fft[0],fft[1],fft[2],fft[3]))
		material.set_shader_param("reactive",(fft[0]+fft[1])*0.5)
		if visual_quality_level==2:
			material.set_shader_param("bands_1",Color(fft[4],fft[5],fft[6],fft[7]))
			material.set_shader_param("bands_2",Color(fft[8],fft[9],fft[10],fft[11]))
			material.set_shader_param("bands_3",Color(fft[12],fft[13],fft[14],fft[15]))
	emit_signal("analysis_updated",frame)
	if visual_quality_level>0 and pose_visual != null and pose_visual.enabled:
		pose_visual.intensity=(fft[0]+fft[1])*0.5
		pose_visual.update()
	if visual_quality_level>0 and avatar_visual != null and avatar_visual.active:
		if pose_visual.mode!="live" or pose_visual.tracking_live:avatar_visual.view_mode=pose_visual.view_mode if pose_visual.enabled and pose_visual.tracking_live else "body"
		avatar_visual.intensity=(fft[0]+fft[1])*0.5
		var accepted=avatar_visual.set_tracked_pose(pose_visual.points,pose_visual.tracking_live and pose_visual.status!="BODY HOLD / BRIEF DROPOUT") if pose_visual.mode=="live" else avatar_visual.set_pose(pose_visual.points if pose_visual.enabled else [])
		if accepted:
			avatar_visual.set_visual_context(preset_index,(fft[0]+fft[1]+fft[2])/3.0,(fft[4]+fft[5]+fft[6])/3.0,(fft[8]+fft[9]+fft[10])/3.0,not reduced_motion.pressed)
	var dance_enabled=visual_quality_level==2 and backing_dancers!=null and backing_dancers.pressed
	backup_choreography.step(delta,tempo_state,dance_enabled and dance_source,reduced_motion.pressed,metronome_bpm.value if metronome_bpm!=null else 0.0)
	for i in range(backing_avatars.size()):
		var performer=backing_avatars[i]
		# Share zoom/crop only: each puppet retains its own framing origin.
		performer.view_mode=avatar_visual.view_mode
		if dance_enabled:
			performer.intensity=(fft[0]+fft[1])*0.5
			performer.set_visual_context(preset_index,(fft[0]+fft[1]+fft[2])/3.0,(fft[4]+fft[5]+fft[6])/3.0,(fft[8]+fft[9]+fft[10])/3.0,not reduced_motion.pressed)
			performer.set_pose(backup_choreography.pose(i))
		elif not performer.last_points.empty():performer.set_pose([])

func _report_frame_metrics(delta):
	frame_sample_seconds += delta
	frame_sample_count += 1
	if frame_sample_seconds >= 10.0:
		# Bounded in-memory metrics, no remote telemetry and no new audio.
		var pacing = frame_metrics.snapshot()
		print("SHIELDAMP_HEADROOM level=%d app_cpu_pct=%.1f thermal=%d p95_ms=%.1f" % [visual_quality_level,app_cpu_percent,thermal_status,pacing.p95_ms])
		print("TEGRA_MILKDROP_METRIC fps_engine=%.1f fps_counted=%.1f frame_p95_ms=%.1f late_ratio=%.3f mode=%s" % [Engine.get_frames_per_second(), float(frame_sample_count) / frame_sample_seconds, pacing["p95_ms"], pacing["late_ratio"], ("demo" if demo else ("live" if live_audio else "idle"))])
		if sendspin_facade!=null and is_instance_valid(sendspin_facade) and sendspin_facade.sink!=null and sendspin_facade.sink.active:
			var audio_stats=sendspin_facade.sink.buffer_stats()
			var pcm_age=OS.get_ticks_msec()-sendspin_facade.sink.last_pcm_at if sendspin_facade.sink.last_pcm_at>=0 else -1
			print("SHIELDAMP_AUDIO queued_ms=%d underruns=%d rebuffers=%d buffering=%s generation=%d pcm_age_ms=%d rms=%.4f" % [audio_stats.queued_ms,audio_stats.underruns,audio_stats.rebuffers,str(audio_stats.buffering),sendspin_facade.sink.stream_generation,pcm_age,sendspin_facade.sink.last_rms])
		if pose_visual!=null:
			print("SHIELDAMP_WEBCAM connected=%s processing=%s polls=%d" % [str(pose_visual.webcam_connected),str(pose_visual.is_processing()),pose_visual.poll_attempts])
		frame_sample_seconds = 0.0
		frame_sample_count = 0

func _save_setup():
	var policy = load("res://scripts/ConnectionPolicy.gd").new()
	var ha = ha_endpoint_edit.text.strip_edges()
	var origin = stream_origin_edit.text.strip_edges()
	if ha != "" and (not ha.ends_with("/api/websocket") or policy.origin(ha.trim_suffix("/api/websocket"), ["ws", "wss"], transport_trust.pressed).empty()):
		detail_label.text = "Invalid HA endpoint; setup was not saved"
		return
	if origin != "" and policy.origin(origin, ["http", "https"], transport_trust.pressed).empty():
		detail_label.text = "Invalid audio origin; setup was not saved"
		return
	var entity = entity_edit.text.strip_edges()
	if entity != "":
		var regex = RegEx.new()
		regex.compile("^media_player\\.[a-z0-9_]{1,100}$")
		if regex.search(entity) == null:
			detail_label.text = "Invalid media_player entity; setup was not saved"
			return
	var config = ConfigFile.new()
	config.set_value("installation", "backing_dancers", backing_dancers.pressed)
	config.set_value("installation","webcam_gestures_enabled",gesture_policy.enabled)
	config.set_value("installation","webcam_gesture_mode",gesture_mode)
	config.set_value("installation","webcam_gesture_bindings",gesture_policy.bindings)
	config.set_value("installation","visual_quality",visual_governor.mode)
	config.set_value("installation","visuals_enabled",visuals_enabled)
	config.set_value("installation","music_reactivity",sensitivity_index)
	config.set_value("installation", "ha_websocket", ha)
	config.set_value("installation", "stream_origin", origin)
	config.set_value("installation", "entity", entity)
	config.set_value("installation", "trust_private_cleartext", transport_trust.pressed)
	config.set_value("installation", "reduced_motion", reduced_motion.pressed)
	config.set_value("installation", "large_text", large_text.pressed)
	config.set_value("installation", "configured_metronome_bpm", metronome_bpm.value)
	detail_label.text = "Setup saved; token and track URL remain memory only" if config.save("user://installation.cfg") == OK else "Setup could not be saved"

func _update_layout():
	if command_grid != null:
		command_grid.columns = int(clamp(floor((rect_size.x - 48.0) / (230.0 if large_text != null and large_text.pressed else 160.0)), 1, 4))

func _handle_tv_back(source="input"):
	if body_control_policy.panel_open:
		_close_body_control_panel()
		return
	_cancel_requested_play()
	if music_ui!=null and music_ui.handle_topmost_back(source):return
	if music_ui != null and music_ui.fullscreen_visual:
		music_ui._exit_fullscreen()
		return
	# Omega Prime TVInput: gamepad B (1), Back/Select (11) are navigation.
	# Read actual visibility, not the property of a widget hidden by its parent.
	if ma_panel != null and ma_panel.is_visible_in_tree():
		ma_panel._close()
		return
	if music_ui != null and music_ui.queue_drawer != null and music_ui.queue_drawer.visible:
		music_ui._close_queue()
		return
	if music_ui != null and music_ui.offline_drawer != null and music_ui.offline_drawer.visible:
		music_ui._close_offline_collection()
		return
	var focus = get_focus_owner()
	if focus is LineEdit:
		focus.release_focus()
		return
	if page_scroller != null and page_scroller.visible:
		_show_music_stage()
		return
	if offline_music != null and offline_music.is_playing():
		offline_music.stop()
		live_audio = false
		return
	if live_audio:
		_stop_audio()
		return
	print("SHIELDAMP_LIFECYCLE event=back_exit")
	get_tree().quit()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_layout()
	elif what in [MainLoop.NOTIFICATION_APP_PAUSED, MainLoop.NOTIFICATION_WM_FOCUS_OUT]:
		gesture_policy.cancel("Gestures paused / return to player and hold neutral")
		_flush_app_volume()
		if what == MainLoop.NOTIFICATION_APP_PAUSED:
			print("SHIELDAMP_LIFECYCLE event=paused")
			app_is_paused=true
		else: app_has_focus=false
		# Suspend webcam work on focus loss; only a real pause stops audio.
		if pose_visual != null and pose_visual.enabled and (what==MainLoop.NOTIFICATION_APP_PAUSED or not (gesture_mode=="panel" and gesture_policy.enabled)):
			pose_suspended_mode=pose_visual.mode
			pose_visual.set_enabled(false)
		if what==MainLoop.NOTIFICATION_APP_PAUSED and offline_music!=null:
			offline_music.stop()
		if what==MainLoop.NOTIFICATION_APP_PAUSED:
			_stop_audio()
			live_audio = false
	elif what in [MainLoop.NOTIFICATION_APP_RESUMED, MainLoop.NOTIFICATION_WM_FOCUS_IN]:
		if what == MainLoop.NOTIFICATION_APP_RESUMED: app_is_paused=false
		else: app_has_focus=true
		if app_has_focus and not app_is_paused and not pose_suspended_mode.empty():
			var desired_mode=pose_suspended_mode
			pose_suspended_mode=""
			if pose_visual!=null and pose_visual.mode=="off": pose_visual.set_mode(desired_mode)
	elif what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android native Back goes through this notification once.
		_handle_tv_back("native")

func _input(event):
	if body_control_panel!=null and body_control_panel.route(event):
		get_tree().set_input_as_handled()
		return
	if music_ui != null and music_ui.route_drawer_input(event):
		get_tree().set_input_as_handled()
		return
	if music_ui != null and music_ui.fullscreen_visual:
		if event is InputEventJoypadButton and event.pressed and event.button_index in [1,11]:
			_handle_tv_back()
			get_tree().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo and event.scancode in [KEY_ESCAPE,KEY_BACKSPACE]:
			_handle_tv_back()
			get_tree().set_input_as_handled()
			return
		if (event is InputEventJoypadMotion and abs(event.axis_value) >= 0.55) or (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventMouseButton and event.pressed):
			music_ui._show_fullscreen_help()
			if not (event is InputEventKey and event.scancode in [KEY_VOLUMEUP,KEY_VOLUMEDOWN,KEY_VOLUMEMUTE]):
				get_tree().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.pressed and event.button_index in [1, 11]:
		# Omega Prime ASUS controller B and Back; system/Home keys untouched.
		_handle_tv_back()
		get_tree().set_input_as_handled()
		return
	if event is InputEventKey and event.echo and event.is_action_pressed("ui_accept"):
		get_tree().set_input_as_handled()

func _set_large_text(enabled):
	if accessibility_font != null:
		accessibility_font.size = 28 if enabled else 20
	if music_ui != null:
		music_ui.set_tv_text_mode(enabled)
	_update_layout()

# Saved-session reconnect is read-only; only a current explicit Play intent starts music.
func _start_sendspin_player(endpoint,trusted):
	if sendspin_facade!=null:
		if sendspin_facade.runtime!=null and sendspin_facade.runtime.active:
			# Connect is idempotent: reflecting an existing session as merely
			# connecting would erase its paired client identity in the panel.
			var current=sendspin_facade.client.status() if sendspin_facade.client!=null else {}
			if typeof(current)==TYPE_DICTIONARY and typeof(current.get("paired"))==TYPE_BOOL and current["paired"] and typeof(current.get("client_id"))==TYPE_STRING and not current["client_id"].empty():
				var receiving=sendspin_facade.sink!=null and sendspin_facade.sink.get("active")==true
				ma_panel.set_sendspin_status("receiving" if receiving else "paired","Playback is already connected",str(current.get("client_id","")))
			else:
				ma_panel.set_sendspin_status("connecting","Playback connection is already in progress")
			return
		_stop_audio()
	var facade=load("res://scripts/SendspinExperienceFacade.gd").new()
	add_child(facade)
	if not facade.start_experimental(true,endpoint,trusted):
		facade.queue_free()
		ma_panel.set_sendspin_status("error","Check the private address, LAN trust, native player and secure storage")
		return
	if not attach_sendspin_analysis(facade):
		facade.stop()
		facade.queue_free()
		ma_panel.set_sendspin_status("error","Could not attach the TV player")
		return
	if music_ui!=null:music_ui.set_playback_context("ma")
	facade.runtime.connect("state_changed",self,"_on_sendspin_state",[facade])
	facade.runtime.connect("pairing_code_changed",self,"_on_sendspin_pairing_code",[facade,facade.runtime])
	_on_sendspin_state("connecting","Waiting for Music Assistant; pair this TV in its player settings",facade)

func _on_sendspin_pairing_code(code,facade,runtime):
	if facade!=sendspin_facade or ma_panel==null or not is_instance_valid(runtime): return
	if facade.runtime!=runtime or runtime.current_pairing_code!=code: return
	if typeof(code)!=TYPE_STRING or (not code.empty() and not runtime.active):return
	if not code.empty() and tv_reconnect_waiting and music_ui!=null and not ma_panel.is_visible_in_tree():
		if tv_reconnect_timer!=null: tv_reconnect_timer.stop()
		music_ui._open_library()
	ma_panel.show_pairing_code(code)

func _on_sendspin_state(state,detail,facade):
	if facade!=sendspin_facade or ma_panel==null: return
	playback_detail=str(detail).substr(0,160)
	print("SHIELDAMP_PLAYER state=",state," detail=",playback_detail)
	var id=""
	if state in ["paired","receiving"]:
		if facade.runtime==null or not facade.runtime.active:return
		var status=facade.client.status() if facade.client!=null else null
		if typeof(status)!=TYPE_DICTIONARY or typeof(status.get("paired"))!=TYPE_BOOL or not status["paired"] or typeof(status.get("client_id"))!=TYPE_STRING or status["client_id"].empty():
			state="error"
			detail="Invalid playback identity; disconnect and reconnect playback"
		else:id=status["client_id"]
	var was_paired=ma_panel.sendspin_paired
	ma_panel.set_sendspin_status(state,detail,id)
	if not was_paired and state in ["paired","receiving"] and music_ui!=null:
		ma_panel._save_connection_setting("sendspin","paired_endpoint_hash",ma_panel.sendspin_endpoint.text.strip_edges().sha256_text(),"paired_before",true)
		music_ui.tv_queue_reconnected()
		if tv_queue_timer!=null: tv_queue_timer.start(1.0)
	if was_paired and not state in ["paired","receiving"]:
		tv_queue_pending_session=null
		tv_queue_last_action=""
		tv_queue_state=""
		tv_queue_timing.clear()
		tv_queue_timing_read_at=-1
		if tv_queue_timer!=null: tv_queue_timer.stop()
		if music_ui!=null:
			music_ui.invalidate_tv_queue()
			music_ui.show_status("PLAYBACK DISCONNECTED / PRESS RECONNECT")
	if tv_reconnect_waiting and state in ["paired","receiving"]:
		tv_reconnect_waiting=false
		if tv_reconnect_timer!=null: tv_reconnect_timer.stop()
		if music_ui!=null: music_ui.show_status("PLAYBACK CONNECTED / PRESS PLAY")
	elif state=="error":
		tv_reconnect_waiting=false
		if tv_reconnect_timer!=null: tv_reconnect_timer.stop()
	if state=="error":
		_cancel_requested_play(false)
		stream_warmup_budget.reset()
	if state=="error" and music_ui!=null:
		_set_tv_playback_error("Playback connection failed. Check Music Assistant.")

func _reconnect_tv():
	if ma_panel!=null and ma_panel.library_disconnected:
		if music_ui!=null:
			music_ui._open_library()
			music_ui.show_status("CONNECT LIBRARY TO CONTINUE")
		return false
	if tv_reconnect_waiting or ma_panel==null: return false
	var endpoint=ma_panel.sendspin_endpoint.text.strip_edges()
	var trusted=ma_panel.sendspin_trust.pressed
	var gate=load("res://scripts/SendspinExperienceFacade.gd").new()
	var valid=gate._valid_endpoint(endpoint,trusted)
	gate.free()
	if not valid:
		if music_ui!=null:
			music_ui._open_library()
			if not ma_panel.sendspin_box.visible: ma_panel._toggle_sendspin()
			ma_panel.sendspin_status.text="Enter a private TV player address and explicitly trust the LAN."
			music_ui.show_status("CONFIGURE THE PLAYBACK FIRST")
		return false
	if sendspin_facade!=null: _stop_audio()
	_start_sendspin_player(endpoint,trusted)
	if sendspin_facade==null:
		tv_reconnect_waiting=false
		if music_ui!=null: music_ui.show_status("TV RECONNECT FAILED / CHECK SETTINGS")
		return false
	tv_reconnect_waiting=true
	if tv_reconnect_timer!=null: tv_reconnect_timer.start(20.0)
	if music_ui!=null: music_ui.show_status("RECONNECTING PLAYBACK / NO AUTOPLAY")
	return true
func _on_tv_reconnect_timeout():
	if not tv_reconnect_waiting: return
	_stop_audio()
	if music_ui!=null: music_ui.show_status("PLAYBACK CONNECTION TIMED OUT / RETRY")
func _on_tv_audio_wait_timeout():
	if tv_audio_requested and tv_playback_error.empty() and not _tv_audio_ready() and music_ui!=null and music_ui._tv_mode():
		music_ui.show_status("Still waiting for audio. Press Play to retry.")

func _tv_sink():
	if not is_instance_valid(sendspin_facade):return null
	var sink=sendspin_facade.sink
	return sink if is_instance_valid(sink) and sink==analysis_owner else null

func _tv_audio_ready():
	var sink=_tv_sink()
	if sink==null or not sink.active or sink.buffering or sink.reported_frames<=0:
		return false
	if sink.stream_generation==tv_previous_generation or sink.last_data_at<max(0,tv_audio_since):
		return false
	var age=OS.get_ticks_msec()-sink.last_data_at
	return age>=0 and age<=750

func _tv_playback_status():
	if not tv_playback_error.empty():return "error"
	if _tv_audio_ready():return "playing"
	if tv_audio_requested:return "waiting"
	if tv_queue_state=="paused":return "paused"
	if tv_queue_last_action in ["pause","stop","clear"]:return "idle"
	if tv_queue_state in ["playing","buffering"]:return "waiting"
	return "idle"

func _reset_tv_audio():
	tv_audio_requested=false
	tv_audio_since=-1
	tv_previous_generation=-1
	tv_playback_error=""
	if tv_audio_wait_timer!=null:tv_audio_wait_timer.stop()

func _watch_tv_audio(require_new_stream=false, start_timer=true):
	_reset_tv_audio()
	tv_queue_last_action=""
	tv_audio_requested=true
	tv_audio_since=OS.get_ticks_msec()
	var sink=_tv_sink()
	if require_new_stream and sink!=null and sink.active:
		tv_previous_generation=sink.stream_generation
	if start_timer and tv_audio_wait_timer!=null:tv_audio_wait_timer.start(10.0)
	if music_ui!=null and music_ui._tv_mode():music_ui.show_status("")

func _set_tv_playback_error(detail):
	_reset_tv_audio()
	tv_playback_error=detail
	if music_ui!=null and music_ui._tv_mode():music_ui.show_status(detail)

func _stop_sendspin_player():
	stream_warmup_budget.reset()
	if sendspin_facade!=null:
		_stop_audio()
		ma_panel.set_sendspin_status("idle","TV player stopped")

func _reveal_sendspin_pairing():
	if sendspin_facade==null:
		ma_panel.set_sendspin_status("idle","Connect this TV player first")
		return
	ma_panel.show_sendspin_token(sendspin_facade.reveal_pairing_token())

func _confirm_sendspin_pairing():
	if sendspin_facade==null or not is_instance_valid(sendspin_facade):
		ma_panel.set_sendspin_status("idle","Connect playback before finishing pairing")
		return false
	if sendspin_facade.confirm_pairing()==true:return true
	# A repeated Finish is not a new connection and must not erase a valid route.
	ma_panel.sendspin_details.text="No new pairing confirmation is waiting. Playback state is unchanged."
	return false

func _sendspin_command(command,argument=null):
	return _request_tv_queue(command,argument)
func _queue_read_in_progress():
	return tv_queue_request!=null and is_instance_valid(tv_queue_request) and tv_queue_request.get("action") in ["read","items"]
func _web_queue_busy():
	return web_remote!=null and web_remote.music_api!=null and web_remote.music_api.mutation_busy()

func _queue_controls_available():
	# A metadata refresh must not make an explicit transport button briefly
	# unavailable every few seconds. Only read-only requests are preemptible.
	return not _web_queue_busy() and not _sendspin_controls().empty() and (tv_queue_request==null or _queue_read_in_progress()) and ma_panel!=null and not ma_panel.library_disconnected and ma_panel.sendspin_paired and not ma_panel.endpoint_edit.text.strip_edges().empty() and (not _library_credential(false).empty() or Engine.has_singleton("ShieldAmpTokenStore"))
func _request_tv_queue(command,argument=null):
	if command in ["pause","stop","clear"]:_cancel_requested_play()
	if not command in ["play","pause","stop","next","previous","read","items","seek_backward","seek_forward","remove","clear"]:
		return false
	if tv_queue_request!=null:
		# A preview opened during another request waits for it. Bind it to
		# this session so it cannot query a replacement player's queue.
		if command=="items" and not _sendspin_controls().empty():
			tv_queue_pending_session=sendspin_facade
			return true
		if not command in ["read","items"] and _queue_read_in_progress():
			var previous=tv_queue_request
			tv_queue_request=null
			if music_ui!=null and music_ui.queue_view=="tv" and music_ui.queue_drawer.visible:
				tv_queue_pending_session=sendspin_facade
			previous.cancel()
			previous.queue_free()
		else:
			# Never cancel, queue or automatically repeat a mutation whose
			# outcome may already be unknown to this client.
			if not command in ["read","items"] and music_ui!=null:
				music_ui.show_status("PLAYBACK REQUEST IN PROGRESS / WAIT FOR RESULT")
			return false
	if not _queue_controls_available():
		if not command in ["read","items"] and music_ui!=null: music_ui.show_status("QUEUE UNAVAILABLE / CONNECT MUSIC ASSISTANT")
		return false
	var credential=_library_credential()
	if credential.empty():
		if not command in ["read","items"] and music_ui!=null: music_ui.show_status("QUEUE NEEDS MUSIC ASSISTANT ACCESS")
		return false
	var operation=load("res://scripts/MATvQueueRequest.gd").new()
	add_child(operation)
	tv_queue_request=operation
	operation.connect("completed",self,"_on_tv_queue_result",[operation])
	var started=operation.begin(self,sendspin_facade,ma_panel.endpoint_edit.text,credential,ma_panel.lan_trust.pressed,command,argument)
	credential=""
	if not started and tv_queue_request==operation:
		tv_queue_request=null
		operation.queue_free()
		if not command in ["read","items"] and music_ui!=null: music_ui.show_status("QUEUE REQUEST COULD NOT START")
	if started and command in ["play","next","previous"] and not recovery_restarting and not _recovery_binding().empty():
		_arm_playback_recovery()
	if started and not command in ["read","items"] and music_ui!=null:
		if command in ["play","next","previous","seek_backward","seek_forward"]:_prepare_stream_visuals()
		elif command in ["pause","stop","clear"]:stream_warmup_budget.reset()
		music_ui.show_status("VERIFYING TV ROUTE")
		if music_ui.queue_view=="tv" and music_ui.queue_drawer.visible:
			tv_queue_pending_session=sendspin_facade
		if command in ["play","next","previous"]:
			music_ui.set_playback_context("ma")
			_watch_tv_audio(command!="play")
			music_ui._refresh_tv_presentation()
			if tv_queue_timer!=null: tv_queue_timer.start(0.25)
	return started
func _on_tv_queue_result(ok,action,snapshot,detail,operation):
	if operation!=tv_queue_request: return
	if not ok:
		if not action in ["read","items"]:playback_recovery.cancel()
		stream_warmup_budget.reset()
		if action in ["play","next","previous"]:_set_tv_playback_error(detail)
	var empty_queue=not ok and operation.get("failure_reason")=="queue_empty"
	var auth_rejected=not ok and operation.get("failure_reason")=="auth_failed"
	tv_queue_request=null
	operation.queue_free()
	if empty_queue and music_ui!=null:
		_reset_tv_audio()
		music_ui._open_library()
		music_ui.show_status("YOUR QUEUE IS EMPTY / CHOOSE MUSIC")
		return
	if auth_rejected:
		tv_queue_pending_session=null
		ma_panel._disconnect_library("auth_failed")
		if music_ui!=null:music_ui.show_status("LIBRARY ACCESS REJECTED / CONNECT LIBRARY")
		return
	var pending_session=tv_queue_pending_session
	tv_queue_pending_session=null
	if pending_session!=null:
		call_deferred("_start_pending_tv_preview",pending_session)
	if music_ui==null: return
	if ok and action in ["seek_backward","seek_forward","next","previous","stop","clear"]:
		if sendspin_facade!=null and sendspin_facade.runtime!=null and sendspin_facade.runtime.has_method("invalidate_buffer_measurement"):
			sendspin_facade.runtime.invalidate_buffer_measurement()
		music_ui._clear_buffer_progress()
	if ok and action=="read":
		tv_queue_timing=snapshot.duplicate(true)
		tv_queue_timing_read_at=OS.get_ticks_msec()
	if action=="read":
		if ok:
			tv_queue_state=str(snapshot.get("state",""))
			if tv_queue_state in ["paused","idle","stopped"]:
				tv_queue_last_action=""
			music_ui.show_tv_queue_snapshot(snapshot)
		elif music_ui.tv_queue_label!=null and music_ui._tv_mode():
			music_ui.tv_queue_label.text="QUEUE INFO UNAVAILABLE"
			music_ui.tv_queue_label.show()
	elif action=="items":
		music_ui.show_tv_queue_items(snapshot.get("items",[]) if ok else [],ok,detail)
	elif ok:
		tv_queue_last_action=action
		if action in ["pause","stop","clear"]:_reset_tv_audio()
		if action in ["next","previous"]:
			music_ui.now_title.text="Changing track…"
			music_ui._set_fullscreen_track("Changing track…","","MUSIC ASSISTANT")
			if music_ui.track_hero!=null: music_ui.track_hero.set_track(music_ui.artwork.texture,"Changing track…","MUSIC ASSISTANT")
			music_ui.tv_queue_label.hide()
		if not action in ["play","next","previous"]:music_ui.show_status("QUEUE REQUEST ACCEPTED / POSITION UNVERIFIED")
		if tv_queue_timer!=null: tv_queue_timer.start(0.25)
	else:
		music_ui.show_status(detail)
func _start_pending_tv_preview(session):
	if session!=sendspin_facade or music_ui==null or not is_instance_valid(music_ui): return
	if music_ui.queue_view!="tv" or not music_ui.queue_drawer.visible: return
	if not _request_tv_queue("items"):
		music_ui.show_tv_queue_items([],false,"QUEUE UNAVAILABLE / RETRY")

func _tv_seek_available():
	var age=OS.get_ticks_msec()-tv_queue_timing_read_at
	return _queue_controls_available() and age>=0 and age<=5000 and tv_queue_policy.seek_target(tv_queue_timing,0,OS.get_unix_time(),OS.get_ticks_msec())>=0

func _refresh_tv_queue():
	if tv_queue_timer!=null: tv_queue_timer.start(3.0)
	if sendspin_facade!=null and is_instance_valid(sendspin_facade): _request_tv_queue("read")
func _sendspin_controls():
	if sendspin_facade==null or not is_instance_valid(sendspin_facade) or sendspin_facade.runtime==null or not sendspin_facade.runtime.active or sendspin_facade.client==null: return {}
	var status=sendspin_facade.client.status()
	return status if typeof(status)==TYPE_DICTIONARY and typeof(status.get("paired"))==TYPE_BOOL and status["paired"] else {}

func _on_sendspin_play_here(item):
	# Main transport resumes its queue; Library Play deliberately inserts/plays
	# the selected media on the exact verified own output, preserving its tail.
	if typeof(item)!=TYPE_DICTIONARY or item.empty():return _sendspin_command("play")
	if ma_panel==null:return false
	if not _queue_controls_available() or str(_sendspin_controls().get("client_id",""))!=ma_panel.sendspin_player_id:
		ma_panel.sendspin_play_requested=false
		ma_panel.status_label.text="Playback changed. Reconnect this device; no play request sent."
		return false
	if tv_queue_request!=null:
		if not _queue_read_in_progress():return false
		var previous=tv_queue_request;tv_queue_request=null;previous.cancel();previous.queue_free()
	if not ma_panel.catalog.play_local_selection(ma_panel.sendspin_player_id,item):
		ma_panel.sendspin_play_requested=false
		return false
	_prepare_stream_visuals()
	if sendspin_facade.runtime.has_method("invalidate_buffer_measurement"):sendspin_facade.runtime.invalidate_buffer_measurement()
	music_ui.set_playback_context("ma")
	music_ui.invalidate_tv_queue()
	music_ui.now_title.text="Waiting for track information"
	music_ui._close_library()
	music_ui.play_button.grab_focus()
	_watch_tv_audio(true)
	if tv_queue_timer!=null:tv_queue_timer.start(0.25)
	return true

func _show_ma_catalog():
	if music_ui != null:
		page_scroller.hide()
		music_ui.show()
		music_ui._open_library()
	else:
		ma_panel.show()
	ma_panel.focus_entry()

func _on_ma_catalog_closed():
	# Disconnect revokes only this app's MA preview stream and in-memory bearer.
	if native_transport != null and native_transport.ma_preview_mode:
		_stop_audio()
	_hide_ma_catalog()

func _hide_ma_catalog():
	ma_panel.hide()
	if music_ui != null:
		music_ui._close_library()
	else:
		ma_button.grab_focus()

func _on_ma_preview(item):
	# Explicit user action, time-bound MA selection, short official preview only.
	# Full library track playback requires a separately supported playback session.
	if ma_panel == null or ma_panel.catalog == null or native_transport == null:
		return
	var catalog = ma_panel.catalog
	var selected = catalog.selection()
	if selected.empty() or selected.get("media_type") != "track":
		return
	if selected.get("item_id") != item.get("item_id") or selected.get("provider") != item.get("provider"):
		return
	if catalog.token.empty():
		return
	var preview_route = load("res://scripts/MAPreviewRoute.gd").new()
	var route = preview_route.prepare(selected, catalog.endpoint, catalog.trusted_private_http)
	if route.empty():
		if music_ui != null:
			music_ui.show_status("Cannot preview this track; unsafe or unavailable")
		return
	# Stop ONLY audio owned by this app; never change Music Assistant queues.
	_stop_all_music()
	analysis_owner = native_stream_engine
	native_transport.configure(native_stream_engine, route["origin"], catalog.trusted_private_http)
	if not native_transport.start_authorized_preview(route["url"], catalog.token):
		if music_ui != null:
			music_ui.show_status("MA preview unavailable; no playback started")
		return
	_reset_analysis()
	demo = false
	if music_ui != null:
		music_ui.show_ma_selection(route["track_name"], str(selected.get("artist", "")), str(selected.get("album", "")))
		music_ui.set_playback_context("preview")
		music_ui.source_label.text = "MUSIC ASSISTANT  •  SHORT PREVIEW"
		music_ui.show_status("MA SHORT PREVIEW / genuine audio, NOT full track")
		music_ui._close_library()

func _on_ma_selected(item):
	# MA catalog items are opaque IDs, NOT verified audio URLs.
	# Show library metadata, never silently control MA or fabricate a stream.
	title_label.text = "Selected collection item: " + str(item.get("name", ""))
	if music_ui != null:
		# Browsing must not replace the title of music that is still playing.
		var local_playing = offline_music != null and offline_music.is_playing()
		var stream_playing = native_stream_engine != null and analysis_owner == native_stream_engine and native_stream_engine.active
		var tv_playing = sendspin_facade != null and is_instance_valid(sendspin_facade) and sendspin_facade.runtime != null and sendspin_facade.runtime.active
		if local_playing or stream_playing or tv_playing:
			music_ui.show_status("CATALOG ITEM SELECTED / CURRENT MUSIC CONTINUES")
		else:
			music_ui.show_ma_selection(item.get("name", "Untitled"), str(item.get("artist", "")), str(item.get("album", "")))
	detail_label.text = "Collection selection only; no playback or queue change. Use an authorized playable URL separately."

func _apply_resolution_base():
	var desired = Vector2(min(1280.0, max(320.0, OS.window_size.x)), min(720.0, max(360.0, OS.window_size.y)))
	if desired != screen_base:
		screen_base = desired
		get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_2D, SceneTree.STRETCH_ASPECT_EXPAND, desired, 1.0)

func _responsive_catalog(parent):
	for child in parent.get_children():
		if child is Label:
			child.autowrap = true
		elif child is Button:
			child.clip_text = true
		_responsive_catalog(child)

func _seek_offline(delta):
	return offline_music.seek_relative(delta) if offline_music != null and (local_pcm == null or not local_pcm.active) else false

# Opt-in gesture commands share the visible transport callbacks. No independent
# queue/player route or automatic command is created by settings or polling.
func _build_gesture_settings(parent):
	webcam_gestures=CheckBox.new()
	webcam_gestures.text="Webcam gestures"
	webcam_gestures.hint_tooltip="Experimental webcam gestures. Off by default. Save Setup remembers this choice."
	webcam_gestures.rect_min_size.y=52
	parent.add_child(webcam_gestures)
	webcam_gestures.connect("toggled",self,"_set_webcam_gestures")
	_label(parent,"Cross arms to open 3D controls, lower your hands, then reach deliberately into a button. The camera measures screen-plane movement, not punch depth. Gestures are off by default; enabling them also enables Webcam. Menus pause recognition.",24)
	gesture_mode_choice=OptionButton.new()
	gesture_mode_choice.add_item("Crossed arms: 3D controls")
	gesture_mode_choice.add_item("Direct gestures: arm holds / waves / head shake")
	gesture_mode_choice.rect_min_size.y=60
	parent.add_child(gesture_mode_choice)
	gesture_mode_choice.connect("item_selected",self,"_set_gesture_mode")

	for action in gesture_policy.ACTIONS:
		gesture_mode_labels.append(_label(parent,{"previous":"Previous track","play_pause":"Play / Pause","next":"Next track"}[action]+" gesture",24))
		var choice=OptionButton.new()
		choice.clip_text=true
		for label in gesture_policy.LABELS:choice.add_item(label)
		choice.rect_min_size.y=48
		parent.add_child(choice)
		choice.select(gesture_policy.GESTURES.find(gesture_policy.bindings[action]))
		choice.hint_tooltip=choice.get_item_text(choice.selected)+"\n"+gesture_policy.recipe(gesture_policy.bindings[action])
		choice.connect("item_selected",self,"_select_gesture_binding",[action])
		gesture_choices[action]=choice
	gesture_status=_label(parent,"Gestures off",26)
	_button(parent,"RECENTER HEAD / LOOK FORWARD","_recenter_webcam_head")
	_button(parent,"TRY GESTURES / RETURN TO PLAYER","_try_webcam_controls")
func _restore_gesture_setup(setup):
	gesture_mode="direct" if setup.get_value("installation","webcam_gesture_mode","panel")=="direct" else "panel"
	gesture_mode_choice.select(1 if gesture_mode=="direct" else 0)
	var saved=setup.get_value("installation","webcam_gesture_bindings",gesture_policy.DEFAULTS)
	if typeof(saved)!=TYPE_DICTIONARY:saved=gesture_policy.DEFAULTS
	var wanted=setup.get_value("installation","webcam_gestures_enabled",false)
	if typeof(wanted)!=TYPE_BOOL:wanted=false
	if not gesture_policy.configure(wanted,saved):gesture_policy.configure(false,gesture_policy.DEFAULTS)
	webcam_gestures.set_pressed_no_signal(gesture_policy.enabled)
	_refresh_gesture_mode_controls()
	for action in gesture_policy.ACTIONS:
		gesture_choices[action].select(gesture_policy.GESTURES.find(gesture_policy.bindings[action]))
		gesture_choices[action].hint_tooltip=gesture_choices[action].get_item_text(gesture_choices[action].selected)+"\n"+gesture_policy.recipe(gesture_policy.bindings[action])
func _set_webcam_gestures(value):
	gesture_policy.configure(value,gesture_policy.bindings)
	body_control_policy.cancel()
	if value and pose_visual!=null and pose_visual.webcam_connected and pose_visual.mode=="off":pose_visual.set_mode("live")
	_refresh_pose_control_budget()
	_update_gesture_feedback()
func _try_webcam_controls():
	_set_webcam_gestures(true)
	_show_music_stage()
	music_ui._enter_fullscreen()
func _set_gesture_mode(index):
	gesture_mode="direct" if index==1 else "panel"
	gesture_policy.cancel()
	body_control_policy.cancel()
	_refresh_gesture_mode_controls()
	_update_gesture_feedback()
func _refresh_gesture_mode_controls():
	for label in gesture_mode_labels:label.visible=gesture_mode=="direct"
	for choice in gesture_choices.values():choice.visible=gesture_mode=="direct"
func _close_body_control_panel():
	body_control_policy.cancel("Controls closed / cross arms to reopen")
	_update_gesture_feedback()
func _perform_panel_action(action):
	if action=="close":
		_close_body_control_panel()
		return true
	if not _gesture_context_allowed():return false
	if action in gesture_policy.ACTIONS:return _perform_gesture_action(action)
	if action=="stop" and music_ui!=null and not music_ui.stop_button.disabled:
		music_ui.stop_button.emit_signal("pressed");return true
	return false
func _select_gesture_binding(index,action):
	if not action in gesture_policy.ACTIONS or index<0 or index>=gesture_policy.GESTURES.size():return false
	var proposed=gesture_policy.bindings.duplicate()
	proposed[action]=gesture_policy.GESTURES[index]
	if not gesture_policy.configure(gesture_policy.enabled,proposed):
		gesture_choices[action].select(gesture_policy.GESTURES.find(gesture_policy.bindings[action]))
		gesture_status.text="That gesture is assigned already. Choose Unassigned for its other action first."
		return false
	gesture_choices[action].hint_tooltip=gesture_policy.LABELS[index]+"\n"+gesture_policy.recipe(proposed[action])
	_update_gesture_feedback()
	return true
func _refresh_pose_control_budget():
	if pose_visual==null:return
	var hz=4 if visual_quality_level==2 else (2 if visual_quality_level==1 else 0)
	# Explicit controls remain available with VISUALS OFF. Only the existing
	# loopback landmark poll runs; avatar/FFT/background render budgets stay off.
	if gesture_policy.enabled and pose_visual.webcam_connected and pose_visual.mode=="live" and (app_has_focus or gesture_mode=="panel") and not app_is_paused:hz=4
	pose_visual.set_performance_budget(hz)
func _gesture_context_allowed():
	if not gesture_policy.enabled or (not app_has_focus and gesture_mode!="panel") or app_is_paused or pose_visual==null:return false
	if not pose_visual.webcam_connected or pose_visual.mode!="live" or not pose_visual.enabled:return false
	if music_ui==null or not music_ui.visible or not music_ui.root.is_visible_in_tree():return false
	if page_scroller!=null and page_scroller.is_visible_in_tree():return false
	if ma_panel!=null and ma_panel.is_visible_in_tree():return false
	if music_ui._active_drawer()!=null or preload("res://scripts/ModalFocus.gd").nested_popup(self):return false
	var focus=get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return false
	return true
func _on_gesture_tracking_lost(_reason):
	body_control_policy.cancel("Tracking interrupted / show shoulders and wrists")
	gesture_policy.cancel("Tracking interrupted / hold neutral to rearm" if gesture_policy.enabled else "Gestures off")
	_update_gesture_feedback()
func _on_gesture_sample(points,source_epoch,frame,captured_at):
	if gesture_mode=="panel":
		var action=body_control_policy.sample(OS.get_ticks_msec(),source_epoch,frame,captured_at,points,_gesture_context_allowed())
		if not action.empty():_perform_panel_action(action)
		_update_gesture_feedback()
		return
	var action=gesture_policy.sample(OS.get_ticks_msec(),source_epoch,frame,captured_at,points,_gesture_context_allowed())
	if not action.empty():_perform_gesture_action(action)
	_update_gesture_feedback()
func _perform_gesture_action(action):
	if not _gesture_context_allowed() or not action in gesture_policy.ACTIONS:return false
	var button=music_ui.previous_button if action=="previous" else music_ui.next_button
	if action=="play_pause":
		var playing=(_sendspin_fresh() or tv_queue_state=="playing") if music_ui._tv_mode() else offline_music.is_playing()
		button=music_ui.tv_pause_button if playing else music_ui.play_button
	if button==null or button.disabled:return false
	button.emit_signal("pressed")
	return true
func _recenter_webcam_head():
	if avatar_visual!=null:avatar_visual.recenter_head()
	gesture_policy.cancel("Look forward and lower your arms")
	gesture_feedback_presenter.reset()
	_update_gesture_feedback()
func _update_gesture_feedback():
	var raw=body_control_policy.feedback if gesture_mode=="panel" else gesture_policy.feedback
	if gesture_policy.enabled and not app_has_focus and gesture_mode!="panel":raw="Gestures paused / select the Kinegra Amp pane"
	var urgent=not gesture_policy.enabled or "accepted" in raw.to_lower() or (pose_visual!=null and not pose_visual.webcam_connected)
	if gesture_policy.enabled and pose_visual!=null and pose_visual.mode!="live":raw="Webcam is off / enable Webcam to use gestures"
	var shown=gesture_feedback_presenter.update(raw,OS.get_ticks_msec(),urgent)
	if body_control_panel!=null:body_control_panel.sync(body_control_policy)
	if gesture_status!=null:gesture_status.text=shown
	if music_ui!=null and music_ui.has_method("show_gesture_cues"):
		music_ui.show_gesture_cues(gesture_policy.enabled and pose_visual!=null and pose_visual.webcam_connected and pose_visual.mode=="live",gesture_policy.bindings if gesture_mode=="direct" else {},shown)

func _show_licenses():
	if music_ui != null: music_ui.show_licenses()


func _build_web_remote_settings(parent):
    web_remote_toggle=CheckBox.new()
    web_remote_toggle.text="Web remote (trusted LAN)"
    web_remote_toggle.rect_min_size.y=54
    parent.add_child(web_remote_toggle)
    web_remote_toggle.connect("toggled",self,"_set_web_remote")
    web_require_key=CheckBox.new()
    web_require_key.text="Require access key"
    web_require_key.rect_min_size.y=54
    parent.add_child(web_require_key)
    _label(parent,"Trusted LAN ranges: IPv4, CIDR or start-end; separate ranges with commas.")
    web_trusted_ranges=_edit(parent,"Example: 10.42.0.0/24, 192.168.1.20-192.168.1.40")
    _button(parent,"APPLY REMOTE ACCESS","_apply_web_access")
    _label(parent,"Disabling the key grants control to devices in these trusted ranges. Production requires a key by default.")
    web_remote_status=_label(parent,"Web remote is off.")
    web_remote_new_key=_button(parent,"NEW REMOTE ACCESS KEY","_rotate_web_remote_key")
    _label(parent,"Control Play, Pause, Previous, Next and Stop from a browser. Uses local HTTP while this app is running. Production starts off; development starts on. Your choice is remembered for each build type.")

func _start_web_remote():
    web_remote=preload("res://scripts/WebRemote.gd").new()
    add_child(web_remote)
    web_remote.connect("changed",self,"_sync_web_remote")
    web_remote.configure(self,web_remote.development_build(OS.has_feature("debug"),OS.has_feature("shieldamp_production")))
    _sync_web_remote()

func _set_web_remote(enabled):
    if web_remote!=null:web_remote.set_enabled(enabled)
    _sync_web_remote()

func _apply_web_access():
    if web_remote!=null:
        web_remote.set_access(web_require_key.pressed,web_trusted_ranges.text)
        _sync_web_remote()

func _rotate_web_remote_key():
    if web_remote!=null:web_remote.rotate_key()

func _sync_web_remote():
    if web_remote_toggle==null:return
    web_remote_toggle.set_pressed_no_signal(web_remote!=null and web_remote.server.is_listening())
    web_remote_status.text=web_remote.status if web_remote!=null else "Web remote is off."
    if web_remote!=null:
        web_require_key.set_pressed_no_signal(web_remote.require_key)
        if not web_trusted_ranges.has_focus():web_trusted_ranges.text=web_remote.trusted_ranges_text
    web_remote_new_key.disabled=web_remote==null or not web_remote.server.is_listening()

func web_remote_snapshot():
    if music_ui==null:return {"title":"", "source":"Kinegra Amp", "state":"starting"}
    var local=music_ui.playback_context=="offline"
    var state="playing" if local and offline_music.is_playing() else "paused or stopped"
    if not local:state=_tv_playback_status()
    var detail=music_ui.status_label.text if local or tv_playback_error.empty() else tv_playback_error
    return {"title":music_ui.now_title.text.substr(0,512),"source":"Offline library" if local else "Music Assistant","state":state,"detail":detail.substr(0,160)}

func web_remote_control(action):
    if music_ui==null or not action in ["play","pause","previous","next","stop"]:return false
    if action=="play":
        if music_ui._tv_mode():return _play_music_assistant()
        if not offline_music.is_playing():_play_offline_music()
    elif action=="pause":music_ui._pause_tv()
    elif action=="previous":music_ui._previous()
    elif action=="next":music_ui._next()
    elif action=="stop":music_ui._stop()
    return true


func web_remote_diagnostics():
    var runtime=sendspin_facade.runtime if sendspin_facade!=null else null
    var sink=sendspin_facade.sink if sendspin_facade!=null else null
    var native=sendspin_facade.client.status() if sendspin_facade!=null and sendspin_facade.client!=null else {}
    var clean={}
    for field in ["active","paired","generation","queued_bytes","startup_buffering","sample_rate","channels","bits_per_sample"]:
        if typeof(native.get(field)) in [TYPE_BOOL,TYPE_INT,TYPE_REAL]:clean[field]=native[field]
    return {"connection":ma_panel.playback_state if ma_panel!=null else "none","detail":playback_detail,"runtime_active":runtime!=null and runtime.active,"runtime_state":runtime.state if runtime!=null else "none","sink_active":sink!=null and sink.active,"pcm_age_ms":OS.get_ticks_msec()-sink.last_pcm_at if sink!=null and sink.last_pcm_at>=0 else -1,"native":clean,"pending_resume":not pending_queue_resume.empty(),"queue_action":tv_queue_request.action if tv_queue_request!=null else "none","ui_status":music_ui.status_label.text if music_ui!=null else "starting"}


func _build_offline_source_settings(parent):
	_label(parent,"OFFLINE COPYING / OPTIONAL LOCAL-FILE SOURCE")
	_label(parent,"Save the current and upcoming local tracks. Set up the included file-source helper on your music host; streaming subscriptions are unsupported.")
	offline_source_edit=_edit(parent,"Source: http://192.168.1.30:8766")
	offline_source_key_edit=_edit(parent,"File-source access key",true)
	var saved=ConfigFile.new()
	if saved.load(offline_save.config_path)==OK:offline_source_edit.text=saved.get_value("source","origin","")
	_button(parent,"SAVE LOCAL-FILE SOURCE","_save_offline_source")
	offline_source_status=_label(parent,"Source configured" if offline_save.configured() else "Not configured / USB import remains available")

func _save_offline_source():
	var ok=offline_save.configure(offline_source_edit.text.strip_edges(),offline_source_key_edit.text.strip_edges())
	offline_source_key_edit.text=""
	offline_source_status.text="Source saved / trusted private LAN HTTP" if ok else "Enter a private HTTP origin and the helper's key; no setting changed"


func _recovery_binding():
	if ma_panel==null or ma_panel.library_disconnected or app_is_paused or music_ui==null or not music_ui._tv_mode():return ""
	return ma_panel.endpoint_edit.text.strip_edges()+"|"+ma_panel.sendspin_endpoint.text.strip_edges()+"|"+(ma_panel._playback_client_id() if not ma_panel._playback_client_id().empty() else recovery_client_id)

func _update_playback_recovery():
	if not playback_recovery.armed:return
	var now=OS.get_ticks_msec()
	var data_at=-1
	var buffering=true
	if sendspin_facade!=null and is_instance_valid(sendspin_facade) and sendspin_facade.sink!=null:
		data_at=sendspin_facade.sink.last_data_at
		buffering=sendspin_facade.sink.buffering
	var fresh_queue=tv_queue_timing_read_at>=0 and now-tv_queue_timing_read_at<10000 and now-playback_recovery.since>5000
	var busy=not pending_queue_resume.empty() or tv_queue_request!=null or _web_queue_busy() or ma_panel.catalog.request_node!=null or ma_panel.playback_state=="connecting"
	var action=playback_recovery.step(now,_recovery_binding(),data_at,buffering,busy,tv_queue_state,fresh_queue)
	if action=="exhausted":
		_set_tv_playback_error("No audio received. Retry Play or use Offline Library.")
	elif action=="reconnect":
		print("SHIELDAMP_RECOVERY attempt=",playback_recovery.attempts)
		music_ui.show_status("Audio stalled / reconnecting and refilling…")
		recovery_restarting=true
		_stop_audio()
		_play_music_assistant()
		recovery_restarting=false

func _arm_playback_recovery():
	if recovery_restarting:return
	recovery_client_id=ma_panel._playback_client_id()
	if not recovery_client_id.empty():playback_recovery.play_intent(_recovery_binding(),OS.get_ticks_msec())

func _recovery_catalog_state(state,detail):
	if state=="play_requested":_arm_playback_recovery()
	elif state in ["auth_expired","permission_denied"]:playback_recovery.cancel()
	elif ma_panel.catalog.request_context.get("kind")=="play" and state in ["command_failed","disconnected","malformed_reply","stale_reply"]:
		playback_recovery.cancel()
		_set_tv_playback_error(detail)
