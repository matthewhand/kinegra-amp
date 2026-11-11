extends CanvasLayer
# Music-first TV UI. Controller D-pad focus is explicit; visualizer stays full-screen.
# No automatic music, oscillator, synthetic audio or external service writes.
const TransportStyle=preload("res://scripts/TransportStyle.gd")
const ModalFocus = preload("res://scripts/ModalFocus.gd")
var _drawer_focus_owner = null
var _restoring_drawer_focus = false
var offline_play_button = null
var app = null
var fullscreen_visual = false
var fullscreen_button = null
var fullscreen_help = null
var fullscreen_track = null
var fullscreen_track_title = null
var fullscreen_track_artist = null
var fullscreen_album = null
var fullscreen_playback = null
var fullscreen_art = null
var fullscreen_cover = null # Kept null: one morphing card owns fullscreen art.
var cover_tween=null
var playback_notice=preload("res://scripts/PlaybackNotice.gd").new()
var cover_morph=0.0
var cover_target=-1
var fullscreen_card_frame=null
var stage_cover=null
var portrait_layout=false
var fullscreen_help_until = 0
var fullscreen_art_caption=null
var artwork_controller=null
var _artwork_context=""
var _artwork_binding=""
var _artwork_auth_failed_binding=""
var _artwork_descriptor={}
var _tv_snapshot={}
var _tv_snapshot_at=-1
var _tv_snapshot_session=null
var _tv_display={}
var _tv_presentation=preload("res://scripts/MAPresentationState.gd").new()
var header_card = null
var player_card = null
var root = null
var ma_drawer = null
var _queue_return_to_library=false
var _accept_held={}
var _back_held={}
var library_config_popup=null
var _configuration_completed_close=false
var _back_input_at=-10000
var _back_native_at=-10000
var offline_drawer = null
var queue_drawer = null
var queue_actions_grid=null
var queue_button = null
var queue_close_button = null
var queue_items = []
var queue_selected = 0
var body_button = null
var avatar_button = null
var queue_local_first=0
var queue_previous_page=null
var queue_next_page=null
var queue_download_button=null
var queue_play_saved_button=null
var queue_save_label = null
var queue_empty_label = null
var queue_header_label = null
var queue_selected_label=null
var item_title_dialog=null
var queue_help_label = null
var queue_toggle_button = null
var queue_refresh_button = null
var queue_view = "local"
# Playback intent is explicit state; labels never choose an audio backend.
var playback_context = "offline"
var ui_memory=preload("res://scripts/MusicUiMemory.gd").new()
var _startup_restored=false
var _memory_save_timer=null
var _memory_restore_location={}
var _memory_restore_origin=""
var _memory_page_generation=-1
var _restoring_memory_selection=false
var _offline_location_seen=false
var _tv_queue_selection_id=""
var _tv_queue_selection_binding=""
var _tv_queue_rows_binding=""
var _queue_focus_after_read=false
var playlist_context=preload("res://scripts/PlaylistContext.gd").new()
var tv_queue_items = []
var tv_queue_rows=[]
var tv_clear_dialog=null
var tv_clear_session=null
var tv_clear_client=""
var tv_queue_preview_status = ""
var queue_up_button = null
var queue_down_button = null
var queue_remove_button = null
var queue_clear_button = null
var offline_button = null
var offline_mix_button = null
var offline_favorite_button = null
var offline_summary = null
var offline_selected_label = null
var offline_heading = null
var _stage_font = null
var _text_labels = []
var _large_text_enabled = false
var legal_dialog = null
var offline_queue_button = null
var offline_remove_button = null
var offline_item_buttons = [] # Legacy public list; dynamic rows use ItemList.
var offline_list = null
var offline_scroll = null
var offline_page_label = null
var offline_previous_page = null
var offline_next_page = null
var offline_import_button = null
var offline_cancel_import_button = null
var offline_import_status = null
var offline_import = null
var _offline_selected = 0
var _offline_page = 0
var _offline_delete_index = -1
var _offline_page_indices = []
const OFFLINE_PAGE_SIZE = 25
var now_title = null
var source_label = null
var status_label = null
var play_button = null
var previous_button = null
var next_button = null
var stop_button = null
var tv_pause_button = null
var gesture_cues={}
var gesture_fullscreen_feedback=null
var library_button = null
var settings_button = null
var home_button = null
var volume_slider = null
var volume_feedback = null
var playlist_button = null
var favorite_button = null
var repeat_button = null
var shuffle_button = null
var preset_button = null
var sensitivity_button = null
var artwork = null
var artwork_caption = null
var playback_progress = null
var buffered_progress = null
var progress_stack = null
var buffer_label = null
const BufferPresentation=preload("res://scripts/PlaybackBufferPresentation.gd")
var rewind_button = null
var forward_button = null
var clock_label = null
var timeline_row = null
var options_grid = null
var volume_tag = null
var compact_layout = false
var header_grid = null
var header_emblem = null
var header_brand=null
var visuals_button=null
var transport_grid = null
var track_row = null
var tv_queue_label = null
var _progress_elapsed = 0.0
var track_hero = null
var sample_remove_dialog = null
const TRACK_COVERS = []

const INK = Color(0.025, 0.038, 0.062, 0.91)
const INK_SOLID = Color(0.035, 0.055, 0.082, 0.98)
const EDGE = Color(0.32, 0.53, 0.60, 0.45)
const WHITE = Color(0.93, 0.96, 0.97, 1.0)
const MUTED = Color(0.63, 0.72, 0.77, 1.0)
const TEAL = Color(0.23, 0.93, 0.79, 1.0)
const WARM = Color(0.96, 0.69, 0.37, 1.0)

func _box(color, border, radius=16):
    var style = StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    return style

func _text(parent, value, size=22, color=WHITE):
    var result = Label.new()
    result.text = value
    result.hint_tooltip = value
    result.add_color_override("font_color", color)
    var text_font = DynamicFont.new()
    text_font.font_data = load("res://assets/fonts/DejaVuSans.ttf")
    text_font.size = size
    result.add_font_override("font", text_font)
    result.set_meta("tv_base_font_size", size)
    _text_labels.append(result)
    result.clip_text = true
    result.rect_min_size.y = max(36, size + 12)
    parent.add_child(result)
    return result

func _action(parent, value, method, primary=false):
    var button = Button.new()
    button.text = value
    # Ensure oversized localized/favourite labels never paint over neighbours.
    # Tooltip retains the unabridged label for accessibility inspection.
    button.clip_text = true
    button.add_constant_override("hseparation",8)
    button.hint_tooltip = value
    button.focus_mode = Control.FOCUS_ALL
    button.rect_min_size = Vector2(142 if primary else 104, 66)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_color_override("font_color", Color(0.04, 0.10, 0.14) if primary else WHITE)
    button.add_color_override("font_color_hover", WHITE)
    button.add_stylebox_override("normal", _box(TEAL if primary else INK_SOLID, EDGE, 12))
    button.add_stylebox_override("hover", _box(Color(0.15, 0.37, 0.42, 0.98), TEAL, 12))
    button.add_stylebox_override("pressed", _box(Color(0.10, 0.28, 0.32, 1), TEAL, 12))
    var focus = _box(Color(0.12, 0.24, 0.29, 0.98), WARM, 12)
    focus.set_border_width_all(4)
    button.add_stylebox_override("focus", focus)
    parent.add_child(button)
    button.connect("pressed", self, method)
    return button

func _card(parent, modal=false):
    var result = PanelContainer.new()
    if modal:
        result.set_as_toplevel(true)
    result.add_stylebox_override("panel", _box(INK, EDGE))
    parent.add_child(result)
    return result

func _inside(parent, horizontal=22, vertical=16):
    var margins = MarginContainer.new()
    for key in ["left", "right"]:
        margins.add_constant_override("margin_" + key, horizontal)
    for key in ["top", "bottom"]:
        margins.add_constant_override("margin_" + key, vertical)
    parent.add_child(margins)
    return margins

func _ready():
    app = get_parent()
    ui_memory.load_state()
    _memory_save_timer=Timer.new()
    _memory_save_timer.one_shot=true
    _memory_save_timer.wait_time=0.25
    add_child(_memory_save_timer)
    _memory_save_timer.connect("timeout",ui_memory,"save")
    artwork_controller=load("res://scripts/MAArtworkController.gd").new()
    add_child(artwork_controller)
    artwork_controller.connect("artwork_ready",self,"_artwork_ready")
    artwork_controller.connect("authorization_failed",self,"_art_authorization_failed")
    root = Control.new()
    root.name = "MusicFirstOverlay"
    root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var stage_theme = Theme.new()
    var stage_font = DynamicFont.new()
    stage_font.font_data = load("res://assets/fonts/DejaVuSans.ttf")
    stage_font.size = 19
    stage_theme.default_font = stage_font
    root.theme = stage_theme
    _stage_font = stage_font
    add_child(root)
    root.connect("resized", self, "_apply_tv_typography")
    get_viewport().connect("gui_focus_changed",self,"_drawer_focus_changed")

    var top = _card(root)
    top.name = "MusicAssistantFirstHeader"
    header_card = top
    top.anchor_left = 0.035
    top.anchor_right = 0.965
    top.anchor_top = 0.035
    top.anchor_bottom = 0.035
    top.margin_top = 0
    top.margin_bottom = 100
    var top_inside = _inside(top, 22, 12)
    var top_row = GridContainer.new()
    header_grid=top_row
    top_row.columns=7
    top_row.add_constant_override("hseparation", 8)
    top_inside.add_child(top_row)
    var emblem = TextureRect.new()
    header_emblem=emblem
    emblem.name = "KinegraAmpEmblem"
    emblem.texture = load("res://assets/branding/icon_192.png")
    emblem.rect_min_size = Vector2(66, 66)
    emblem.expand = true
    emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top_row.add_child(emblem)
    var brand = _text(top_row, "Kinegra Amp", 26, WHITE)
    brand.name = "KinegraAmpTitle"
    brand.clip_text = false
    brand.valign = Label.VALIGN_CENTER
    brand.rect_min_size.y = 66
    brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header_brand = brand
    library_button = _action(top_row, "MUSIC ASSISTANT", "_open_library", true)
    offline_button = _action(top_row, "OFFLINE LIBRARY", "_open_offline_collection")
    queue_button = _action(top_row, "QUEUE", "_open_queue")
    fullscreen_button = _action(top_row, "FULLSCREEN", "_enter_fullscreen")
    visuals_button=_action(top_row,"VISUALS: ON","_toggle_visuals")
    settings_button = _action(top_row, "SETTINGS", "_advanced")
    sync_visuals_control()

    track_hero = load("res://scripts/TrackHero.gd").new()
    track_hero.name = "NowPlayingTrackHero"
    root.add_child(track_hero)
    track_hero.anchor_left = 0.12
    track_hero.anchor_right = 0.88
    track_hero.anchor_top = 0.17
    track_hero.anchor_bottom = 0.51

    var bottom = _card(root)
    bottom.name = "NowPlayingDock"
    player_card = bottom
    bottom.anchor_left = 0.035
    bottom.anchor_right = 0.965
    bottom.anchor_top = 0.54
    bottom.anchor_bottom = 0.965
    var dock = _inside(bottom, 24, 14)
    var stack = VBoxContainer.new()
    stack.add_constant_override("separation", 8)
    dock.add_child(stack)
    var now_row = GridContainer.new()
    track_row=now_row
    now_row.columns=3
    stack.add_child(now_row)
    # Original project art, explicitly marked as branding rather
    # than pretending it is provider-supplied album cover artwork.
    var art_col = VBoxContainer.new()
    art_col.rect_min_size.x = 76
    now_row.add_child(art_col)
    artwork = TextureRect.new()
    artwork.name = "OriginalBrandArtwork"
    artwork.texture = load("res://assets/branding/icon_192.png")
    artwork.rect_min_size = Vector2(64, 64)
    artwork.expand = true
    artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_col.add_child(artwork)
    artwork_caption = _text(art_col, "BRAND ART", 14, MUTED)
    artwork_caption.rect_min_size.y = 22
    var title_col = VBoxContainer.new()
    title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    now_row.add_child(title_col)
    source_label = _text(title_col, "MUSIC ASSISTANT  •  CHOOSE MUSIC", 17, TEAL)
    now_title = _text(title_col, "Your music. Your visuals.", 27, WHITE)
    tv_queue_label = _text(title_col, "", 15, MUTED)
    tv_queue_label.clip_text=true
    tv_queue_label.hide()
    status_label = _text(now_row, "READY  •  SILENT UNTIL PLAY", 17, MUTED)
    var controls = GridContainer.new()
    transport_grid=controls
    controls.columns=5
    controls.add_constant_override("separation", 12)
    stack.add_child(controls)
    play_button = _action(controls, "PLAY", "_toggle", true)
    previous_button = _action(controls, "PREVIOUS", "_previous")
    tv_pause_button = _action(controls, "PAUSE", "_pause_tv")
    play_button.icon=load("res://assets/icons/transport-play.svg")
    previous_button.icon=load("res://assets/icons/transport-previous.svg")
    tv_pause_button.icon=load("res://assets/icons/transport-pause.svg")
    next_button = _action(controls, "NEXT", "_next")
    stop_button = _action(controls, "STOP", "_stop")
    next_button.icon=load("res://assets/icons/transport-next.svg")
    stop_button.icon=load("res://assets/icons/transport-stop.svg")
    TransportStyle.apply(play_button,false)
    _build_gesture_cues(controls,stack)
    # Second row: local-only collection/preset controls. Nothing contacts MA.
    var options = GridContainer.new()
    options_grid=options
    options.columns=8
    options.add_constant_override("hseparation", 10)
    options.add_constant_override("vseparation", 8)
    stack.add_child(options)
    playlist_button = _action(options, "MIX: ALL", "_cycle_playlist")
    favorite_button = _action(options, "SAVE FAV", "_toggle_favorite")
    repeat_button = _action(options, "REPEAT: ALL", "_cycle_repeat")
    shuffle_button = _action(options, "SHUFFLE: OFF", "_toggle_shuffle")
    preset_button = _action(options, "SCENE: HORIZON", "_cycle_preset")
    sensitivity_button = _action(options, "SENS: NORMAL", "_cycle_sensitivity")
    sensitivity_button.hide() # Music reactivity now lives in Settings.
    body_button = _action(options, "WEBCAM: OFF", "_toggle_body")
    body_button.hide()
    app.pose_visual.connect("webcam_changed",self,"_webcam_changed")
    avatar_button = _action(options, "AVATAR: NEON", "_cycle_avatar")
    avatar_button.hide()
    app.pose_visual.connect("status_changed",self,"_body_status")
    for option in [playlist_button, favorite_button, repeat_button, shuffle_button, preset_button, sensitivity_button, body_button, avatar_button]:
        option.rect_min_size.y = 50

    var timeline = HBoxContainer.new()
    timeline_row=timeline
    timeline.add_constant_override("separation", 12)
    stack.add_child(timeline)
    rewind_button = _action(timeline, "REW -10s", "_seek_backward")
    progress_stack=Control.new()
    progress_stack.rect_min_size=Vector2(250,24)
    progress_stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    progress_stack.size_flags_vertical=Control.SIZE_SHRINK_CENTER
    timeline.add_child(progress_stack)
    buffered_progress=ProgressBar.new()
    buffered_progress.name="LocallyBufferedAudio"
    progress_stack.add_child(buffered_progress)
    buffered_progress.set_anchors_and_margins_preset(Control.PRESET_WIDE)
    buffered_progress.percent_visible=false
    buffered_progress.step=0.001
    buffered_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE
    buffered_progress.add_stylebox_override("bg",_box(Color(0.04,0.08,0.11,0.65),Color(0,0,0,0),4))
    buffered_progress.add_stylebox_override("fg",_box(Color(0.25,0.42,0.50,0.65),Color(0,0,0,0),4))
    playback_progress=ProgressBar.new()
    playback_progress.name="PrivateOfflineProgress"
    progress_stack.add_child(playback_progress)
    playback_progress.set_anchors_and_margins_preset(Control.PRESET_WIDE)
    playback_progress.percent_visible=false
    playback_progress.step=0.001
    playback_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE
    playback_progress.add_stylebox_override("bg",StyleBoxEmpty.new())
    playback_progress.add_stylebox_override("fg",_box(TEAL,Color(0,0,0,0),4))
    forward_button = _action(timeline, "FWD +10s", "_seek_forward")
    rewind_button.rect_min_size.y = 50
    forward_button.rect_min_size.y = 50
    rewind_button.focus_neighbour_right = rewind_button.get_path_to(forward_button)
    forward_button.focus_neighbour_left = forward_button.get_path_to(rewind_button)
    var timeline_labels=VBoxContainer.new()
    timeline_labels.size_flags_vertical=Control.SIZE_SHRINK_CENTER
    timeline.add_child(timeline_labels)
    clock_label = _text(timeline_labels, "00:00 / 00:00", 15, MUTED)
    buffer_label=_text(timeline_labels,"",12,MUTED)
    buffer_label.hint_tooltip="Audio already queued locally. Excludes additional SDK/server buffering; not an offline download."
    buffer_label.hide()
    clock_label.rect_min_size.x = 158
    clock_label.size_flags_horizontal = Control.SIZE_SHRINK_END
    set_process(true)

    # A separate offline-only collection browser: never reuses MA credentials,
    # catalogue requests or preview callbacks. Opening and selecting are silent.
    offline_drawer = _card(root, true)
    offline_drawer.name = "PrivateOfflineCollectionDrawer"
    offline_drawer.anchor_left = 0.16
    offline_drawer.anchor_right = 0.84
    offline_drawer.anchor_top = 0.12
    offline_drawer.anchor_bottom = 0.90
    offline_drawer.add_stylebox_override("panel", _box(INK_SOLID, TEAL, 18))
    var offline_outer = _inside(offline_drawer, 16, 12)
    offline_scroll = ScrollContainer.new()
    offline_scroll.name = "OfflineLibraryScroll"
    offline_scroll.scroll_horizontal_enabled = false
    offline_scroll.follow_focus = true
    offline_outer.add_child(offline_scroll)
    var offline_stack = VBoxContainer.new()
    offline_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    offline_stack.add_constant_override("separation", 8)
    offline_scroll.add_child(offline_stack)
    offline_heading = _text(offline_stack, "OFFLINE LIBRARY", 22)
    _text(offline_stack, "Select silently. PLAY starts the selected track.", 16, MUTED)
    offline_mix_button = _action(offline_stack, "MIX: ALL TRACKS", "_cycle_offline_collection")
    offline_mix_button.rect_min_size.y = 48
    offline_summary = _text(offline_stack, "LOCAL TRACKS / NO AUTOPLAY", 17, TEAL)
    offline_summary.autowrap = true
    offline_selected_label = _text(offline_stack, "SELECT A TRACK", 20, WHITE)
    offline_list = ItemList.new()
    offline_list.name = "OfflineTrackList"
    offline_list.rect_min_size.y = 180
    offline_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    offline_list.focus_mode = Control.FOCUS_ALL
    offline_list.select_mode = ItemList.SELECT_SINGLE
    offline_list.allow_reselect = true
    offline_list.add_constant_override("vseparation", 12)
    offline_list.add_stylebox_override("bg",_box(INK_SOLID,EDGE,8))
    offline_list.add_stylebox_override("selected",_box(Color(0.08,0.26,0.29),TEAL,6))
    offline_list.add_stylebox_override("selected_focus",_box(Color(0.08,0.26,0.29),WARM,6))
    offline_list.add_color_override("font_color",WHITE)
    offline_list.add_color_override("font_color_selected",WHITE)
    offline_stack.add_child(offline_list)
    offline_list.connect("item_selected",self,"_offline_item_selected")
    offline_list.connect("item_activated",self,"_offline_item_activated")
    var page_row = HBoxContainer.new()
    offline_stack.add_child(page_row)
    offline_previous_page = _action(page_row,"PREVIOUS PAGE","_offline_page_previous")
    offline_previous_page.rect_min_size.y = 46
    offline_page_label = _text(page_row,"PAGE 1 / 1",16,MUTED)
    offline_next_page = _action(page_row,"NEXT PAGE","_offline_page_next")
    offline_next_page.rect_min_size.y = 46
    var offline_footer = GridContainer.new()
    offline_footer.columns = 3
    offline_footer.add_constant_override("hseparation", 8)
    offline_footer.add_constant_override("vseparation", 8)
    offline_stack.add_child(offline_footer)
    offline_play_button = _action(offline_footer,"PLAY","_play_cued_from_drawer",true)
    offline_queue_button = _action(offline_footer,"ADD TO QUEUE","_queue_selected_offline")
    _action(offline_footer,"CLOSE","_close_offline_collection")
    offline_favorite_button = _action(offline_footer,"SAVE FAV","_toggle_offline_drawer_favorite")
    offline_remove_button = _action(offline_footer,"DELETE COPY…","_confirm_remove_sample")
    var restore_button = _action(offline_footer,"RESTORE","_restore_samples")
    restore_button.visible = not app.offline_music.SOURCES.empty()
    restore_button.hint_tooltip = "Restore the bundled sample tracks. Imported files remain unchanged."
    offline_import_button = _action(offline_stack,"IMPORT FROM USB / INTERNAL STORAGE","_begin_offline_import")
    offline_import_button.hint_tooltip = "Choose MP3 / Ogg files. Copies stay in this app; USB originals are untouched."
    offline_cancel_import_button = _action(offline_stack,"CANCEL IMPORT","_cancel_offline_import")
    offline_import_status = _text(offline_stack,"MP3 / OGG • COPIES STAY ON THIS DEVICE",16,MUTED)
    offline_import_status.autowrap = true
    offline_import_status.rect_min_size.y = 64
    offline_import = preload("res://scripts/OfflineImportSession.gd").new()
    offline_import.music = app.offline_music
    offline_import.connect("status_changed",self,"_offline_import_changed")
    add_child(offline_import)
    sample_remove_dialog = ConfirmationDialog.new()
    sample_remove_dialog.window_title = "Delete device copy?"
    sample_remove_dialog.dialog_text = "Delete only this app's copy? USB originals stay unchanged. Imported tracks can be imported again."
    sample_remove_dialog.get_ok().text = "DELETE DEVICE COPY"
    root.add_child(sample_remove_dialog)
    sample_remove_dialog.connect("confirmed",self,"_remove_selected_sample")
    var offline_focus_controls = []
    ModalFocus.controls(offline_drawer,offline_focus_controls)
    for control in offline_focus_controls:
        control.connect("focus_entered",self,"_offline_focus_entered",[control])
    offline_drawer.hide()

    queue_drawer = _card(root, true)
    queue_drawer.name = "UpNextDrawer"
    queue_drawer.anchor_left = 0.16
    queue_drawer.anchor_right = 0.84
    queue_drawer.anchor_top = 0.12
    queue_drawer.anchor_bottom = 0.90
    queue_drawer.add_stylebox_override("panel", _box(INK_SOLID, TEAL, 18))
    var queue_stack=VBoxContainer.new()
    _inside(queue_drawer,20,12).add_child(queue_stack)
    queue_header_label=_text(queue_stack,"QUEUE",22)
    queue_help_label=_text(queue_stack,"Select a row, then move or remove it. Add tracks in Offline Library.",16,MUTED)
    queue_help_label.autowrap=true
    queue_help_label.clip_text=false
    queue_help_label.max_lines_visible=3
    queue_selected_label=_text(queue_stack,"",17,TEAL)
    queue_selected_label.autowrap=true
    queue_selected_label.clip_text=false
    queue_selected_label.max_lines_visible=4
    queue_selected_label.focus_mode=Control.FOCUS_ALL
    queue_selected_label.connect("gui_input",self,"_item_title_input",[false])
    queue_selected_label.connect("focus_entered",self,"_title_focus",[queue_selected_label,true])
    queue_selected_label.connect("focus_exited",self,"_title_focus",[queue_selected_label,false])
    var queue_switch=GridContainer.new()
    queue_switch.columns=2
    queue_stack.add_child(queue_switch)
    queue_toggle_button=_action(queue_switch,"QUEUE", "_toggle_queue_view")
    queue_toggle_button.hide() # Backend choice follows playback; it is not a player chooser.
    queue_toggle_button.rect_min_size.y=50
    queue_toggle_button.hide()
    queue_refresh_button=_action(queue_switch,"REFRESH QUEUE", "_refresh_tv_queue_preview")
    queue_refresh_button.rect_min_size.y=50
    queue_download_button=_action(queue_switch,"SAVE QUEUE OFFLINE","_save_queue_offline")
    queue_play_saved_button=_action(queue_switch,"PLAY SAVED QUEUE","_play_saved_queue")
    queue_previous_page=_action(queue_switch,"PREVIOUS PAGE","_queue_previous_page")
    queue_next_page=_action(queue_switch,"NEXT PAGE","_queue_next_page")
    app.offline_save.connect("changed",self,"_refresh_queue")
    queue_refresh_button.hide()
    queue_save_label=_text(queue_stack,"",16,WARM)
    queue_save_label.autowrap=true
    queue_save_label.clip_text=false
    queue_save_label.max_lines_visible=3
    queue_empty_label=_text(queue_stack,"Nothing queued yet. Add tracks from Offline Library.",16,MUTED)
    queue_empty_label.autowrap=true
    queue_empty_label.clip_text=false
    queue_empty_label.max_lines_visible=3
    var queue_scroll=ScrollContainer.new()
    queue_scroll.scroll_horizontal_enabled=false
    queue_scroll.follow_focus=true
    queue_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
    queue_stack.add_child(queue_scroll)
    var queue_rows=VBoxContainer.new()
    queue_rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    queue_scroll.add_child(queue_rows)
    for i in range(32):
        var row=_action(queue_rows,"QUEUED TRACK","_queue_select")
        row.connect("pressed",self,"_queue_select_index",[i])
        row.connect("focus_entered",self,"_queue_row_focused",[i])
        row.visible=false
        queue_items.append(row)
    var queue_actions=GridContainer.new()
    queue_actions.columns=5
    queue_actions_grid=queue_actions
    queue_stack.add_child(queue_actions)
    queue_up_button=_action(queue_actions,"MOVE UP","_queue_up")
    queue_down_button=_action(queue_actions,"MOVE DOWN","_queue_down")
    queue_remove_button=_action(queue_actions,"REMOVE","_queue_remove")
    queue_clear_button=_action(queue_actions,"CLEAR","_queue_clear")
    queue_close_button=_action(queue_actions,"CLOSE","_close_queue")
    queue_drawer.hide()
    tv_clear_dialog=ConfirmationDialog.new()
    tv_clear_dialog.window_title="Clear Kinegra Amp queue?"
    tv_clear_dialog.dialog_text="Stop playback and remove every item from this app's Music Assistant queue?"
    tv_clear_dialog.get_ok().text="CLEAR QUEUE"
    root.add_child(tv_clear_dialog)
    tv_clear_dialog.connect("confirmed",self,"_confirm_tv_queue_clear")
    app.offline_music.connect("queue_changed",self,"_refresh_queue")
    app.offline_music.connect("library_changed",self,"_refresh_offline_collection")

    # The existing Music Assistant catalog is a first-class accessible drawer.
    # Reparent the existing instance, preserving one token/cancellation owner.
    ma_drawer = _card(root, true)
    ma_drawer.name = "MusicAssistantLibraryDrawer"
    ma_drawer.anchor_left = 0.20
    ma_drawer.anchor_right = 0.80
    ma_drawer.anchor_top = 0.09
    ma_drawer.anchor_bottom = 0.92
    ma_drawer.add_stylebox_override("panel", _box(INK_SOLID, TEAL, 18))
    var outer = _inside(ma_drawer, 16, 12)
    var library_layout=VBoxContainer.new()
    library_layout.add_constant_override("separation",6)
    outer.add_child(library_layout)
    var catalog=app.ma_panel
    if catalog!=null:
        for control in [catalog.browser_box,catalog.action_rail]:
            control.get_parent().remove_child(control)
            library_layout.add_child(control)
        catalog.selection_label.autowrap=true
        catalog.selection_label.max_lines_visible=3
        catalog.selection_label.connect("gui_input",self,"_item_title_input",[true])
        catalog.selection_label.connect("focus_entered",self,"_title_focus",[catalog.selection_label,true])
        catalog.selection_label.connect("focus_exited",self,"_title_focus",[catalog.selection_label,false])
        catalog.results_label.autowrap=true
        catalog.results_label.max_lines_visible=3
        library_config_popup=PopupPanel.new()
        library_config_popup.popup_exclusive=true
        library_config_popup.add_stylebox_override("panel",_box(INK_SOLID,TEAL,16))
        root.add_child(library_config_popup)
        var configuration_scroll=ScrollContainer.new()
        configuration_scroll.scroll_horizontal_enabled=false
        configuration_scroll.follow_focus=true
        library_config_popup.add_child(configuration_scroll)
        catalog.get_parent().remove_child(catalog)
        configuration_scroll.add_child(catalog)
        catalog.size_flags_horizontal=Control.SIZE_EXPAND_FILL
        catalog.connect("configuration_requested",self,"_show_library_configuration")
        catalog.connect("view_queue_requested",self,"_open_library_queue")
        catalog.catalog.connect("page_ready",self,"_library_page_loaded")
        catalog.catalog.connect("selection_changed",self,"_library_memory_selection_changed")
        library_config_popup.connect("popup_hide",self,"_library_configuration_closed")
    ma_drawer.hide()
    item_title_dialog=AcceptDialog.new()
    item_title_dialog.window_title="Full selected title"
    item_title_dialog.get_label().autowrap=true
    root.add_child(item_title_dialog)
    _watch_popups(root)
    stage_cover=TextureRect.new()
    stage_cover.name="ArtworkBetweenDancers"
    stage_cover.expand=true
    stage_cover.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    stage_cover.mouse_filter=Control.MOUSE_FILTER_IGNORE
    root.add_child(stage_cover)
    stage_cover.hide()
    cover_tween=Tween.new()
    root.add_child(cover_tween)
    fullscreen_track = _card(root)
    fullscreen_track.name = "FullscreenTrack"
    fullscreen_track.anchor_left = 0.03
    fullscreen_track.anchor_right = 0.46
    fullscreen_track.anchor_top = 0.04
    fullscreen_track.anchor_bottom = 0.04
    fullscreen_track.margin_bottom = 166
    fullscreen_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
    fullscreen_card_frame=Control.new()
    fullscreen_card_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
    fullscreen_track.add_child(fullscreen_card_frame)
    fullscreen_art=TextureRect.new()
    fullscreen_art.expand=true
    fullscreen_art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    fullscreen_art.mouse_filter=Control.MOUSE_FILTER_IGNORE
    fullscreen_card_frame.add_child(fullscreen_art)
    fullscreen_art_caption=_text(fullscreen_card_frame,"BRAND ART",12,MUTED)
    fullscreen_art_caption.align=Label.ALIGN_CENTER
    fullscreen_track_title=_text(fullscreen_card_frame,"",24,WHITE)
    fullscreen_track_artist=_text(fullscreen_card_frame,"",18,MUTED)
    fullscreen_album=_text(fullscreen_card_frame,"",16,MUTED)
    fullscreen_playback=_text(fullscreen_card_frame,"",15,TEAL)
    fullscreen_track.hide()
    fullscreen_help = _card(root)
    fullscreen_help.name = "FullscreenHelp"
    fullscreen_help.anchor_left = 0.20
    fullscreen_help.anchor_right = 0.80
    fullscreen_help.anchor_top = 0.82
    fullscreen_help.anchor_bottom = 0.82
    fullscreen_help.margin_bottom = 74
    fullscreen_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var help_label = _text(_inside(fullscreen_help, 20, 10), "OK / A: PLAY / PAUSE\nLEFT / RIGHT: PREV / NEXT\nBACK / B: CONTROLS", 18, WHITE)
    help_label.align = Label.ALIGN_CENTER
    help_label.autowrap=true
    help_label.clip_text=false
    help_label.size_flags_vertical=Control.SIZE_EXPAND_FILL
    help_label.rect_min_size.y=96
    fullscreen_help.hide()
    root.show()
    # Restored local preferences must be reflected immediately, even while
    # Music Assistant remains the default focus and music stays stopped.
    _refresh_collection()
    _sync_offline_art()
    _set_fullscreen_track(app.offline_music.current_title(), "Local audio" if app.offline_music.track_index < 4 else "Imported audio", "OFFLINE")
    _apply_tv_typography()
    if app.ma_panel!=null:
        if app.ma_panel.has_signal("credential_session_closed"):app.ma_panel.connect("credential_session_closed",self,"_art_session_closed")
        if app.ma_panel.catalog!=null:app.ma_panel.catalog.connect("state_changed",self,"_art_catalog_state")
        if app.ma_panel.catalog!=null:app.ma_panel.catalog.connect("queued_playlist_context",self,"_remember_playlist_context")
    volume_tag=_text(root,"",18,WARM)
    volume_tag.name="PersistentAppVolume"
    volume_tag.anchor_left=0.035
    volume_tag.anchor_right=0.965
    volume_tag.anchor_top=1.0
    volume_tag.anchor_bottom=1.0
    volume_tag.margin_top=-38
    volume_tag.margin_bottom=-4
    volume_tag.align=Label.ALIGN_RIGHT
    volume_tag.mouse_filter=Control.MOUSE_FILTER_IGNORE
    volume_tag.raise()
    sync_app_volume()
    library_button.grab_focus()

func sync_app_volume():
    if volume_tag==null or app==null:return
    volume_tag.raise()
    volume_tag.visible=app.app_volume_percent<100
    volume_tag.text="APP VOLUME: %d%%%s" % [app.app_volume_percent," / NOT SAVED" if not app.volume_save_ok else ""]

func _enter_fullscreen():
    if fullscreen_visual: return
    # Fullscreen must never leave an invisible drawer holding remote focus.
    _close_open_catalog()
    if ma_drawer != null: ma_drawer.hide()
    if offline_drawer != null: offline_drawer.hide()
    if queue_drawer != null: queue_drawer.hide()
    fullscreen_visual=true
    header_card.hide()
    player_card.hide()
    track_hero.hide()
    fullscreen_track.show()
    sync_static_art()
    _update_fullscreen_playback()
    if app.pose_visual != null:
        app.pose_visual.fullscreen_visual=true
        if app.avatar_visual != null: app.avatar_visual.fullscreen_visual=true
        for performer in app.backing_avatars: performer.fullscreen_visual=true
        app.pose_visual.update()
    _show_fullscreen_help()

func sync_static_art():
    if app==null:return
    _sync_cover_mode()
    if stage_cover!=null:
        var camera_live=app.pose_visual!=null and app.pose_visual.enabled
        var art_only=app.visual_quality_level==0
        var box=preload("res://scripts/StageLayout.gd").artwork_rect(root.rect_size,fullscreen_visual,_stage_top())
        if art_only:
            var top=player_card.rect_position.y+player_card.rect_size.y+12.0 if portrait_layout else header_card.rect_position.y+header_card.rect_size.y+12.0
            var bottom=root.rect_size.y-16.0 if portrait_layout else player_card.rect_position.y-12.0
            box=preload("res://scripts/StageLayout.gd").focused_artwork_rect(root.rect_size,top,bottom)
        stage_cover.visible=not fullscreen_visual and ((art_only and box.size.x>=96.0) or (not camera_live and not art_only and app.backing_dancers!=null and app.backing_dancers.pressed))
        if artwork!=null:stage_cover.texture=artwork.texture
        if track_hero!=null:track_hero.visible=not fullscreen_visual and app.visual_quality_level>0 and not portrait_layout and not stage_cover.visible and not (compact_layout and root.rect_size.y<900)
        if artwork!=null:artwork.get_parent().visible=not stage_cover.visible and (track_hero==null or not track_hero.visible)
        stage_cover.rect_position=box.position
        stage_cover.rect_size=box.size
    var top=_stage_top()
    if app.avatar_visual!=null:app.avatar_visual.stage_top=top
    if app.pose_visual!=null:app.pose_visual.stage_top=top
    for performer in app.backing_avatars:performer.stage_top=top
    if fullscreen_visual:_fit_fullscreen_layout()

func _sync_cover_mode():
    var camera_live=app.pose_visual!=null and app.pose_visual.enabled
    var centered=fullscreen_visual and (app.visual_quality_level==0 or (not camera_live and app.backing_dancers!=null and app.backing_dancers.pressed))
    var target=1 if centered else 0
    if target==cover_target:return
    cover_target=target
    cover_tween.stop_all()
    var immediate=(app.reduced_motion!=null and app.reduced_motion.pressed) or app.stream_warmup_budget.holding
    if immediate:_set_cover_morph(float(target))
    else:
        cover_tween.interpolate_method(self,"_set_cover_morph",cover_morph,float(target),0.32,Tween.TRANS_CUBIC,Tween.EASE_IN_OUT)
        cover_tween.start()

func _set_cover_morph(value):
    cover_morph=clamp(float(value),0.0,1.0)
    _layout_fullscreen_card()

func _fullscreen_art_side(size,art_only):
    var side=min(size.x*(.68 if art_only else .29),size.y*(.60 if art_only else .45))
    # Wide screens have room for help beside the card; narrow screens reserve
    # its bottom strip. The artwork does not jump when the hint times out.
    var reserve=(218.0 if size.x>=size.y*1.6 else 506.0) if art_only else 354.0
    return min(side,max(94.0,size.y-reserve))

func _layout_fullscreen_card():
    if root==null or fullscreen_card_frame==null:return
    var size=root.rect_size
    var wide=min(size.x*0.94,900.0)
    var compact=Rect2(Vector2(size.x*.03,size.y*.04),Vector2(wide,174.0))
    var art_only=app!=null and app.visual_quality_level==0
    var side=_fullscreen_art_side(size,art_only)
    var centered_size=Vector2(side+36.0,side+194.0)
    var middle=size.y*.5 if art_only else size.y*lerp(.5,.58,preload("res://scripts/StageLayout.gd").portrait_weight(size))
    var bottom_guard=12.0 if art_only and size.x>=size.y*1.6 else 156.0
    var centered=Rect2(Vector2((size.x-centered_size.x)*.5,clamp(middle-centered_size.y*.5,12.0,max(12.0,size.y-bottom_guard-centered_size.y))),centered_size)
    fullscreen_track.anchor_left=0;fullscreen_track.anchor_right=0
    fullscreen_track.anchor_top=0;fullscreen_track.anchor_bottom=0
    fullscreen_track.rect_position=compact.position.linear_interpolate(centered.position,cover_morph)
    fullscreen_track.rect_size=compact.size.linear_interpolate(centered.size,cover_morph)
    var cover_side=lerp(94.0,side,cover_morph)
    fullscreen_art.rect_position=Vector2(18,10).linear_interpolate(Vector2(18,14),cover_morph)
    fullscreen_art.rect_size=Vector2(cover_side,cover_side)
    fullscreen_art_caption.rect_position=Vector2(18,106).linear_interpolate(Vector2(18,side+16),cover_morph)
    fullscreen_art_caption.rect_size=Vector2(cover_side,24)
    var start=Vector2(124,10).linear_interpolate(Vector2(18,side+40),cover_morph)
    var labels=[fullscreen_track_title,fullscreen_track_artist,fullscreen_album,fullscreen_playback]
    var line=0
    for label in labels:
        if label==fullscreen_album and not label.visible:continue
        label.rect_position=start+Vector2(0,line*36.0)
        label.rect_size=Vector2(max(1.0,fullscreen_track.rect_size.x-start.x-18.0),36.0)
        line+=1

func _show_fullscreen_help():
    playback_notice.reveal()
    if not fullscreen_visual: return
    fullscreen_help.show()
    fullscreen_help_until=OS.get_ticks_msec()+5000

func _exit_fullscreen():
    if not fullscreen_visual: return
    fullscreen_visual=false
    fullscreen_help.hide()
    fullscreen_track.hide()
    sync_static_art()
    header_card.show()
    player_card.show()
    sync_static_art()
    if app.pose_visual != null:
        app.pose_visual.fullscreen_visual=false
        if app.avatar_visual != null: app.avatar_visual.fullscreen_visual=false
        for performer in app.backing_avatars: performer.fullscreen_visual=false
        app.pose_visual.update()
    fullscreen_button.grab_focus()

func _sync_offline_art():
    if app == null or app.offline_music == null:
        return
    _artwork_context="offline"
    _artwork_descriptor={}
    if artwork_controller!=null:artwork_controller.cancel_current()
    var music = app.offline_music
    var texture = load(TRACK_COVERS[music.track_index]) if music.track_index < TRACK_COVERS.size() and music.available(music.track_index) else load("res://assets/branding/icon_192.png")
    artwork.texture = texture
    if fullscreen_cover!=null:fullscreen_cover.texture=texture
    if fullscreen_art != null: fullscreen_art.texture = texture
    if fullscreen_art_caption!=null:fullscreen_art_caption.text="COVER" if music.track_index < 4 and music.available(music.track_index) else "BRAND ART"
    artwork_caption.text = "COVER" if music.track_index < 4 and music.available(music.track_index) else "BRAND ART"
    if track_hero != null:
        track_hero.set_track(texture, music.current_title(), "BUNDLED LOCALLY" if music.track_index < 4 else "IMPORTED / ON THIS DEVICE")

func _confirm_remove_sample():
    if app != null and app.offline_music != null and _offline_selected >= 0:
        _offline_delete_index = _offline_selected
        sample_remove_dialog.dialog_text = "Delete this app's copy of “%s”? USB originals stay unchanged. Imported tracks can be imported again." % app.offline_music.get_title(_offline_delete_index)
        sample_remove_dialog.popup_centered(Vector2(min(680,root.rect_size.x*0.8),230))

func _remove_selected_sample():
    var music = app.offline_music
    var ok = music.remove_library_track(_offline_delete_index)
    _offline_delete_index = -1
    _refresh_offline_collection()
    show_status("DEVICE COPY DELETED" if ok else "COULD NOT DELETE DEVICE COPY")

func _restore_samples():
    var ok = app.offline_music.restore_bundled_tracks()
    _refresh_offline_collection()
    show_status("BUNDLED TRACKS RESTORED  /  PRESS PLAY" if ok else "COULD NOT RESTORE SAMPLES")

func set_tv_text_mode(enabled):
    if typeof(enabled) != TYPE_BOOL:
        return
    _large_text_enabled = enabled
    _apply_tv_typography()

func _apply_tv_typography():
    if _stage_font == null or root == null or not is_inside_tree():
        return
    # Default label sizes scale modestly at 1080p; Large text follows the
    # existing Settings toggle without changing playback or stealing focus.
    _apply_compact_layout()
    var extra = 2 if get_viewport().size.y >= 900.0 else 0
    var enlarge = 3 if _large_text_enabled else 0
    _stage_font.size = 19 + extra + enlarge
    for label in _text_labels:
        if is_instance_valid(label):
            var font = label.get_font("font")
            if font is DynamicFont:
                font.size = int(label.get_meta("tv_base_font_size")) + extra + enlarge
    for cue in gesture_cues.values():cue.get_font("font").size=20 if _large_text_enabled else 18
    call_deferred("_fit_fullscreen_layout")

func _close_open_catalog():
    # Leaving an open catalog must cancel pending requests and clear its token.
    # A hidden drawer may belong to an explicitly started preview, so leave it alone.
    if ma_drawer != null and ma_drawer.visible and app != null and app.ma_panel != null:
        app.ma_panel._close()

func _open_offline_collection():
    if queue_drawer != null: queue_drawer.hide()
    if app == null or app.offline_music == null:
        return
    _close_open_catalog()
    ma_drawer.hide()
    app.offline_music.refresh_user_library()
    var allowed=app.offline_music.playlists.indices()
    if not _offline_location_seen:
        var remembered=ui_memory.offline_index()
        _offline_selected=remembered if remembered in allowed else app.offline_music.track_index
        _offline_location_seen=true
    if not _offline_selected in allowed:_offline_selected=allowed[0] if not allowed.empty() else -1
    var selected_position=allowed.find(_offline_selected)
    _offline_page=int(selected_position/OFFLINE_PAGE_SIZE) if selected_position>=0 else 0
    offline_drawer.show_modal(true)
    _refresh_offline_collection()
    if allowed.empty():offline_import_button.grab_focus()
    else:offline_mix_button.grab_focus()

func _close_offline_collection():
    if offline_drawer != null:
        offline_drawer.hide()
    if offline_button != null:
        offline_button.grab_focus()

func _refresh_offline_collection():
    if offline_drawer == null or app == null or app.offline_music == null: return
    var music = app.offline_music
    var allowed = music.playlists.indices()
    if not _offline_selected in allowed: _offline_selected = allowed[0] if not allowed.empty() else -1
    var pages = max(1,int(ceil(float(allowed.size()) / OFFLINE_PAGE_SIZE)))
    _offline_page = clamp(_offline_page,0,pages-1)
    _offline_page_indices = allowed.slice(_offline_page*OFFLINE_PAGE_SIZE,min(allowed.size()-1,(_offline_page+1)*OFFLINE_PAGE_SIZE-1)) if not allowed.empty() else []
    offline_heading.text = "OFFLINE LIBRARY / %d TRACKS" % music.playlists.available_tracks.count(true)
    offline_mix_button.text = "MIX: " + music.playlists.playlist_name()
    offline_selected_label.text = "SELECTED: " + music.get_title(_offline_selected).to_upper() if _offline_selected >= 0 else "NO AVAILABLE TRACKS"
    offline_selected_label.hint_tooltip = offline_selected_label.text
    offline_favorite_button.text = "REMOVE FAV" if music.playlists.is_favorite(_offline_selected) else "SAVE FAV"
    offline_favorite_button.disabled = _offline_selected < 0
    offline_play_button.disabled = _offline_selected < 0
    offline_queue_button.disabled = _offline_selected < 0
    offline_remove_button.disabled = _offline_selected < 0
    offline_mix_button.disabled = music.playlists.available_tracks.count(true) == 0
    offline_summary.text = "%d IN THIS MIX / %d AVAILABLE / NO AUTOPLAY" % [allowed.size(),music.playlists.available_tracks.count(true)] if music.playlists.available_tracks.count(true) > 0 else "YOUR OFFLINE LIBRARY IS EMPTY. IMPORT MP3 OR OGG FILES TO START."
    offline_page_label.text = "%d / %d" % [_offline_page+1,pages]
    offline_previous_page.disabled = _offline_page == 0
    offline_next_page.disabled = _offline_page+1 >= pages
    offline_list.clear()
    for index in _offline_page_indices:
        var text = "%s%s" % [music.get_title(index)," [FAV]" if music.playlists.is_favorite(index) else ""]
        offline_list.add_item(text)
        offline_list.set_item_tooltip(offline_list.get_item_count()-1,text)
        if index == _offline_selected: offline_list.select(offline_list.get_item_count()-1)
    if _offline_location_seen and _offline_selected>=0:
        ui_memory.remember_offline(_offline_selected)
        _memory_save_timer.start()
    _offline_import_changed()

func _offline_focus_entered(control):
    # ItemList updates and larger text may queue a container resize in the same
    # event as focus. Scroll again after layout, not against the previous bounds.
    if offline_scroll != null: offline_scroll.call_deferred("ensure_control_visible",control)

func _offline_item_selected(row):
    if row < 0 or row >= _offline_page_indices.size(): return
    _offline_selected = _offline_page_indices[row]
    ui_memory.remember_offline(_offline_selected)
    _memory_save_timer.start()
    offline_selected_label.text = "SELECTED: " + app.offline_music.get_title(_offline_selected).to_upper()
    offline_selected_label.hint_tooltip = offline_selected_label.text
    offline_favorite_button.text = "REMOVE FAV" if app.offline_music.playlists.is_favorite(_offline_selected) else "SAVE FAV"

func _offline_item_activated(row):
    _offline_item_selected(row)
    offline_play_button.grab_focus()

func _offline_page_previous():
    _offline_page = max(0,_offline_page-1)
    var allowed = app.offline_music.playlists.indices()
    if not allowed.empty(): _offline_selected = allowed[min(allowed.size()-1,_offline_page*OFFLINE_PAGE_SIZE)]
    _refresh_offline_collection()
    offline_list.grab_focus()

func _offline_page_next():
    var allowed = app.offline_music.playlists.indices()
    _offline_page = min(_offline_page+1,max(0,int(ceil(float(allowed.size())/OFFLINE_PAGE_SIZE))-1))
    if not allowed.empty(): _offline_selected = allowed[min(allowed.size()-1,_offline_page*OFFLINE_PAGE_SIZE)]
    _refresh_offline_collection()
    offline_list.grab_focus()

func _queue_selected_offline():
    if app.offline_music.queue_track(_offline_selected): show_status("ADDED TO QUEUE")
    else: show_status("QUEUE FULL OR TRACK UNAVAILABLE")

func _begin_offline_import():
    offline_import.begin()

func _cancel_offline_import():
    offline_import.cancel()

func _offline_import_changed():
    if offline_import == null: return
    offline_import_status.text = app.offline_music.user_library.last_error if not app.offline_music.user_library.last_error.empty() else offline_import.message()
    offline_import_button.disabled = offline_import.state in offline_import.ACTIVE or app.offline_music.user_library.blocked
    offline_cancel_import_button.visible = offline_import.state in offline_import.ACTIVE
    offline_cancel_import_button.disabled = offline_import.state == "cancelling"

func _queue_add(index):
    if app.offline_music.queue_track(index):
        show_status("ADDED TO QUEUE")
    else:
        show_status("QUEUE FULL OR TRACK UNAVAILABLE")

func _queue_add_0(): _queue_add(0)
func _queue_add_1(): _queue_add(1)
func _queue_add_2(): _queue_add(2)
func _queue_add_3(): _queue_add(3)
func _queue_select(): pass
func _queue_select_index(index):
    queue_selected=index+(queue_local_first if queue_view=="local" else 0)
    _remember_queue_selection()
    _refresh_queue()
func _open_queue():
    _queue_return_to_library=false
    _close_open_catalog()
    offline_drawer.hide()
    ma_drawer.hide()
    queue_view="tv" if _tv_mode() else "local"
    _queue_focus_after_read=queue_view=="tv"
    tv_queue_items.clear()
    tv_queue_rows.clear()
    queue_drawer.show_modal(true)
    if queue_view=="tv":
        _refresh_tv_queue_preview()
        if tv_queue_items.empty():queue_refresh_button.grab_focus()
    else:
        _refresh_queue()
        if not app.offline_music.upcoming_queue.empty():
            queue_items[queue_selected%32].grab_focus()
        else:
            queue_close_button.grab_focus()
func _close_queue():
    _remember_queue_selection()
    _queue_focus_after_read=false
    tv_clear_session=null
    tv_clear_client=""
    if tv_clear_dialog!=null:tv_clear_dialog.hide()
    queue_drawer.hide()
    queue_view="tv" if _tv_mode() else "local"
    tv_queue_items.clear()
    tv_queue_rows.clear()
    if _queue_return_to_library:
        _queue_return_to_library=false
        ma_drawer.show_modal(true)
        app.ma_panel.show()
        app.ma_panel.view_queue_button.grab_focus()
    else:queue_button.grab_focus()
func _open_library_queue():
    _queue_return_to_library=true
    ma_drawer.hide()
    offline_drawer.hide()
    queue_view="tv"
    _queue_focus_after_read=true
    tv_queue_items.clear();tv_queue_rows.clear()
    queue_drawer.show_modal(true)
    _refresh_tv_queue_preview()
    if tv_queue_items.empty():queue_refresh_button.grab_focus()
func _toggle_queue_view():
    if queue_view=="local":
        queue_view="tv"
        _refresh_tv_queue_preview()
    else:
        queue_view="local"
        tv_queue_items.clear()
        tv_queue_rows.clear()
    _refresh_queue()
func _refresh_tv_queue_preview():
    if queue_view!="tv": return
    _remember_queue_selection()
    _queue_focus_after_read=true
    tv_queue_items.clear()
    tv_queue_rows.clear()
    tv_queue_preview_status="LOADING QUEUE..."
    if not app._request_tv_queue("items"):
        tv_queue_preview_status="QUEUE UNAVAILABLE / RETRY"
    _refresh_queue()
func invalidate_tv_queue():
    _clear_buffer_progress()
    _tv_snapshot.clear()
    _tv_snapshot_at=-1
    _tv_snapshot_session=null
    _tv_display.clear()
    if _tv_mode():_clear_tv_metadata()
    tv_clear_session=null
    tv_clear_client=""
    if tv_clear_dialog!=null:tv_clear_dialog.hide()
    tv_queue_items.clear()
    tv_queue_rows.clear()
    if tv_queue_label!=null and _tv_mode():
        tv_queue_label.text="QUEUE DISCONNECTED"
        tv_queue_label.show()
    if queue_view=="tv":
        tv_queue_preview_status="PLAYBACK DISCONNECTED / RECONNECT"
        _refresh_queue()
func tv_queue_reconnected():
    if tv_queue_label!=null and _tv_mode():
        tv_queue_label.text="PLAYBACK CONNECTED / QUEUE INFO PENDING"
        tv_queue_label.show()
    if queue_view=="tv":
        tv_queue_preview_status="PLAYBACK CONNECTED / REFRESH QUEUE"
        _refresh_queue()
func show_tv_queue_items(items,ok,detail):
    if queue_view!="tv" or not queue_drawer.visible:return
    _remember_queue_selection()
    var restore_id=_tv_queue_selection_id if _queue_selection_binding()==_tv_queue_selection_binding else ""
    var focus_row=_queue_focus_after_read or queue_items.has(root.get_focus_owner())
    tv_queue_items.clear()
    tv_queue_rows.clear()
    if ok and typeof(items)==TYPE_ARRAY:
        for item in items:
            if typeof(item)==TYPE_DICTIONARY:
                tv_queue_items.append(str(item.get("name","Untitled")))
                tv_queue_rows.append(item.duplicate(true))
            else:
                # Display legacy/read-only fixture rows without inventing IDs.
                tv_queue_items.append(str(item))
                tv_queue_rows.append({})
    _tv_queue_rows_binding=_queue_selection_binding() if ok else ""
    queue_selected=0
    if not restore_id.empty():
        for index in range(tv_queue_rows.size()):
            if str(tv_queue_rows[index].get("item_id",""))==restore_id:
                queue_selected=index
                break
    tv_queue_preview_status=("UP TO 10 UPCOMING ITEMS / %d SHOWN" % tv_queue_items.size()) if ok else str(detail)
    _refresh_queue()
    _queue_focus_after_read=false
    _remember_queue_selection()
    if focus_row and not tv_queue_rows.empty():queue_items[queue_selected%32].grab_focus()
func _refresh_queue():
    if app == null or app.offline_music == null or queue_drawer == null:
        return
    queue_button.text="QUEUE" if _tv_mode() else "QUEUE (%d)" % app.offline_music.upcoming_queue.size()
    if queue_toggle_button!=null:
        queue_toggle_button.hide()
    if queue_refresh_button!=null: queue_refresh_button.visible=queue_view=="tv"
    queue_previous_page.visible=queue_view=="local"
    queue_next_page.visible=queue_view=="local"
    queue_download_button.visible=queue_view=="tv" or app.offline_save.active
    queue_download_button.text="CANCEL SAVING" if app.offline_save.active else "SAVE QUEUE OFFLINE"
    queue_play_saved_button.visible=not app.offline_save.saved_indices.empty()
    queue_play_saved_button.text="PLAY SAVED SO FAR" if app.offline_save.active else "PLAY SAVED QUEUE"
    if queue_view=="tv":
        queue_header_label.text="QUEUE"
        queue_help_label.text="Remove an upcoming item, or clear this app's queue."
        queue_selected_label.text=("SELECTED / OK FOR FULL TITLE\n"+str(tv_queue_items[queue_selected])) if queue_selected>=0 and queue_selected<tv_queue_items.size() else ""
        queue_selected_label.visible=not queue_selected_label.text.empty()
        queue_save_label.text=app.offline_save.message if not app.offline_save.message.empty() else tv_queue_preview_status
        queue_save_label.show()
        queue_empty_label.text="No unbuffered upcoming items to show."
        queue_empty_label.visible=tv_queue_items.empty() and not tv_queue_preview_status.begins_with("LOADING")
        for button in [queue_up_button,queue_down_button]:
            button.disabled=true
            button.hide()
        var available=app._queue_controls_available()
        queue_remove_button.show()
        queue_remove_button.text="REMOVE"
        queue_remove_button.disabled=not available or queue_selected<0 or queue_selected>=tv_queue_rows.size() or not app.tv_queue_policy.item_id(tv_queue_rows[queue_selected].get("item_id"))
        queue_clear_button.show()
        queue_clear_button.text="CLEAR QUEUE…"
        queue_clear_button.disabled=not available
        for i in range(queue_items.size()):
            var row=queue_items[i]
            row.visible=i<tv_queue_items.size()
            if row.visible:
                row.text="%s%02d   %s" % ["[SELECTED] " if i==queue_selected else "",i+1,str(tv_queue_items[i])]
                row.hint_tooltip=row.text
        return
    for button in [queue_up_button,queue_down_button,queue_remove_button,queue_clear_button]: button.show()
    queue_remove_button.text="REMOVE"
    queue_clear_button.text="CLEAR"
    queue_header_label.text="QUEUE"
    queue_help_label.text="Select a row, then move or remove it. Add tracks in Offline Library."
    queue_empty_label.text="Nothing queued yet. Add tracks from Offline Library."
    var items=app.offline_music.upcoming_queue
    queue_selected=clamp(queue_selected,0,max(0,items.size()-1))
    queue_local_first=int(queue_selected/32)*32
    queue_previous_page.disabled=queue_local_first==0
    queue_next_page.disabled=queue_local_first+32>=items.size()
    queue_help_label.text="Select, move or remove a track. Showing %d–%d of %d." % [queue_local_first+1 if not items.empty() else 0,min(queue_local_first+32,items.size()),items.size()]
    queue_selected_label.text=("SELECTED / OK FOR FULL TITLE\n"+app.offline_music.get_title(items[queue_selected])) if not items.empty() else ""
    queue_selected_label.visible=not items.empty()
    if queue_empty_label != null:
        queue_empty_label.visible=items.empty()
    if queue_up_button != null:
        queue_up_button.disabled=items.empty() or queue_selected<=0
        queue_down_button.disabled=items.empty() or queue_selected>=items.size()-1
        queue_remove_button.disabled=items.empty()
        queue_clear_button.disabled=items.empty()
    if queue_save_label != null:
        queue_save_label.text="" if app.offline_music.queue_save_ok else "QUEUE CHANGES COULD NOT BE SAVED"
        queue_save_label.visible=not app.offline_music.queue_save_ok
        if app.offline_save.active:
            queue_save_label.text=app.offline_save.message
            queue_save_label.show()
    for i in range(queue_items.size()):
        var button=queue_items[i]
        var absolute=queue_local_first+i
        button.visible=absolute<items.size()
        if button.visible:
            button.text=("%s%02d   %s" % ["[SELECTED]  " if absolute==queue_selected else "",absolute+1,app.offline_music.get_title(items[absolute])])
            button.hint_tooltip=button.text
func _queue_up():
    if queue_view!="local": return
    if app.offline_music.queue_move(queue_selected,-1):
        queue_selected-=1
        _refresh_queue()
func _queue_down():
    if queue_view!="local": return
    if app.offline_music.queue_move(queue_selected,1):
        queue_selected+=1
        _refresh_queue()
func _queue_remove():
    if queue_view=="tv":
        if queue_remove_button.disabled or queue_selected<0 or queue_selected>=tv_queue_rows.size():return
        app._sendspin_command("remove",tv_queue_rows[queue_selected].get("item_id"))
        _refresh_queue()
        return
    app.offline_music.queue_remove(queue_selected)
    _refresh_queue()
func _queue_clear():
    if queue_view=="tv":
        if not app._queue_controls_available():return
        tv_clear_session=app.sendspin_facade
        tv_clear_client=str(app._sendspin_controls().get("client_id",""))
        tv_clear_dialog.popup_centered(Vector2(min(640,root.rect_size.x-40),180))
        return
    app.offline_music.queue_clear()
    _refresh_queue()
func _confirm_tv_queue_clear():
    var session=tv_clear_session
    var client=tv_clear_client
    tv_clear_session=null
    tv_clear_client=""
    if queue_view!="tv" or not queue_drawer.visible or session==null or not is_instance_valid(session) or session!=app.sendspin_facade or client.empty() or client!=str(app._sendspin_controls().get("client_id","")):
        show_status("PLAYBACK CHANGED / QUEUE NOT CLEARED")
        return
    app._sendspin_command("clear")
    _refresh_queue()

func _cycle_offline_collection():
    if app == null or not app._cycle_offline_playlist():
        return
    _refresh_offline_collection()
    offline_mix_button.grab_focus()

func _cue_offline_track(index):
    # Browsing selection is independent of playback and never closes another source.
    if app == null or not app.offline_music.available(index): return
    _offline_selected = index
    _refresh_offline_collection()
    if offline_drawer.visible and offline_play_button != null: offline_play_button.grab_focus()

func _cue_offline_0():
    _cue_offline_track(0)

func _cue_offline_1():
    _cue_offline_track(1)

func _cue_offline_2():
    _cue_offline_track(2)

func _cue_offline_3():
    _cue_offline_track(3)

func _toggle_offline_drawer_favorite():
    if app == null or app.offline_music == null or _offline_selected < 0: return
    app.offline_music.playlists.toggle_favorite(_offline_selected)
    if app.offline_music.playlists.playlist_index == 3 and app.offline_music.playlists.indices().empty():
        app.offline_music.playlists.playlist_index = 0
    app.offline_music.persist_preferences()
    _refresh_offline_collection()
    offline_favorite_button.grab_focus()

func _play_cued_from_drawer():
    if _offline_selected < 0 or not app._cue_offline_track(_offline_selected): return
    _close_offline_collection()
    _play_offline()

func _open_library():
    if queue_drawer != null: queue_drawer.hide()
    offline_drawer.hide()
    ma_drawer.show_modal(true)
    if app != null and app.ma_panel != null:
        app.ma_panel.show()
        app.ma_panel.connect_saved_if_needed()
        if library_config_popup==null or not library_config_popup.visible:app.ma_panel.focus_entry()

func _close_library():
    _cancel_library_play_intents()
    if library_config_popup!=null:library_config_popup.hide()
    ma_drawer.hide()
    if library_button != null:
        library_button.grab_focus()

func _advanced():
    if queue_drawer != null: queue_drawer.hide()
    _close_open_catalog()
    offline_drawer.hide()
    ma_drawer.hide()
    hide()
    app.page_scroller.show()
    app.page_scroller.scroll_vertical = 0
    if app.device_refresh_button != null:
        app.device_refresh_button.grab_focus()

func show_stage():
    if queue_drawer != null: queue_drawer.hide()
    _close_open_catalog()
    app.page_scroller.hide()
    offline_drawer.hide()
    ma_drawer.hide()
    show()
    if library_button != null:
        library_button.grab_focus()

func _cycle_avatar():
    var styles=app.avatar_visual.STYLES.duplicate()
    styles.append("skeleton")
    var current=app.avatar_visual.mode if app.avatar_visual.active else "skeleton"
    var next=styles[(styles.find(current)+1)%styles.size()]
    if next=="skeleton":
        app.avatar_visual.set_active(false)
        app.pose_visual.draw_skeleton=true
    else:
        app.avatar_visual.set_style(next)
        app.avatar_visual.set_active(true)
        app.pose_visual.draw_skeleton=false
    avatar_button.text="AVATAR: "+next.to_upper()
    app.pose_visual.update()

func _toggle_body():
    if not app.pose_visual.webcam_connected: return
    app.pose_visual.set_mode("off" if app.pose_visual.mode=="live" else "live")

func _webcam_changed(connected):
    if body_button==null: return
    if not connected and body_button.has_focus(): avatar_button.grab_focus()
    body_button.visible=connected
    _body_status(app.pose_visual.status)

func _body_status(value):
    if body_button==null: return
    var label="OFF" if app.pose_visual.mode!="live" else ("PAUSED" if app.pose_visual.performance_suspended else ("LIVE" if app.pose_visual.tracking_live else "WAITING"))
    body_button.text="WEBCAM: "+label
    body_button.hint_tooltip="Webcam tracking: "+value
    _sync_avatar_context()

func _sync_avatar_context():
    if avatar_button==null:return
    var available=app.pose_visual.webcam_connected and app.pose_visual.mode=="live"
    if not available and avatar_button.has_focus():
        (body_button if body_button.visible else visuals_button).grab_focus()
    avatar_button.visible=available

func set_playback_context(value):
    if not value in ["offline","catalog","ma","preview"]:return false
    playback_context=value
    if _startup_restored:ui_memory.set_source(value)
    return true

func _tv_mode():
    return app!=null and playback_context in ["catalog","ma"]
func _apply_compact_layout():
    if options_grid==null or player_card==null or root==null: return
    portrait_layout=root.rect_size.y>root.rect_size.x
    compact_layout=root.rect_size.x<1050.0 or portrait_layout
    var show_brand=root.rect_size.x>=1200.0 and not portrait_layout
    header_grid.columns=3 if compact_layout else (8 if show_brand else 6)
    header_emblem.visible=show_brand
    if header_brand!=null:header_brand.visible=show_brand
    transport_grid.columns=3 if compact_layout else 5
    track_row.columns=2 if compact_layout else 3
    header_card.margin_bottom=170 if compact_layout else 100
    track_hero.anchor_top=0.21 if compact_layout else 0.17
    for drawer in [ma_drawer,offline_drawer,queue_drawer]:
        if drawer!=null:
            drawer.anchor_left=0.025 if compact_layout else (0.20 if drawer==ma_drawer else 0.16)
            drawer.anchor_right=0.975 if compact_layout else (0.80 if drawer==ma_drawer else 0.84)
    now_title.clip_text=true
    source_label.clip_text=true
    status_label.clip_text=true
    options_grid.columns=(3 if root.rect_size.x<550.0 else 4) if compact_layout else 8
    if queue_actions_grid!=null:queue_actions_grid.columns=3 if root.rect_size.x<700.0 else 5
    # Keep the existing timeline from imposing a desktop minimum width on
    # portrait transport controls and their contextual gesture reminders.
    var narrow=root.rect_size.x<550.0
    if playback_progress!=null:playback_progress.rect_min_size.x=70 if narrow else 250
    if clock_label!=null:clock_label.rect_min_size.x=84 if narrow else 158
    if rewind_button!=null:rewind_button.rect_min_size.x=68 if narrow else 104
    if forward_button!=null:forward_button.rect_min_size.x=68 if narrow else 104
    var short_compact=compact_layout and root.rect_size.y<900.0
    player_card.anchor_top=(0.30 if short_compact else 0.48) if compact_layout else 0.54
    if track_hero!=null:
        track_hero.anchor_bottom=0.45 if compact_layout else 0.51
        track_hero.visible=not fullscreen_visual and app.visual_quality_level>0 and not short_compact and not portrait_layout
    if app.ma_panel!=null and app.ma_panel.browse_nav!=null:
        app.ma_panel.browse_nav.columns=3 if portrait_layout else (2 if root.rect_size.x<900 else 5)
        app.ma_panel.browse_tools.columns=2 if root.rect_size.x<900 else 4
        app.ma_panel.setup_button.text="SETTINGS"
        app.ma_panel.sendspin_toggle.text="PLAYBACK"
    if offline_list != null: offline_list.rect_min_size.y = clamp(180.0 + max(0.0,root.rect_size.y-800.0)*0.4,180.0,420.0)
    if play_button!=null: play_button.rect_min_size.x=120 if compact_layout else 142
    if portrait_layout:
        header_card.anchor_top=0.015
        header_card.anchor_bottom=0.015
        ma_drawer.anchor_top=0.015
        ma_drawer.anchor_bottom=0.985
    else:
        header_card.anchor_top=0.035
        header_card.anchor_bottom=0.035
        ma_drawer.anchor_top=0.09
        ma_drawer.anchor_bottom=0.92
        player_card.anchor_bottom=0.965
        player_card.margin_top=0
        player_card.margin_bottom=0
    call_deferred("_fit_portrait_player")

func _fit_portrait_player():
    if root==null or player_card==null:return
    if portrait_layout:
        var top=header_card.rect_position.y+header_card.rect_size.y+14.0
        player_card.anchor_top=0.0
        player_card.anchor_bottom=0.0
        player_card.margin_top=top
        player_card.margin_bottom=top+player_card.get_combined_minimum_size().y
    _fit_fullscreen_layout()
    sync_static_art()

func _stage_top():
    if fullscreen_visual:return lerp(root.rect_size.y*.04+186.0,root.rect_size.y*.10,cover_morph)
    if portrait_layout:return player_card.rect_position.y+player_card.rect_size.y+12.0
    return -1.0
func _toggle_visuals():
    app.set_visuals_enabled(not app.visuals_enabled)
    show_status("VISUALS ON" if app.visuals_enabled else "VISUALS OFF / MUSIC CONTINUES")

func sync_visuals_control():
    if visuals_button==null:return
    visuals_button.text="VISUALS: ON" if app.visuals_enabled else "VISUALS: OFF"
    visuals_button.hint_tooltip="Toggle visual effects without stopping music. Adaptive quality still protects playback. Save Setup remembers this choice."
    visuals_button.add_stylebox_override("normal",_box(Color(0.05,0.24,0.27) if app.visuals_enabled else INK_SOLID,TEAL if app.visuals_enabled else EDGE,12))
    _fit_stage_button_labels()

func _toggle():
    if _tv_mode():app._play_music_assistant()
    elif not app.offline_music.is_playing(): app._play_offline_music()
func _pause_tv():
    if _tv_mode(): app._sendspin_command("pause")
    elif app.offline_music.is_playing(): app._toggle_offline()

func _play_offline():
    app._play_offline_music()

func _previous():
    if _tv_mode(): app._sendspin_command("previous")
    else: app._previous_offline()

func _next():
    if _tv_mode(): app._sendspin_command("next")
    else: app._next_offline()

func _stop():
    if _tv_mode(): app._sendspin_command("stop")
    else: app._stop_all_music()

func _cycle_playlist():
    if app == null or app.offline_music == null:
        return
    if app._cycle_offline_playlist():
        show_status("PLAYLIST READY / Press PLAY to start")
    _refresh_collection()

func _toggle_favorite():
    if app != null:
        app._toggle_offline_favorite()
    _refresh_collection()

func _cycle_repeat():
    if app != null:
        app._cycle_offline_repeat()
    _refresh_collection()

func _toggle_shuffle():
    if app != null:
        app._toggle_offline_shuffle()
    _refresh_collection()

func _cycle_preset():
    if app != null:
        app._cycle_visual_preset()

func show_visual_preset(name):
    if preset_button != null:
        preset_button.text = "SCENE: " + str(name).replace("HORIZON GRID", "HORIZON").replace("NEBULA FLOW", "NEBULA")

func _cycle_sensitivity():
    if app != null:
        app._cycle_visual_sensitivity()

func show_visual_sensitivity(name):
    if sensitivity_button != null:
        sensitivity_button.text = "SENS: " + str(name).substr(0, 12)

func _refresh_collection():
    if app == null or app.offline_music == null:
        return
    var o = app.offline_music
    if playlist_button != null:
        playlist_button.text = "MIX: " + o.playlists.playlist_name().replace("ALL FOUR", "ALL").replace("HEAVY ROTATION", "HEAVY").replace("NIGHT FLIGHT", "NIGHT").replace("FAVOURITES", "FAVS")
    if repeat_button != null:
        repeat_button.text = "REPEAT: " + o.playlists.repeat_name()
    if shuffle_button != null:
        shuffle_button.text = "SHUFFLE: " + o.playlists.shuffle_name()
    if favorite_button != null:
        favorite_button.text = "FAVOURITED" if o.playlists.is_favorite(o.track_index) else "SAVE FAV"
    if not o.last_save_ok and status_label != null:
        status_label.text = "LOCAL PREFERENCES UNSAVED / ORIGINAL FILE PRESERVED"

func _clock(secs):
    var bounded = int(clamp(float(secs), 0.0, 359999.0))
    return "%02d:%02d" % [int(bounded / 60), bounded % 60]

func _clear_buffer_progress():
    if buffered_progress!=null:buffered_progress.value=0
    if buffer_label!=null:buffer_label.hide()

func _update_buffer_progress(metadata):
    _clear_buffer_progress()
    if metadata.empty() or app==null or app.sendspin_facade==null or app.sendspin_facade.runtime==null:return
    var runtime=app.sendspin_facade.runtime
    if not runtime.has_method("queued_audio_snapshot"):return
    var info=BufferPresentation.present(metadata,runtime.queued_audio_snapshot(),OS.get_ticks_msec())
    if info.empty():return
    buffer_label.text=info.label
    buffer_label.show()
    buffered_progress.value=info.end_percent if info.timeline else 0.0
    timeline_row.show()

func _sendspin_is_buffering():
    return app!=null and app.sendspin_facade!=null and app.sendspin_facade.runtime!=null and app.sendspin_facade.runtime.active and app.sendspin_facade.runtime.get("buffering")==true

func _process(delta):
    if fullscreen_visual and fullscreen_help.visible and OS.get_ticks_msec() >= fullscreen_help_until:
        fullscreen_help.hide()
    if not visible or app == null or app.offline_music == null:
        return
    if fullscreen_visual and fullscreen_track!=null:
        var persistent=cover_target==1 or cover_morph>.02
        var comfort=app.reduced_motion!=null and app.reduced_motion.pressed
        var notice_alpha=playback_notice.step(delta,persistent,comfort)
        if abs(fullscreen_track.modulate.a-notice_alpha)>.00001:fullscreen_track.modulate.a=notice_alpha
    var local = app.offline_music
    if track_hero != null:
        var offline_visible = playback_context=="offline"
        var ma_selected = playback_context=="catalog"
        var ma_preview = playback_context=="preview"
        var ma_local = playback_context=="ma"
        var tv_state=app._tv_playback_status() if ma_local else ""
        var fresh_local=tv_state=="playing"
        var fresh_preview = false
        if ma_preview and app.native_transport != null and app.native_transport.ma_preview_mode and app.native_stream_engine != null and app.analysis_owner == app.native_stream_engine and app.native_stream_engine.active:
            var age = OS.get_ticks_msec() - app.native_stream_engine.last_pcm_at
            fresh_preview = app.native_stream_engine.last_pcm_at >= 0 and age >= 0 and age <= 500
        var tv_buffering=ma_local and _sendspin_is_buffering()
        var hero_state = _tv_status_text() if ma_local else ("PLAYING  /  MA SHORT PREVIEW" if fresh_preview else ("MA PREVIEW  /  WAITING FOR AUDIO" if ma_preview else ("CATALOG SELECTION  /  NO PLAYBACK" if ma_selected else "")))
        var hero_playing=(offline_visible and local.is_playing()) or fresh_preview or (fresh_local and not tv_buffering)
        if hero_playing and track_hero.get("render_budget_fps")==0:
            hero_state="PLAYING / VISUALS OFF" if not app.visuals_enabled else "PLAYING / AUDIO FIRST"
        if tv_buffering and tv_state=="waiting": hero_state="BUFFERING AUDIO…"
        if ma_preview and track_hero.source_label != null:
            track_hero.source_label.text = "MUSIC ASSISTANT  /  SHORT PREVIEW"
        var fraction=local.progress_fraction() if offline_visible else 0.0
        if ma_local and _tv_display.get("timeline",false):fraction=float(_tv_display.position)/float(_tv_display.duration)
        track_hero.set_audio_state(hero_playing, app.fft, fraction, app.reduced_motion != null and app.reduced_motion.pressed, hero_state)
    _progress_elapsed += max(0.0, float(delta))
    if _progress_elapsed < 0.2:
        return
    _progress_elapsed = 0.0
    _sync_art_session()
    if _tv_mode():_refresh_tv_presentation()
    if fullscreen_visual:_update_fullscreen_playback()
    sync_static_art()
    sync_app_volume()
    _sync_transport()
    _fit_stage_button_labels()
    # Never pretend MA catalogue metadata has a local progress position.
    if playback_context!="offline":
        var current=_current_tv_metadata() if _tv_mode() else {}
        _update_buffer_progress(current)
        playback_progress.value=100.0*current.position/current.duration if current.get("timeline",false) else 0.0
        clock_label.text=(_clock(current.position)+" / "+_clock(current.duration)) if current.get("timeline",false) else (("LIVE / NO DURATION" if app._tv_playback_status()=="playing" else "") if _tv_mode() else "NO TIMELINE")
        return
    _clear_buffer_progress()
    playback_progress.value = local.progress_fraction() * 100.0
    clock_label.text = _clock(local.progress_seconds()) + " / " + _clock(local.duration_seconds())

func _sync_transport():
    _sync_avatar_context()
    var tv=_tv_mode()
    queue_button.text="QUEUE" if tv else "QUEUE (%d)" % app.offline_music.upcoming_queue.size()
    var available=app._queue_controls_available() if tv else false
    tv_pause_button.visible=true
    previous_button.disabled=tv and not available
    next_button.disabled=tv and not available
    stop_button.disabled=tv and not available
    # Play is also the recovery entry: a missing connection must not disable it.
    # Main serializes/deduplicates accepted intents and in-flight mutations.
    play_button.disabled=false
    tv_pause_button.disabled=(not available) if tv else not app.offline_music.is_playing()
    tv_pause_button.text="PAUSE"
    tv_pause_button.hint_tooltip="Pause music here. Position retention is still being tested."
    if tv:
        play_button.text="PLAY"
        play_button.hint_tooltip="Play or resume Music Assistant here. Your saved connection reconnects automatically."
        stop_button.text="STOP"
    elif app.offline_music!=null:
        play_button.text="PLAY"
        play_button.hint_tooltip="Play local music. Use Pause to pause it."
        stop_button.text="STOP"
    var active=app._tv_playback_status()=="playing" if tv else app.offline_music.is_playing()
    TransportStyle.apply(play_button,active)
    if app.ma_panel!=null: app.ma_panel.set_playback_active(active and tv)
    var seekable=app._tv_seek_available() if tv else true
    rewind_button.disabled=not seekable
    forward_button.disabled=not seekable
    rewind_button.visible=not tv or seekable
    forward_button.visible=not tv or seekable
    progress_stack.visible=root.rect_size.x>=800.0 and (not tv or _current_tv_metadata().get("timeline",false))
    playback_progress.visible=progress_stack.visible
    buffered_progress.visible=progress_stack.visible
    timeline_row.visible=not tv or seekable or _current_tv_metadata().get("timeline",false) or (buffer_label!=null and buffer_label.visible)
    if tv_queue_label!=null and not tv: tv_queue_label.hide()

func show_tv_queue_snapshot(snapshot):
    if not _tv_mode() or typeof(snapshot)!=TYPE_DICTIONARY:return
    _tv_snapshot=snapshot.duplicate(true)
    _tv_snapshot_at=OS.get_ticks_msec()
    _tv_snapshot_session=app.sendspin_facade
    _refresh_tv_presentation()
    if snapshot.get("item_count",-1)==0:
        tv_queue_label.hide()
        return
    var next=str(snapshot.get("next","")).strip_edges()
    if not str(snapshot.get("current_id","")).empty() and snapshot.get("current_id")==snapshot.get("next_id"):next=""
    tv_queue_label.text="NEXT: "+(next if not next.empty() else "NONE REPORTED")
    tv_queue_label.hint_tooltip="Next item reported by Music Assistant."
    tv_queue_label.show()

func _remember_playlist_context(name,ids):
    playlist_context.remember(name,ids)

func _current_tv_metadata():
    if app==null or app.sendspin_facade!=_tv_snapshot_session:return {}
    return _tv_presentation.current(_tv_snapshot,_tv_snapshot_at,OS.get_ticks_msec(),app._tv_playback_status()=="playing",OS.get_unix_time())

func _clear_tv_metadata():
    _tv_display.clear()
    var message="Choose music" if _tv_snapshot_at<0 else "Waiting for track information"
    if _tv_snapshot_at>=0 and app.sendspin_facade==_tv_snapshot_session and OS.get_ticks_msec()-_tv_snapshot_at<=10000:
        var count=_tv_snapshot.get("item_count",-1)
        if count==0 or (count==-1 and _tv_snapshot.get("state","") in ["idle","stopped"] and str(_tv_snapshot.get("current","")).empty()):
            message="Queue is empty"
    now_title.text=message
    now_title.hint_tooltip=message
    _set_fullscreen_track(message,"","MUSIC ASSISTANT","")
    if fullscreen_track_artist!=null:
        fullscreen_track_artist.text="Press Play to resume your queue" if _tv_snapshot_at<0 else "MUSIC ASSISTANT"
        fullscreen_track_artist.hint_tooltip=fullscreen_track_artist.text
    _set_artwork_descriptor({},"tv|waiting")
    if track_hero!=null:track_hero.set_track(artwork.texture,message,"MUSIC ASSISTANT")

func _tv_status_text():
    match app._tv_playback_status():
        "playing": return "PLAYING HERE"
        "waiting": return "WAITING FOR AUDIO"
        "error": return app.tv_playback_error
        "paused": return "PAUSED"
    return ""

func _refresh_tv_presentation():
    var state=_tv_status_text()
    source_label.text="MUSIC ASSISTANT" if state.empty() else "MUSIC ASSISTANT  •  "+state
    if not app.tv_playback_error.empty():show_status(app.tv_playback_error)
    var current=_current_tv_metadata()
    if current.empty():
        _clear_tv_metadata()
        return
    _tv_display=current
    now_title.text=current.title
    now_title.hint_tooltip=current.title
    var context_label=playlist_context.label(current.album,playlist_context.playlist(str(_tv_snapshot.get("library_track_id",""))))
    _set_fullscreen_track(current.title,current.artist,"MUSIC ASSISTANT",current.album,context_label)
    _set_artwork_descriptor(_tv_snapshot.get("artwork_descriptor",{}),"tv|"+str(_tv_snapshot.get("current_id","")))
    if track_hero!=null:track_hero.set_track(artwork.texture,current.title,"MUSIC ASSISTANT")

func _fit_stage_button_labels():
    if _stage_font==null: return
    for button in [library_button,offline_button,queue_button,fullscreen_button,settings_button,visuals_button,previous_button,play_button,tv_pause_button,next_button,stop_button,playlist_button,favorite_button,repeat_button,shuffle_button,preset_button,sensitivity_button,body_button,avatar_button,rewind_button,forward_button,queue_toggle_button,queue_refresh_button,queue_previous_page,queue_next_page,queue_download_button,queue_play_saved_button,queue_up_button,queue_down_button,queue_remove_button,queue_clear_button,queue_close_button]:
        if button==null or not button.is_visible_in_tree() or button.rect_size.x<=0: continue
        var key=str(button.text)+"|"+str(int(button.rect_size.x))+"|"+str(_stage_font.size)
        if button.has_meta("fitted_label_key") and button.get_meta("fitted_label_key")==key: continue
        var font=DynamicFont.new()
        font.font_data=_stage_font.font_data
        var style=button.get_stylebox("normal")
        var padding=style.get_minimum_size().x if style!=null else 0
        if button.icon!=null: padding+=button.icon.get_width()+button.get_constant("hseparation")
        font.size=_stage_font.size
        while font.size>12 and font.get_string_size(button.text).x+padding>button.rect_size.x:
            font.size-=1
        button.add_font_override("font",font)
        button.set_meta("fitted_label_key",key)

func show_offline_track(name, playing):
    set_playback_context("offline")
    source_label.text = "OFFLINE MUSIC  •  ON THIS DEVICE"
    now_title.text = str(name)
    now_title.hint_tooltip = now_title.text
    _sync_offline_art()
    _refresh_collection()
    _set_fullscreen_track(name, "Local audio" if app.offline_music.track_index < 4 else "Imported audio", "OFFLINE")
    show_offline_state(playing)

func show_offline_state(playing):
    if _tv_mode(): return
    if play_button != null:
        play_button.text = "PAUSE" if playing else "PLAY"
    if status_label != null:
        status_label.text = "PLAYING  •  LOCAL AUDIO" if playing else "PAUSED  •  AUDIO IDLE"

func show_status(message):
    if status_label != null:
        status_label.text = str(message).substr(0, 65)

# The library can describe a selection without playing it. Only display
# elapsed time for the local player and only claim preview playback while
# recent PCM confirms that the preview source is actually producing audio.
func _update_fullscreen_playback():
    if fullscreen_playback == null or app == null or source_label == null:
        return
    var source = source_label.text
    var message = "NO PLAYBACK"
    if playback_context=="offline" and app.offline_music != null:
        var local = app.offline_music
        message = "PLAYING" if local.is_playing() else "PAUSED / STOPPED"
        var duration = float(local.duration_seconds())
        if not is_nan(duration) and not is_inf(duration) and duration > 0.0:
            message += "  /  " + _clock(local.progress_seconds()) + " / " + _clock(duration)
    elif playback_context=="catalog":
        message = "SELECTION / NO PLAYBACK"
    elif playback_context=="ma":
        var current=_current_tv_metadata()
        message=app.tv_playback_error if not app.tv_playback_error.empty() else _tv_status_text()
        if message.empty():message="PRESS PLAY"
        if current.get("timeline",false):
            message+="  /  "+("" if current.get("advancing",false) else "LAST REPORTED ")+_clock(current.position)+" / "+_clock(current.duration)
        elif app._tv_playback_status()=="playing":message+="  /  NO DURATION REPORTED"
    elif playback_context=="preview":
        var fresh = false
        if app.native_transport != null and app.native_transport.ma_preview_mode and app.native_stream_engine != null and app.analysis_owner == app.native_stream_engine and app.native_stream_engine.active:
            var age = OS.get_ticks_msec() - app.native_stream_engine.last_pcm_at
            fresh = app.native_stream_engine.last_pcm_at >= 0 and age >= 0 and age <= 500
        message = "SHORT PREVIEW / PLAYING" if fresh else "SHORT PREVIEW / WAITING FOR AUDIO"
    fullscreen_playback.hint_tooltip = message
    if cover_target==1 and playback_context=="ma":
        var current=_current_tv_metadata()
        var state=app.tv_playback_error if not app.tv_playback_error.empty() else _tv_status_text()
        if state.empty():state="Press Play"
        message=state+"  "+_clock(current.position)+" / "+_clock(current.duration) if current.get("timeline",false) else state
        fullscreen_track_artist.text=fullscreen_track_artist.text.split("  /  ")[0]
    fullscreen_playback.text = message

func _set_fullscreen_track(title, artist, source, album="", context_label=""):
    playback_notice.show(str(title)+"|"+str(artist)+"|"+str(source))
    if fullscreen_track_title != null:
        fullscreen_track_title.text = str(title)
        fullscreen_track_title.hint_tooltip = str(title)
        fullscreen_track_artist.text = (str(artist) if str(artist).strip_edges() != "" else "Artist not provided") + "  /  " + str(source)
        fullscreen_track_artist.hint_tooltip = fullscreen_track_artist.text
        fullscreen_album.text = str(context_label) if not str(context_label).empty() else playlist_context.label(str(album),"")
        fullscreen_album.visible=not fullscreen_album.text.empty()
        fullscreen_album.hint_tooltip = fullscreen_album.text

func show_ma_selection(name, artist="", album="",descriptor={}):
    if app!=null and (app._sendspin_fresh() or (app.offline_music!=null and app.offline_music.is_playing())):
        show_status("CATALOG SELECTION / CURRENT MUSIC CONTINUES")
        return
    if descriptor.empty() and app!=null and app.ma_panel!=null and app.ma_panel.catalog!=null:
        var selected=app.ma_panel.catalog.selected
        if selected.get("name")==str(name):descriptor=selected.get("artwork_descriptor",{})
    _set_fullscreen_track(name, artist, "MUSIC ASSISTANT SELECTION", album)
    set_playback_context("catalog")
    source_label.text = "MUSIC ASSISTANT  •  CATALOG SELECTION"
    now_title.text = str(name).substr(0, 65)
    now_title.hint_tooltip = str(name)
    _set_artwork_descriptor(descriptor,"selection|"+str(name)+"|"+str(artist))
    if track_hero != null:
        track_hero.set_track(artwork.texture, name, "MUSIC ASSISTANT  /  CATALOG SELECTION")
    show_status("SELECTED  •  NO STREAM URL YET")

func _seek_backward():
    _seek_direction(-10.0)

func _seek_forward():
    _seek_direction(10.0)

func _seek_direction(seconds):
    if app == null:
        return
    if _tv_mode():
        if app._tv_seek_available():app._sendspin_command("seek_backward" if seconds<0 else "seek_forward")
        else:show_status("SEEK NEEDS FRESH PLAYING TRACK TIMING")
        return
    if playback_context!="offline":
        show_status("SEEK UNAVAILABLE FOR THIS SOURCE")
        return
    if app._seek_offline(seconds):
        _progress_elapsed = 0.2
        _process(0.0)
    else:
        show_status("SEEK UNAVAILABLE / PRESS PLAY FIRST")

func _active_drawer():
    if not visible or fullscreen_visual:
        return null
    for drawer in [ma_drawer,offline_drawer,queue_drawer]:
        if drawer!=null and drawer.is_visible_in_tree():
            return drawer
    return null

func _drawer_focus_changed(control):
    var drawer=_active_drawer()
    if drawer==null or _restoring_drawer_focus or ModalFocus.nested_popup(root):
        return
    if control!=null and drawer.is_a_parent_of(control):
        _drawer_focus_owner=control
        return
    var target=_drawer_focus_owner
    if not is_instance_valid(target) or not drawer.is_a_parent_of(target) or not target.is_visible_in_tree():
        var choices=[]
        ModalFocus.controls(drawer,choices)
        target=choices[0] if not choices.empty() else null
    if target!=null:
        _restoring_drawer_focus=true
        target.grab_focus()
        _restoring_drawer_focus=false

func route_drawer_input(event):
    var accept_key=""
    if event is InputEventJoypadButton and event.button_index==0:accept_key="joy:"+str(event.device)+":0"
    elif event is InputEventKey and event.scancode in [KEY_ENTER,KEY_KP_ENTER]:accept_key="key:"+str(event.device)+":"+str(event.scancode)
    if not accept_key.empty():
        if not event.pressed:_accept_held.erase(accept_key)
        elif _accept_held.has(accept_key):return true
        elif _active_drawer()!=null or fullscreen_visual:_accept_held[accept_key]=true
    var back_key=""
    if event is InputEventJoypadButton and event.button_index in [1,11]:back_key="joy:"+str(event.device)+":"+str(event.button_index)
    elif event is InputEventKey and event.scancode==KEY_ESCAPE:back_key="key:"+str(event.device)+":"+str(event.scancode)
    if not back_key.empty():
        if not event.pressed:
            var held=_back_held.has(back_key)
            if _back_held.get(back_key,false):_back_input_at=OS.get_ticks_msec()
            _back_held.erase(back_key)
            return held
        if _back_held.has(back_key):return true
        _back_held[back_key]=_active_drawer()!=null or _top_popup(root)!=null or fullscreen_visual or OS.get_ticks_msec()-_back_native_at<200
    var back=event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index in [1,11])
    if back and (_active_drawer()!=null or _top_popup(root)!=null or fullscreen_visual):
        app._handle_tv_back("input")
        return true
    if fullscreen_visual:return _route_fullscreen_input(event)
    var drawer=_active_drawer()
    if drawer==null or _top_popup(root)!=null:return false
    var focus=root.get_focus_owner()
    var direction=Vector2.ZERO
    for entry in [["ui_left",Vector2.LEFT],["ui_right",Vector2.RIGHT],["ui_up",Vector2.UP],["ui_down",Vector2.DOWN]]:
        if event.is_action_pressed(entry[0],true):
            direction=entry[1]
            break
    var tab=event is InputEventKey and event.pressed and event.scancode==KEY_TAB
    if direction==Vector2.ZERO and not tab:
        return false
    var choices=[]
    ModalFocus.controls(drawer,choices)
    if choices.empty():
        return true
    if focus==null or not drawer.is_a_parent_of(focus):
        choices[0].grab_focus()
        return true
    if tab:
        var index=choices.find(focus)
        choices[posmod(index+(-1 if event.shift else 1),choices.size())].grab_focus()
        return true
    if focus == offline_list:
        var local_selected = offline_list.get_selected_items()
        if direction == Vector2.RIGHT or (direction == Vector2.DOWN and not local_selected.empty() and local_selected[0] == offline_list.get_item_count()-1):
            offline_play_button.grab_focus()
            return true
        if direction == Vector2.UP and not local_selected.empty() and local_selected[0] == 0:
            offline_mix_button.grab_focus()
            return true
    if drawer==ma_drawer:
        var panel=app.ma_panel
        # Category grids use row/column order: a wide search field must not
        # steal Right from a category through diagonal neighbour scoring.
        if focus.get_parent()==panel.browse_nav:
            var tabs=panel.browse_nav.get_children()
            var index=tabs.find(focus)
            var columns=panel.browse_nav.columns
            var target=index
            if direction==Vector2.RIGHT and index%columns<columns-1 and index+1<tabs.size():target=index+1
            elif direction==Vector2.LEFT and index%columns>0:target=index-1
            elif direction==Vector2.UP and index>=columns:target=index-columns
            elif direction==Vector2.DOWN:
                if index+columns<tabs.size():target=index+columns
                else:
                    (panel.search_edit if index%columns==0 else panel.search_button).grab_focus()
                    return true
            tabs[target].grab_focus()
            return true
        if focus in [panel.search_edit,panel.search_button]:
            if direction==Vector2.UP:
                var tabs=panel.browse_nav.get_children()
                var row=int((tabs.size()-1)/panel.browse_nav.columns)*panel.browse_nav.columns
                tabs[min(tabs.size()-1,row+(0 if focus==panel.search_edit else 1))].grab_focus()
                return true
            if direction==Vector2.DOWN:
                panel._focus_selected_list()
                return true
            if focus==panel.search_button and direction==Vector2.LEFT:
                panel.search_edit.grab_focus()
                return true
        if focus==panel.list and direction==Vector2.RIGHT:
            var target=panel.play_focus_target()
            if target!=null:target.grab_focus()
            return true
        if focus.get_parent()==panel.action_grid and panel.action_grid.get_children().find(focus)<panel.action_grid.columns and direction==Vector2.UP:
            panel.selection_label.grab_focus()
            return true
        if focus==panel.selection_label and direction==Vector2.DOWN:
            var target=panel.play_focus_target()
            if target!=null:target.grab_focus()
            return true
        if focus.get_parent()==panel.action_grid and direction==Vector2.RIGHT:
            var adjacent=panel.action_to_right(focus)
            if adjacent!=null:adjacent.grab_focus()
            return true
        if panel.action_rail.is_a_parent_of(focus) and direction==Vector2.LEFT:
            panel._focus_selected_list()
            return true
    if focus is LineEdit and direction.x!=0:
        return false
    if focus is ItemList and direction.x==0:
        var selected=focus.get_selected_items()
        if direction==Vector2.UP or selected.empty() or selected[0]<focus.get_item_count()-1:
            return false
    if drawer==ma_drawer and focus==app.ma_panel.list and direction in [Vector2.RIGHT,Vector2.DOWN]:
        var target=app.ma_panel.play_focus_target()
        if target!=null:
            target.grab_focus()
            return true
    ModalFocus.neighbour(focus,choices,direction).grab_focus()
    return true

func _fit_fullscreen_layout():
    if root==null or fullscreen_track==null:return
    _layout_fullscreen_card()
    fullscreen_help.anchor_left=0.03
    fullscreen_help.anchor_right=0.97
    fullscreen_help.anchor_top=1.0
    fullscreen_help.anchor_bottom=1.0
    fullscreen_help.margin_top=-144
    fullscreen_help.margin_bottom=-16
    if app.visual_quality_level==0 and root.rect_size.x>=root.rect_size.y*1.6:
        var card_width=_fullscreen_art_side(root.rect_size,true)+36.0
        var help_width=min(500.0,(root.rect_size.x-card_width)*.5-32.0)
        fullscreen_help.anchor_left=1.0
        fullscreen_help.anchor_right=1.0
        fullscreen_help.margin_left=-help_width-16.0
        fullscreen_help.margin_right=-16.0
    else:
        fullscreen_help.margin_left=0.0
        fullscreen_help.margin_right=0.0

func _route_fullscreen_input(event):
    var pressed=(event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed)
    if not pressed or ModalFocus.nested_popup(root):return false
    if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index in [1,11]):
        app._handle_tv_back()
        return true
    var action=""
    if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.scancode in [KEY_SPACE,KEY_MEDIAPLAY]) or (event is InputEventJoypadButton and event.button_index==0):action="toggle"
    elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.scancode==KEY_MEDIAPREVIOUS):action="previous"
    elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.scancode==KEY_MEDIANEXT):action="next"
    if action.empty():return false
    _show_fullscreen_help()
    if not _tv_mode() and not source_label.text.begins_with("OFFLINE MUSIC"):return true
    if action=="previous":_previous()
    elif action=="next":_next()
    elif (app._sendspin_fresh() if _tv_mode() else app.offline_music.is_playing()):_pause_tv()
    else:_toggle()
    return true

func _set_artwork_descriptor(descriptor,context):
    var safe=preload("res://scripts/MAArtworkPolicy.gd").descriptor(descriptor)
    if context==_artwork_context and safe.get("proxy_id","")==_artwork_descriptor.get("proxy_id",""):return
    _artwork_context=context
    _artwork_descriptor=safe
    if artwork_controller!=null:artwork_controller.cancel_current()
    _apply_artwork(null)
    _sync_art_session()

func _sync_art_session():
    if artwork_controller==null or app==null:return
    var panel=app.ma_panel
    var catalog=panel.catalog if panel!=null else null
    if catalog==null:return
    var secured=panel.has_signal("credential_session_closed")
    if secured and panel.library_disconnected:
        artwork_controller.close()
        _artwork_binding=""
        if _artwork_context!="offline":_apply_artwork(null)
        return
    var origin=catalog.endpoint
    var credential=catalog.token
    var trust=catalog.trusted_private_http
    var facade=app.sendspin_facade
    var paired=facade!=null and is_instance_valid(facade) and facade.runtime!=null and facade.runtime.active and app._sendspin_controls().get("paired",false)
    var binding=str(catalog.epoch)+"|"+str(facade.get_instance_id() if paired else 0)
    if binding==_artwork_auth_failed_binding:
        artwork_controller.close()
        _artwork_binding=""
        if _artwork_context!="offline":_apply_artwork(null)
        return
    if credential.empty():
        # The origin-bound vault getter is available only with the reviewed
        # credential-session contract. Never recover after Forget/disconnect.
        if not secured or not paired or _artwork_descriptor.empty():
            artwork_controller.close()
            _artwork_binding=""
            if _artwork_context!="offline":_apply_artwork(null)
            return
        origin=panel._credential_endpoint()
        trust=panel.lan_trust.pressed
        binding+="|"+origin+"|"+str(trust)
        if _artwork_binding==binding and artwork_controller.is_configured():
            artwork_controller.select(_artwork_descriptor,_artwork_context)
            return
        credential=app._library_credential() if app.has_method("_library_credential") else panel._read_provisioned_token()
    var changed=not artwork_controller.matches_session(origin,credential,trust,binding)
    if not artwork_controller.configure(origin,credential,trust,binding):
        credential=""
        _artwork_binding=""
        if _artwork_context!="offline":_apply_artwork(null)
        return
    credential=""
    _artwork_binding=binding
    if changed and _artwork_context!="offline":_apply_artwork(null)
    if _artwork_context!="offline":artwork_controller.select(_artwork_descriptor,_artwork_context)

func _art_authorization_failed():
    var panel=app.ma_panel if app!=null else null
    if panel!=null and panel.catalog!=null:
        var facade=app.sendspin_facade
        var paired=facade!=null and is_instance_valid(facade) and facade.runtime!=null and facade.runtime.active and app._sendspin_controls().get("paired",false)
        _artwork_auth_failed_binding=str(panel.catalog.epoch)+"|"+str(facade.get_instance_id() if paired else 0)
    _art_session_closed("auth_failed")

func _art_catalog_state(state,_detail):
    if state in ["cancelled","not_configured","auth_expired","permission_denied","invalid_endpoint","auth_required"]:
        artwork_controller.close()
        _artwork_binding=""
        if _artwork_context!="offline":_apply_artwork(null)

func _art_session_closed(reason):
    if not reason in ["library_closed","focus_lost","inactive"]:playlist_context.clear()
    artwork_controller.close()
    _artwork_binding=""
    if str(reason)!="library_closed":
        _tv_snapshot.clear()
        _tv_snapshot_at=-1
        _tv_display.clear()
        _artwork_descriptor.clear()
        if _tv_mode():_clear_tv_metadata()
    if _artwork_context!="offline":_apply_artwork(null)

func _apply_artwork(texture):
    var genuine=texture!=null
    var shown=texture if genuine else load("res://assets/branding/icon_192.png")
    if fullscreen_cover!=null:fullscreen_cover.texture=shown
    if artwork!=null:artwork.texture=shown
    if fullscreen_art!=null:fullscreen_art.texture=shown
    if artwork_caption!=null:artwork_caption.text="COVER" if genuine else "BRAND ART"
    if fullscreen_art_caption!=null:fullscreen_art_caption.text="COVER" if genuine else "BRAND ART"
    if track_hero!=null:track_hero.set_artwork(shown)

func _artwork_ready(context,texture):
    if context==_artwork_context:_apply_artwork(texture)

func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED and ui_memory!=null:ui_memory.save()
    if what==MainLoop.NOTIFICATION_APP_PAUSED and artwork_controller!=null:
        artwork_controller.close()
        _artwork_binding=""
        _tv_snapshot.clear()
        if _artwork_context!="offline":
            _artwork_descriptor.clear()
            _artwork_context="tv|waiting"
            _apply_artwork(null)

# Non-focusable contextual reminders: hidden until explicitly enabled with a
# connected live webcam. The transport buttons keep their original callbacks,
# icons, styles, focus and disabled-state policy.
func _build_gesture_cues(_controls,_stack):
    for button in [play_button,previous_button,tv_pause_button,next_button,stop_button]:
        var cue=Label.new()
        cue.clip_text=true;cue.focus_mode=Control.FOCUS_NONE
        cue.mouse_filter=Control.MOUSE_FILTER_PASS
        var font=DynamicFont.new();font.font_data=load("res://assets/fonts/DejaVuSans.ttf");font.size=12
        cue.add_font_override("font",font)
        cue.add_color_override("font_color",Color(.03,.09,.12) if button==play_button else TEAL)
        cue.align=Label.ALIGN_CENTER
        cue.anchor_right=1.0;cue.anchor_top=1.0;cue.anchor_bottom=1.0
        cue.margin_left=4;cue.margin_right=-4;cue.margin_top=-19;cue.margin_bottom=-1
        button.add_child(cue)
        cue.hide();gesture_cues[button]=cue
    gesture_fullscreen_feedback=Label.new()
    gesture_fullscreen_feedback.anchor_left=.12;gesture_fullscreen_feedback.anchor_right=.88
    gesture_fullscreen_feedback.anchor_top=.93;gesture_fullscreen_feedback.anchor_bottom=.98
    gesture_fullscreen_feedback.align=Label.ALIGN_CENTER
    gesture_fullscreen_feedback.clip_text=false
    gesture_fullscreen_feedback.autowrap=true
    gesture_fullscreen_feedback.add_font_override("font",_stage_font.duplicate())
    gesture_fullscreen_feedback.get_font("font").size=26
    gesture_fullscreen_feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE
    gesture_fullscreen_feedback.add_color_override("font_color",TEAL)
    add_child(gesture_fullscreen_feedback);gesture_fullscreen_feedback.hide()
func show_gesture_cues(enabled,bindings,feedback):
    var policy=preload("res://scripts/WebcamGesturePolicy.gd")
    for button in gesture_cues:
        var action="play_pause" if button in [play_button,tv_pause_button] else ("previous" if button==previous_button else ("next" if button==next_button else ""))
        var gesture=bindings.get(action,"none")
        var cue=gesture_cues[button]
        cue.visible=enabled and not policy.short_label(gesture).empty()
        cue.text=policy.short_label(gesture)
        cue.hint_tooltip=policy.recipe(gesture)
    if gesture_fullscreen_feedback!=null:
        gesture_fullscreen_feedback.visible=enabled and fullscreen_visual
        gesture_fullscreen_feedback.text=feedback

# Consume the topmost surface once, including Android's independent notification
# path. A duplicate native/input pair must not fall through to the stage Quit.
func handle_topmost_back(source="input"):
    var now=OS.get_ticks_msec()
    if source=="native":
        for handled in _back_held.values():
            if handled:return true
    if (source=="native" and now-_back_native_at<200) or (source=="native" and now-_back_input_at<200) or (source=="input" and now-_back_native_at<200):return true
    var popup=_top_popup(root)
    var handled=true
    if popup!=null:popup.hide()
    elif fullscreen_visual:_exit_fullscreen()
    elif queue_drawer!=null and queue_drawer.is_visible_in_tree():_close_queue()
    elif ma_drawer!=null and ma_drawer.is_visible_in_tree():
        if app.ma_panel.kind=="playlist_items":app.ma_panel._back_to_playlists()
        else:app.ma_panel._close()
    elif offline_drawer!=null and offline_drawer.is_visible_in_tree():_close_offline_collection()
    else:handled=false
    if handled:
        if source=="native":_back_native_at=now
        else:_back_input_at=now
    return handled

func _top_popup(node):
    if node==null:return null
    var children=node.get_children()
    children.invert()
    for child in children:
        var deeper=_top_popup(child)
        if deeper!=null:return deeper
        if child is Popup and child.is_visible_in_tree():return child
    return null

func _watch_popups(node):
    for child in node.get_children():
        if child is Popup and not child.is_connected("about_to_show",self,"_popup_opening"):
            child.connect("about_to_show",self,"_popup_opening",[child])
            child.connect("popup_hide",self,"_popup_closed",[child])
        _watch_popups(child)
func _popup_opening(popup):popup.set_meta("library_opener",root.get_focus_owner())
func _popup_closed(popup):call_deferred("_restore_popup_opener",popup)
func _restore_popup_opener(popup):
    if not is_instance_valid(popup):return
    var opener=popup.get_meta("library_opener") if popup.has_meta("library_opener") else null
    if is_instance_valid(opener) and opener.is_visible_in_tree():opener.grab_focus()

func _show_library_configuration(kind):
    if library_config_popup==null:return
    app.ma_panel.show()
    app.ma_panel.setup_box.visible=kind=="library"
    app.ma_panel.sendspin_box.visible=kind=="playback"
    library_config_popup.popup_centered(Vector2(root.rect_size.x*0.94,root.rect_size.y*0.86))
    if kind=="library":app.ma_panel.endpoint_edit.grab_focus()
    else:app.ma_panel.sendspin_connect_button.grab_focus()
func _library_configuration_closed():
    if not _configuration_completed_close:_cancel_library_play_intents()
    if app==null or not is_instance_valid(app.ma_panel):return
    app.ma_panel.token_edit.text=""
    app.ma_panel._clear_pending_credential()
func _library_page_loaded(_page):
    _restore_library_selection(_page)
    if library_config_popup!=null and library_config_popup.visible and not app.ma_panel.setup_box.visible:call_deferred("_close_completed_library_configuration")
func _close_completed_library_configuration():
    _configuration_completed_close=true
    if library_config_popup!=null:library_config_popup.hide()
    _configuration_completed_close=false
    app.ma_panel._focus_selected_list()

func _item_title_input(event,library):
    if not event.is_action_pressed("ui_accept") or (event is InputEventKey and event.echo):return
    var title=""
    if library:title=str(app.ma_panel._selected_item().get("name",""))
    elif queue_view=="tv" and queue_selected>=0 and queue_selected<tv_queue_items.size():title=str(tv_queue_items[queue_selected])
    elif queue_view=="local" and queue_selected>=0 and queue_selected<app.offline_music.upcoming_queue.size():title=app.offline_music.get_title(app.offline_music.upcoming_queue[queue_selected])
    if title.empty():return
    item_title_dialog.dialog_text=title
    item_title_dialog.popup_centered(Vector2(min(760,root.rect_size.x*0.92),min(420,root.rect_size.y*0.60)))
    item_title_dialog.get_ok().grab_focus()
    root.accept_event()

func _title_focus(label,focused):
    label.add_color_override("font_color",WARM if focused else TEAL)
    var outline=StyleBoxFlat.new()
    outline.draw_center=false
    outline.border_color=WARM if focused else Color(0,0,0,0)
    outline.set_border_width_all(2)
    for side in [MARGIN_LEFT,MARGIN_TOP,MARGIN_RIGHT,MARGIN_BOTTOM]:outline.set_default_margin(side,0)
    label.add_stylebox_override("normal",outline)


func restore_startup_context():
    # Main calls this after its initial local metadata setup. Restoring never plays.
    _startup_restored=true
    var source=ui_memory.source()
    if source=="offline":show_offline_track(app.offline_music.current_title(),false)
    else:
        set_playback_context("ma")
        source_label.text="MUSIC ASSISTANT"
        now_title.text="Choose music"
        now_title.hint_tooltip=now_title.text
        _apply_artwork(null)
        _set_fullscreen_track("Choose music","","MUSIC ASSISTANT")
        fullscreen_track_artist.text="Press Play to resume your queue"
        track_hero.set_track(artwork.texture,"Choose music","MUSIC ASSISTANT")
        show_status("PRESS PLAY TO RESUME YOUR QUEUE")
        if app.has_method("_restore_music_assistant_session"):app.call_deferred("_restore_music_assistant_session")
    _sync_transport()
    call_deferred("_focus_startup_play")
    return source

func _focus_startup_play():
    if fullscreen_visual or _active_drawer()!=null or ModalFocus.nested_popup(root):return
    if play_button!=null and play_button.is_visible_in_tree() and not play_button.disabled:play_button.grab_focus()

func saved_library_location(origin=""):
    if origin.empty() and app!=null and app.ma_panel!=null:origin=app.ma_panel.catalog.endpoint
    _memory_restore_location=ui_memory.location(origin)
    _memory_restore_origin=ui_memory.identity(origin)
    return _memory_restore_location.duplicate(true)

func _restore_library_selection(page):
    if app==null or app.ma_panel==null or typeof(page)!=TYPE_DICTIONARY:return
    var panel=app.ma_panel
    if panel.get("restoring_library_location")==true:return
    if not _memory_restore_location.empty():
        var same=ui_memory.identity(panel.catalog.endpoint)==_memory_restore_origin and page.get("kind")==_memory_restore_location.kind
        if same and page.get("kind")=="playlist_items":same=page.get("playlist",{}).get("item_id")==_memory_restore_location.playlist_id
        var selected=str(_memory_restore_location.selected_id) if same else ""
        _restoring_memory_selection=true
        var rows=page.get("items",[])
        for index in range(rows.size()):
            if rows[index].get("provider")=="library" and str(rows[index].get("item_id",""))==selected:
                panel.list.select(index)
                panel._select_index(index)
                panel.list.ensure_current_is_visible()
                break
        _restoring_memory_selection=false
        _memory_restore_location.clear()
    _memory_page_generation=panel.page_generation
    _remember_library_position()

func _library_memory_selection_changed(_item):
    if _restoring_memory_selection or not _memory_restore_location.empty():return
    if app==null or app.ma_panel==null or _memory_page_generation!=app.ma_panel.page_generation:return
    _remember_library_position()

func _remember_library_position():
    var panel=app.ma_panel
    if panel.offline_mode or panel.catalog.token.empty() or panel.get("restoring_library_location")==true:return
    if ui_memory.remember_location(panel.catalog.endpoint,panel.catalog.current_page,panel.selected_item,int(panel.library_playlist_return.get("offset",0))):_memory_save_timer.start()

func _cancel_library_play_intents():
    if app==null:return
    if app.has_method("cancel_pending_resume"):app.cancel_pending_resume()
    if app.ma_panel!=null and app.ma_panel.has_method("cancel_pending_play"):app.ma_panel.cancel_pending_play()


func _queue_selection_binding():
    if app==null or app.ma_panel==null:return ""
    var client=str(app._sendspin_controls().get("client_id",""))
    var origin=app.ma_panel.catalog.endpoint
    if origin.empty():origin=app.ma_panel._credential_endpoint()
    var fingerprint=ui_memory.identity(origin)
    return fingerprint+"|"+client if not fingerprint.empty() and not client.empty() else ""

func _remember_queue_selection():
    if queue_view!="tv" or queue_selected<0 or queue_selected>=tv_queue_rows.size():return
    var binding=_queue_selection_binding()
    var identifier=str(tv_queue_rows[queue_selected].get("item_id",""))
    if binding.empty() or binding!=_tv_queue_rows_binding or identifier.empty():return
    _tv_queue_selection_binding=binding
    _tv_queue_selection_id=identifier

func _queue_row_focused(index):
    if index<0 or index>=queue_items.size():return
    if queue_view=="tv" and index>=tv_queue_rows.size():return
    if queue_view=="local" and queue_local_first+index>=app.offline_music.upcoming_queue.size():return
    _queue_select_index(index)

func _exit_tree():
    if ui_memory!=null:ui_memory.save()

func show_licenses():
    if legal_dialog == null:
        legal_dialog = preload("res://scripts/LicenseDialog.gd").new()
        root.add_child(legal_dialog)
        _watch_popups(root)
    legal_dialog.open()


func _save_queue_offline():
    if app.offline_save.active:app.offline_save.cancel()
    else:app.offline_save.begin()
    _refresh_queue()

func _play_saved_queue():
    if not app.offline_save.play_saved():show_status("No saved tracks available / open Offline Library")

func _queue_previous_page():
    if queue_view!="local":return
    queue_selected=max(0,queue_local_first-32)
    _refresh_queue()
    if not app.offline_music.upcoming_queue.empty():queue_items[0].grab_focus()

func _queue_next_page():
    if queue_view!="local" or queue_local_first+32>=app.offline_music.upcoming_queue.size():return
    queue_selected=queue_local_first+32
    _refresh_queue()
    queue_items[0].grab_focus()
