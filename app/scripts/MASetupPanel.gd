extends VBoxContainer
# Optional catalog UI. Parent connects media_selected to an explicit later action.
signal media_selected(item)
signal preview_requested(item)
signal configuration_requested(kind)
signal view_queue_requested
signal close_requested
signal credential_session_closed(reason)
signal credential_session_authorized(credential,origin)
signal credential_forgotten
signal sendspin_start_requested(endpoint, trusted)
signal sendspin_stop_requested
signal sendspin_reveal_requested
signal sendspin_confirm_requested
signal sendspin_command_requested(command)
signal sendspin_play_here_requested(item)
var catalog = null
var endpoint_edit = null
var token_edit = null
var lan_trust = null
var search_edit = null
var search_button=null
var status_label = null
var token_storage_label = null
var remember_access = null
var forget_access_dialog = null
var legacy_saved_token_endpoint = ""
var library_disconnected = false
var pending_remember_token = ""
var pending_remember_endpoint = ""
var pending_remember_epoch = -1
var pending_session_token=""
var pending_session_origin=""
var pending_session_epoch=-1
var _logged_token_storage=false
var session_credential_provider=null # Root RAM access; never owns persistence.
var credential_store_override = null # Synthetic host fault injection only.
var results_label = null
var list = null
var playlist_button = null
var confirm_button = null
var preview_button = null
var next_button = null
var previous_button = null
var play_button = null
var add_queue_button=null
var queue_all_button=null
var pending_queue_media=[]
var pending_queue_client=""
var selection_label = null
var action_rail=null
var browser_box=null
var browse_nav=null
var browse_tools=null
var action_grid=null
var view_queue_button=null
var selected_item={}
var selected_epoch=-1
var selected_page=0
var page_generation=0
var pending_play_item={}
var pending_play_client=""
var playback_owner=null
var pending_play_session=null
var connect_play_item={}
var connect_play_epoch=-1
var connect_play_origin=""
var connect_play_deadline=0
var connect_play_facade=null
var connect_play_endpoint=""
var connect_play_client=""
var restoring_library_location=false
var restore_playlist_offset=-1
var pending_queue_session=null
var setup_box = null
var setup_button = null
var demo_button = null
var demo_row = null
var settings_path = "user://music_assistant.cfg"
var sendspin_box = null
var sendspin_toggle = null
var sendspin_endpoint = null
var sendspin_trust = null
var sendspin_status = null
var sendspin_player_id = ""
var sendspin_paired = false
var sendspin_play_requested = false
var sendspin_connect_button = null
var sendspin_advanced = null
var sendspin_advanced_toggle = null
var playback_summary = null
var sendspin_details = null
var playback_state = "idle"
var _selection_ready = false
var sendspin_token_dialog = null
var sendspin_token_label = null
var pairing_code_dialog = null
var pairing_code_label = null
var sendspin_hint = null
var sendspin_refresh_timer = null
var sendspin_refresh_target = ""
var sendspin_refresh_attempts = 0
var sendspin_refresh_deadline = 0
var offline_catalog = preload("res://scripts/OfflineLibraryCatalog.gd").new()
var offline_mode = false
var offline_kind = "albums"
var kind = "tracks"
var offset = 0
var refresh_page_button=null
var back_to_playlists_button=null
var library_playlist_return={"offset":0,"search":""}
var page_request={"kind":"tracks","offset":0,"search":""}

func _ready():
    catalog = load("res://scripts/MACatalog.gd").new()
    add_child(catalog)
    catalog.connect("state_changed", self, "_on_state")
    catalog.connect("state_changed", self, "_credential_state")
    catalog.connect("page_ready", self, "_on_page")
    catalog.connect("selection_changed", self, "_on_selection")
    catalog.connect("players_ready", self, "_on_players")
    var heading = _label("YOUR MUSIC LIBRARY")
    heading.add_color_override("font_color", Color("82e6ce"))
    _label("OK opens a playlist or adds a track. Right moves to actions.")
    setup_button = _button("LIBRARY SETTINGS ▸", "_toggle_setup")
    setup_box = VBoxContainer.new()
    add_child(setup_box)
    endpoint_edit = LineEdit.new()
    endpoint_edit.placeholder_text = "Music Assistant server address"
    endpoint_edit.rect_min_size.y = 48
    setup_box.add_child(endpoint_edit)
    token_edit = LineEdit.new()
    token_edit.placeholder_text = "Library access token (leave blank to use saved access)"
    token_edit.secret = true
    token_edit.rect_min_size.y = 48
    setup_box.add_child(token_edit)
    token_storage_label = Label.new()
    token_storage_label.text = "Provisioned token storage: not checked"
    token_storage_label.autowrap = true
    setup_box.add_child(token_storage_label)
    remember_access = CheckBox.new()
    remember_access.text = "Remember access securely on this device"
    remember_access.pressed = true
    remember_access.focus_mode = Control.FOCUS_ALL
    setup_box.add_child(remember_access)
    lan_trust = CheckBox.new()
    lan_trust.text = "I explicitly trust token exchange over private LAN HTTP (unencrypted)"
    lan_trust.focus_mode = Control.FOCUS_ALL
    setup_box.add_child(lan_trust)
    var saved=ConfigFile.new()
    if saved.load(settings_path)==OK:
        endpoint_edit.text=str(saved.get_value("connection", "endpoint", ""))
        lan_trust.pressed=bool(saved.get_value("connection", "trust_private_http", false))
        legacy_saved_token_endpoint=endpoint_edit.text.strip_edges().trim_suffix("/").to_lower()
    endpoint_edit.connect("text_changed",self,"_library_endpoint_changed")
    lan_trust.connect("toggled",self,"_library_trust_changed")
    _button("CONNECT LIBRARY", "_connect_catalog", setup_box)
    _button("DISCONNECT LIBRARY", "_disconnect_library", setup_box)
    _button("FORGET SAVED ACCESS", "_forget_saved_access", setup_box)
    forget_access_dialog=ConfirmationDialog.new()
    forget_access_dialog.window_title="Forget library access on this device?"
    forget_access_dialog.dialog_text="Saved Music Assistant library access will be removed from this device and pending library requests cancelled. Playback pairing and connection settings stay saved. This does not revoke the token on the server; use Music Assistant to revoke it."
    forget_access_dialog.popup_exclusive=true
    forget_access_dialog.get_ok().text="Forget access"
    forget_access_dialog.connect("confirmed",self,"_confirm_forget_saved_access")
    add_child(forget_access_dialog)
    setup_box.visible = endpoint_edit.text.strip_edges().empty()
    setup_button.text = "LIBRARY SETTINGS ▾" if setup_box.visible else "LIBRARY SETTINGS ▸"
    sendspin_toggle = _button("PLAYBACK SETUP ▸", "_toggle_sendspin")
    sendspin_box = VBoxContainer.new()
    add_child(sendspin_box)
    sendspin_box.hide()
    var explanation=Label.new()
    explanation.text="One-time setup: connect playback, approve pairing in Music Assistant if asked, then use Play. Music stays inside Kinegra Amp."
    explanation.autowrap=true
    sendspin_box.add_child(explanation)
    sendspin_advanced_toggle=_button("ADVANCED CONNECTION ▸", "_toggle_playback_advanced", sendspin_box)
    sendspin_advanced=VBoxContainer.new()
    sendspin_box.add_child(sendspin_advanced)
    sendspin_advanced.hide()
    var address_label=Label.new()
    address_label.text="Custom playback server (normally uses your library server)"
    address_label.autowrap=true
    sendspin_advanced.add_child(address_label)
    sendspin_endpoint=LineEdit.new()
    sendspin_endpoint.placeholder_text="ws://server-address:8927/sendspin"
    sendspin_endpoint.rect_min_size.y=48
    sendspin_advanced.add_child(sendspin_endpoint)
    _button("RESET TO LIBRARY SERVER", "_sendspin_use_ma_host", sendspin_advanced)
    sendspin_details=Label.new()
    sendspin_details.autowrap=true
    sendspin_advanced.add_child(sendspin_details)
    sendspin_trust=CheckBox.new()
    sendspin_trust.text="Allow music from my Music Assistant server on this local network"
    sendspin_trust.focus_mode=Control.FOCUS_ALL
    sendspin_box.add_child(sendspin_trust)
    if saved.has_section("sendspin"):
        sendspin_endpoint.text=str(saved.get_value("sendspin","endpoint",""))
        sendspin_trust.pressed=bool(saved.get_value("sendspin","trust_private_lan",false))
    var startrow=HBoxContainer.new()
    sendspin_box.add_child(startrow)
    sendspin_connect_button = _button("CONNECT PLAYBACK", "_sendspin_start", startrow)
    _button("DISCONNECT", "_sendspin_stop", startrow)
    var pairing=HBoxContainer.new()
    sendspin_box.add_child(pairing)
    _button("SHOW SETUP TOKEN", "_sendspin_reveal", sendspin_advanced)
    _button("FINISH PAIRING", "_sendspin_confirm", pairing)
    sendspin_status=Label.new()
    sendspin_status.text="Playback is not connected yet."
    sendspin_status.autowrap=true
    sendspin_box.add_child(sendspin_status)
    sendspin_hint=Label.new()
    sendspin_hint.autowrap=true
    sendspin_box.add_child(sendspin_hint)
    _button("CHECK CONNECTION", "_refresh_players", sendspin_advanced)
    sendspin_refresh_timer=Timer.new()
    sendspin_refresh_timer.one_shot=true
    add_child(sendspin_refresh_timer)
    sendspin_refresh_timer.connect("timeout",self,"_try_sendspin_refresh")
    playback_summary=_label("Playback: choose Play to set it up.")
    playback_summary.autowrap=true
    sendspin_token_dialog=AcceptDialog.new()
    sendspin_token_dialog.window_title="Pairing token  /  keep private"
    sendspin_token_dialog.rect_min_size=Vector2(520,200)
    add_child(sendspin_token_dialog)
    sendspin_token_label=Label.new()
    sendspin_token_label.autowrap=true
    sendspin_token_dialog.add_child(sendspin_token_label)
    sendspin_token_dialog.connect("popup_hide",self,"_clear_sendspin_token")
    pairing_code_dialog=AcceptDialog.new()
    pairing_code_dialog.window_title="Music Assistant pairing  /  keep private"
    pairing_code_dialog.get_ok().text="DISMISS"
    pairing_code_dialog.get_ok().rect_min_size=Vector2(160,52)
    add_child(pairing_code_dialog)
    pairing_code_label=Label.new()
    pairing_code_label.autowrap=true
    pairing_code_label.align=Label.ALIGN_CENTER
    var pin_font=DynamicFont.new()
    pin_font.font_data=load("res://assets/fonts/DejaVuSans.ttf")
    pin_font.size=28
    pairing_code_label.add_font_override("font",pin_font)
    pairing_code_dialog.add_child(pairing_code_label)
    pairing_code_dialog.connect("popup_hide",self,"_clear_pairing_code")
    var tabs = _row()
    _button("TRACKS", "_tracks", tabs)
    _button("ALBUMS", "_albums", tabs)
    _button("PLAYLISTS", "_playlists", tabs)
    var search_row = _row()
    search_edit = LineEdit.new()
    search_edit.placeholder_text = "Search your library"
    search_edit.max_length = 100
    search_edit.connect("text_entered",self,"_search_submitted")
    search_edit.rect_min_size.y = 48
    search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    search_row.add_child(search_edit)
    search_button=_button("SEARCH", "_search", search_row)
    results_label = _label("RESULTS  /  no page loaded")
    results_label.autowrap=true
    list = ItemList.new()
    list.rect_min_size = Vector2(280, 170)
    list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(list)
    list.connect("item_selected", self, "_select_index")
    list.connect("item_activated", self, "_activate_selection")
    action_rail=VBoxContainer.new()
    action_rail.add_constant_override("separation",6)
    add_child(action_rail)
    selection_label=Label.new()
    selection_label.text="SELECTED / choose a track or playlist"
    selection_label.autowrap=true
    selection_label.max_lines_visible=3
    selection_label.focus_mode=Control.FOCUS_ALL
    selection_label.rect_min_size.y=30
    selection_label.add_color_override("font_color",Color("82e6ce"))
    action_rail.add_child(selection_label)
    action_grid=GridContainer.new()
    action_grid.columns=2
    action_grid.add_constant_override("hseparation",8)
    action_grid.add_constant_override("vseparation",6)
    action_rail.add_child(action_grid)
    play_button=_button("PLAY","_play_on_player",action_grid)
    play_button.hint_tooltip="Play this selected track or playlist here; preserve the remaining queue."
    play_button.icon=load("res://assets/icons/transport-play.svg")
    preload("res://scripts/TransportStyle.gd").apply(play_button,false)
    add_queue_button=_button("ADD TO QUEUE","_queue_selected",action_grid)
    playlist_button=_button("OPEN PLAYLIST","_playlist_items",action_grid)
    view_queue_button=_button("VIEW QUEUE","_view_queue",action_grid)
    queue_all_button=_button("QUEUE PAGE (0)","_queue_all_shown",action_grid)
    _button("BACK TO LIST","_focus_selected_list",action_grid)
    add_queue_button.disabled=true
    queue_all_button.disabled=true
    play_button.disabled=true
    playlist_button.disabled=true
    var paging = _row()
    previous_button = _button("PREVIOUS", "_previous", paging)
    next_button = _button("NEXT", "_next", paging)
    previous_button.disabled = true
    next_button.disabled = true
    var page_tools=_row()
    refresh_page_button=_button("REFRESH","_refresh_page",page_tools)
    back_to_playlists_button=_button("PLAYLISTS","_back_to_playlists",page_tools)
    back_to_playlists_button.hint_tooltip="Return to the playlist library and its previous page."
    refresh_page_button.hint_tooltip="Read this page again. Playlist refresh requests a fresh read from Music Assistant."
    back_to_playlists_button.hide()
    var more = _row()
    confirm_button = _button("SHOW SELECTION", "_confirm", more)
    preview_button = _button("SHORT PREVIEW", "_preview", more)
    confirm_button.disabled = true
    preview_button.disabled = true
    status_label=Label.new()
    status_label.text="Select a playlist and press OK to open. Right moves to actions."
    status_label.autowrap=true
    status_label.rect_min_size.y=44
    action_rail.add_child(status_label)
    var other = _row()
    _button("CANCEL REQUEST", "_cancel", other)
    demo_button = _button("DEMO COLLECTIONS ▸", "_toggle_demos")
    demo_row = _row()
    _button("FICTIONAL ALBUMS", "_fictional_albums", demo_row)
    _button("FICTIONAL ARTISTS", "_fictional_artists", demo_row)
    demo_row.hide()
    _button("DISCONNECT / BACK", "_close")
    browser_box=VBoxContainer.new()
    browser_box.size_flags_vertical=Control.SIZE_EXPAND_FILL
    browser_box.add_constant_override("separation",5)
    add_child(browser_box)
    browse_nav=GridContainer.new();browse_nav.columns=4
    browse_nav.add_constant_override("hseparation",6);browse_nav.add_constant_override("vseparation",5)
    browser_box.add_child(browse_nav)
    for control in tabs.get_children():
        tabs.remove_child(control);browse_nav.add_child(control)
    for control in [setup_button,sendspin_toggle]:
        control.get_parent().remove_child(control);browse_nav.add_child(control)
    tabs.queue_free()
    for control in [search_row,results_label,list]:
        control.get_parent().remove_child(control);browser_box.add_child(control)
    browse_tools=GridContainer.new();browse_tools.columns=4
    browse_tools.add_constant_override("hseparation",6);browse_tools.add_constant_override("vseparation",5)
    browser_box.add_child(browse_tools)
    for row in [paging,page_tools]:
        for control in row.get_children():
            row.remove_child(control)
            browse_tools.add_child(control)
        row.queue_free()
    list.rect_min_size=Vector2(100,80)
    for control in browse_nav.get_children()+browse_tools.get_children():control.rect_min_size.y=36
    for control in action_grid.get_children():control.rect_min_size.y=40
    for control in search_row.get_children():control.rect_min_size.y=36
    search_edit.rect_min_size.y=36
    results_label.autowrap=true;results_label.max_lines_visible=3;results_label.rect_min_size.y=26
    status_label.max_lines_visible=2
    setup_button.text="SETTINGS";sendspin_toggle.text="PLAYBACK"

func _toggle_sendspin():
    sendspin_box.show()
    setup_box.hide()
    emit_signal("configuration_requested","playback")
    sendspin_toggle.text="PLAYBACK SETUP ▾" if sendspin_box.visible else "PLAYBACK SETUP ▸"
    if sendspin_box.visible and sendspin_endpoint.text.strip_edges().empty():
        _sendspin_use_ma_host()

func _toggle_playback_advanced():
    sendspin_advanced.visible=not sendspin_advanced.visible
    sendspin_advanced_toggle.text="ADVANCED CONNECTION ▾" if sendspin_advanced.visible else "ADVANCED CONNECTION ▸"

func _sendspin_use_ma_host():
    var policy=load("res://scripts/ConnectionPolicy.gd").new()
    var parsed=policy.origin(endpoint_edit.text.strip_edges().trim_suffix("/"),["http","https"],true)
    if parsed.empty():
        sendspin_status.text="Enter your Music Assistant server in Library settings first."
        return
    sendspin_endpoint.text="ws://"+str(parsed["host"])+":8927/sendspin"
    sendspin_trust.pressed=lan_trust.pressed

func _sendspin_start():
    if sendspin_endpoint.text.strip_edges().empty():_sendspin_use_ma_host()
    var address=sendspin_endpoint.text.strip_edges()
    var gate=load("res://scripts/SendspinExperienceFacade.gd").new()
    var valid=gate._valid_endpoint(address,sendspin_trust.pressed)
    gate.free()
    if not valid:
        sendspin_status.text="Allow music from your library server on this local network, then Connect playback. Check Advanced connection only if your server address is different."
        return false
    if not _save_connection_setting("sendspin","endpoint",address,"trust_private_lan",sendspin_trust.pressed):
        sendspin_status.text="Could not save settings; existing file was left untouched."
        return false
    emit_signal("sendspin_start_requested",address,sendspin_trust.pressed)
    return true

func _save_connection_setting(section,key,value,trust_key,trust_value):
    var saved=ConfigFile.new()
    var result=saved.load(settings_path)
    var existing=File.new()
    if existing.file_exists(settings_path):
        if result!=OK or existing.open(settings_path,File.READ)!=OK:
            return false
        var original_size=existing.get_len()
        existing.close()
        if original_size>0 and saved.get_sections().empty():
            return false
    saved.set_value(section,key,value)
    saved.set_value(section,trust_key,trust_value)
    var temp=settings_path+"."+str(OS.get_ticks_usec())+".tmp"
    var dir=Directory.new()
    if File.new().file_exists(temp) or saved.save(temp)!=OK:
        return false
    if dir.rename(temp,settings_path)!=OK:
        dir.remove(temp)
        return false
    return true
func _sendspin_stop(): emit_signal("sendspin_stop_requested")
func _sendspin_reveal(): emit_signal("sendspin_reveal_requested")
func _sendspin_confirm(): emit_signal("sendspin_confirm_requested")
func _sendspin_resume(): emit_signal("sendspin_command_requested","play")
func _sendspin_pause(): emit_signal("sendspin_command_requested","pause")
func _sendspin_next(): emit_signal("sendspin_command_requested","next")
func show_sendspin_token(token):
    if typeof(token)!=TYPE_STRING or token.empty() or token.length()>4096:
        sendspin_status.text="Connect playback first."
        return
    sendspin_token_label.text="In Music Assistant player settings, select Kinegra Amp and enter this token when requested. Treat it like a password.\n\n"+token
    sendspin_token_dialog.popup_centered(Vector2(720,260))
func _clear_sendspin_token():
    if sendspin_token_label!=null: sendspin_token_label.text=""
func show_pairing_code(code):
    if pairing_code_dialog==null or pairing_code_label==null: return
    if typeof(code)!=TYPE_STRING or code.length()!=6:
        clear_pairing_code()
        return
    for digit in code:
        if digit<"0" or digit>"9":
            clear_pairing_code()
            return
    pairing_code_label.text="Enter this private code in Music Assistant:\n\n"+code
    var viewport=get_viewport_rect().size
    pairing_code_dialog.popup_centered(Vector2(min(640, viewport.x-40), min(220, viewport.y-40)))
func _clear_pairing_code():
    if pairing_code_label!=null: pairing_code_label.text=""
func clear_pairing_code():
    _clear_pairing_code()
    if pairing_code_dialog!=null: pairing_code_dialog.hide()
func set_sendspin_status(state,detail,player_id=""):
    var previous=sendspin_player_id
    playback_state=str(state)
    if state in ["idle","error"]:
        clear_pairing_code()
        _clear_sendspin_token()
        if sendspin_token_dialog!=null:sendspin_token_dialog.hide()
    sendspin_paired=state in ["paired","receiving"]
    sendspin_player_id=str(player_id) if sendspin_paired else ""
    if sendspin_status!=null:
        sendspin_status.text="Playback is connected inside Kinegra Amp." if sendspin_paired else ("Connecting playback…" if state in ["connecting","pairing"] else (str(detail) if state=="error" else "Connect playback to listen inside Kinegra Amp."))
    if sendspin_details!=null:sendspin_details.text=str(state).to_upper()+" / "+str(detail)
    if sendspin_player_id!=previous:
        sendspin_play_requested=false
        _stop_sendspin_refresh()
        if not sendspin_player_id.empty():
            sendspin_refresh_target=sendspin_player_id
            sendspin_refresh_attempts=0
            sendspin_refresh_deadline=OS.get_ticks_msec()+12000
            sendspin_refresh_timer.start(0.1)
    _refresh_sendspin_play_here()
    if sendspin_paired:call_deferred("_try_connected_play")
    elif state in ["idle","error"]:cancel_pending_play()
func _stop_sendspin_refresh():
    sendspin_refresh_target=""
    if sendspin_refresh_timer!=null: sendspin_refresh_timer.stop()
func _try_sendspin_refresh():
    if sendspin_refresh_target.empty() or sendspin_refresh_target!=sendspin_player_id or not sendspin_paired:
        _stop_sendspin_refresh()
    elif OS.get_ticks_msec()>=sendspin_refresh_deadline or sendspin_refresh_attempts>=3 or catalog.token.empty():
        _stop_sendspin_refresh()
    elif catalog.request_node!=null:
        sendspin_refresh_timer.start(0.5)
    else:
        sendspin_refresh_attempts+=1
        catalog.discover_players()
        sendspin_refresh_timer.start(1.5)
    _refresh_sendspin_play_here()
func _refresh_sendspin_play_here():
    if play_button==null: return
    var item=_selected_item() if catalog!=null else {}
    var local_target=catalog.resolve_local_player(sendspin_player_id) if sendspin_paired else ""
    if play_button!=null:
        var selected=_selection_ready and item.get("provider")=="library" and item.get("media_type") in ["track","album","playlist"] and (item.get("media_type") in ["playlist","album"] or item.get("available",false)==true)
        play_button.disabled=offline_mode or not selected or item.empty() or catalog.token.empty() or (catalog.request_node!=null and catalog.request_context.get("kind")!="players")
        if add_queue_button!=null: add_queue_button.disabled=offline_mode or not selected or not item.get("media_type") in ["track","album","playlist"] or (item.get("media_type")=="track" and item.get("available",false)!=true) or catalog.token.empty() or (catalog.request_node!=null and catalog.request_context.get("kind")!="players")
        if queue_all_button!=null:
            var shown=_shown_queue_tracks()
            queue_all_button.text="QUEUE PAGE (%d)" % shown.size()
            queue_all_button.disabled=offline_mode or shown.empty() or catalog.token.empty() or catalog.request_node!=null
        play_button.text="PLAY"
    if view_queue_button!=null:view_queue_button.disabled=not sendspin_paired or library_disconnected
    if playback_summary!=null:
        playback_summary.text="Playback: ready inside Kinegra Amp." if not local_target.empty() else ("Playback: connected; checking the library connection." if sendspin_paired else "Playback connects automatically when you choose Play.")
    if sendspin_hint!=null:
        if not sendspin_paired:
            sendspin_hint.text="Choose Play. Playback connects automatically."
        elif sendspin_play_requested:
            sendspin_hint.text="Playback requested inside Kinegra Amp."
        elif not sendspin_refresh_target.empty():
            sendspin_hint.text="Checking the playback connection…"
        elif local_target.empty():
            sendspin_hint.text="The playback connection is not ready. Choose Play to check it."
        elif catalog.token.empty():
            sendspin_hint.text="Connect to the Music Assistant library first."
        elif catalog.request_node!=null:
            sendspin_hint.text="Waiting for the current library request to finish..."
        elif item.empty():
            sendspin_hint.text="Select a track or playlist to play."
        elif item.get("provider")!="library" or not item.get("media_type") in ["track","album","playlist"]:
            sendspin_hint.text="Choose a track or playlist from the Music Assistant library."
        else:
            sendspin_hint.text="Ready. Choose Play to listen inside Kinegra Amp."
func _local_play_ready():
    return catalog!=null and not offline_mode and sendspin_paired and not catalog.resolve_local_player(sendspin_player_id).empty()

func _sendspin_play_here():
    _refresh_sendspin_play_here()
    if not _local_play_ready(): return
    sendspin_play_requested=true
    var item=_selected_item()
    if not item.empty():emit_signal("sendspin_play_here_requested",item.duplicate(true))

func _shown_queue_tracks():
    var tracks=[]
    if catalog==null or offline_mode: return tracks
    for item in catalog.current_page.get("items",[]):
        if item.get("provider")=="library" and item.get("media_type")=="track" and item.get("available",false)==true:
            tracks.append(item.duplicate(true))
    return tracks

func _queue_selected():
    if catalog==null or offline_mode or not _selection_ready or not _restore_selected_identity():return
    pending_play_item.clear()
    var item=_selected_item()
    if not item.get("media_type") in ["track","album","playlist"]: return
    _enqueue_snapshot([item])

func _queue_all_shown():
    _enqueue_snapshot(_shown_queue_tracks())

func _enqueue_snapshot(media):
    if playback_owner!=null and playback_owner._web_queue_busy():
        status_label.text="A web queue request is in progress. Wait for its result."
        return
    if media.empty():return
    if catalog.request_node!=null and catalog.request_context.get("kind")!="players":
        status_label.text="A request is in progress. Wait for its result; nothing added again."
        return
    if not sendspin_paired:
        emit_signal("configuration_requested","playback")
        sendspin_box.show()
        sendspin_toggle.text="PLAYBACK SETUP ▾"
        sendspin_connect_button.grab_focus()
        status_label.text="Connect playback first, then add tracks. Nothing queued yet."
        return
    if not _session_matches():
        status_label.text="Playback changed. Connect this device again; nothing added."
        return
    if (catalog.request_node!=null and catalog.request_context.get("kind")=="players") or catalog.resolve_local_player(sendspin_player_id).empty():
        pending_queue_session=_session_identity()
        pending_queue_media=media.duplicate(true)
        pending_queue_client=sendspin_player_id
        if catalog.request_node!=null and catalog.request_context.get("kind")=="players":return
        if not catalog.discover_players():
            pending_queue_media.clear()
            pending_queue_client=""
            pending_queue_session=null
        return
    catalog.enqueue_local_media(sendspin_player_id,media)

func set_playback_active(active):
    if play_button!=null: preload("res://scripts/TransportStyle.gd").apply(play_button,active)

func _row():
    var row = HBoxContainer.new()
    add_child(row)
    return row

func focus_entry():
    if setup_box.visible:
        endpoint_edit.grab_focus()
    elif list.get_item_count() > 0:
        list.grab_focus()
    else:
        setup_button.grab_focus()

func _toggle_demos():
    demo_row.visible = not demo_row.visible
    demo_button.text = "DEMO COLLECTIONS ▾" if demo_row.visible else "DEMO COLLECTIONS ▸"

func _toggle_setup():
    setup_box.show()
    sendspin_box.hide()
    emit_signal("configuration_requested","library")
    setup_button.text = "LIBRARY SETTINGS ▾" if setup_box.visible else "LIBRARY SETTINGS ▸"

func _label(text):
    var label = Label.new()
    label.text = text
    add_child(label)
    return label

func _button(text, method, parent=null):
    var button = Button.new()
    button.text = text
    button.clip_text=true
    button.hint_tooltip=text
    button.rect_min_size=Vector2(100,48)
    # Fill the row so clipped labels cannot collapse buttons to slivers.
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.focus_mode = Control.FOCUS_ALL
    (self if parent == null else parent).add_child(button)
    button.connect("pressed", self, method)
    return button

func _fictional_albums():
    # Cancel any older MA browse locally before showing fictional rows.
    catalog.cancel()
    offline_kind = "albums"
    offline_mode = true
    offset = 0
    _browse_fictional()

func _fictional_artists():
    # Cancel any older MA browse locally before showing fictional rows.
    catalog.cancel()
    offline_kind = "artists"
    offline_mode = true
    offset = 0
    _browse_fictional()

func _browse_fictional():
    _selection_ready=false
    var result = offline_catalog.browse(offline_kind, search_edit.text, offset)
    list.clear()
    for item in result["items"]:
        list.add_item(item["name"])
    previous_button.disabled = offset == 0
    next_button.disabled = not result["has_more"]
    playlist_button.disabled = true
    confirm_button.disabled = true
    preview_button.disabled = true
    play_button.disabled = true
    selection_label.text = "SELECTED  /  choose a fictional group"
    results_label.text = "FICTIONAL OFFLINE %s / %d OF %d" % [offline_kind.to_upper(), result["items"].size(), result["total"]]
    status_label.text = "Offline fictional grouping labels for four original Omega recordings. No Music Assistant query or playback."

func _notification(what):
    if what in [MainLoop.NOTIFICATION_APP_PAUSED,MainLoop.NOTIFICATION_WM_FOCUS_OUT]:
        _clear_pending_credential()
        if token_edit!=null: token_edit.text=""
        if catalog!=null and is_instance_valid(catalog):
            catalog.close()
            emit_signal("credential_session_closed","inactive" if what==MainLoop.NOTIFICATION_APP_PAUSED else "focus_lost")
        _clear_sendspin_token()
        if sendspin_token_dialog!=null: sendspin_token_dialog.hide()
        clear_pairing_code()

func _credential_store():
    if OS.get_environment("METHEXIS_SOURCE_TEST")=="1" and credential_store_override!=null:
        return credential_store_override
    if OS.get_name()=="Android" and Engine.has_singleton("ShieldAmpTokenStore"):
        return Engine.get_singleton("ShieldAmpTokenStore")
    return null

func _credential_endpoint():
    var parsed=catalog.policy.origin(endpoint_edit.text.strip_edges().trim_suffix("/"),["http","https"],lan_trust.pressed)
    return "" if parsed.empty() else str(parsed["prefix"]).to_lower()

func _clear_pending_credential():
    pending_remember_token=""
    pending_remember_endpoint=""
    pending_remember_epoch=-1
    pending_session_token=""
    pending_session_origin=""
    pending_session_epoch=-1

func _read_provisioned_token():
    var vault=_credential_store()
    if vault==null:
        token_storage_label.text="Secure access unavailable. Enter a token for this session; saved access was left untouched."
        return ""
    # Android JNISingleton methods are dynamic; has_method() returns false.
    # The encrypted record binds access to its server. Only the original saved
    # connection may bind an older unbound record during verified migration.
    var requested=_credential_endpoint()
    var bound=str(vault.tokenEndpoint())
    if bound.empty() and str(vault.storageStatus())=="not_configured":
        token_storage_label.text="No saved library access. Enter a token to connect."
        return ""
    if bound.empty(): bound=legacy_saved_token_endpoint
    if requested.empty() or bound.empty() or requested!=bound:
        token_storage_label.text="Saved access belongs to another or unknown server. Enter this server's token; saved access was not sent."
        return ""
    var credential=str(vault.loadTokenForEndpoint(requested))
    var state=str(vault.storageStatus())
    if state in ["secure_no_legacy","migrated_no_legacy"] and not credential.empty():
        legacy_saved_token_endpoint=requested
        if not _logged_token_storage:
            if state=="secure_no_legacy":print("TOKEN_STORAGE=secure_no_legacy")
            elif state=="migrated_no_legacy":print("TOKEN_STORAGE=migrated_no_legacy")
            _logged_token_storage=true
        token_storage_label.text="Access encrypted for this server; no original plaintext token remains."
        return credential
    credential=""
    if state=="not_configured":
        token_storage_label.text="No saved library access. Enter a token to connect."
    elif state=="endpoint_mismatch":
        token_storage_label.text="Saved access belongs to another server. Enter this server's token."
    elif state=="legacy_conflict":
        token_storage_label.text="Saved and original access conflict. Neither was used. Forget saved access, then enter a replacement token."
    elif state=="secure_legacy_remains":
        token_storage_label.text="Secure copy verified, but original plaintext cleanup failed. Retry or Forget saved access; no connection started."
    else:
        token_storage_label.text="Secure access could not be read. Saved records were left untouched. Retry or Forget saved access and enter a replacement."
    return ""

func connect_saved_if_needed():
    if not library_disconnected and catalog.token.empty() and not endpoint_edit.text.strip_edges().empty():
        _connect_catalog()

func _connect_catalog():
    offline_mode=false
    _clear_pending_credential()
    var credential=token_edit.text.strip_edges()
    var typed=not credential.empty()
    if credential.empty() and not library_disconnected and session_credential_provider!=null and is_instance_valid(session_credential_provider):
        credential=session_credential_provider._library_credential(false)
    if credential.empty(): credential=_read_provisioned_token()
    if credential.empty():
        token_edit.text=""
        status_label.text="Enter library access for this server, or resolve the saved-access message above."
        return false
    var accepted=catalog.configure(endpoint_edit.text,credential,[],lan_trust.pressed)
    if accepted:
        pending_session_token=credential
        pending_session_origin=_credential_endpoint()
        pending_session_epoch=catalog.epoch
    if accepted and typed and remember_access.pressed:
        pending_remember_token=credential
        pending_remember_endpoint=_credential_endpoint()
        pending_remember_epoch=catalog.epoch
        token_storage_label.text="Access is in memory. It will be saved only after the server accepts a library request."
    elif accepted and typed:
        token_storage_label.text="Access stays in memory for this session. Enable Remember access to save it securely after the server accepts it."
    credential=""
    token_edit.text=""
    if accepted:
        library_disconnected=false
        setup_box.visible=false
        setup_button.text="LIBRARY SETTINGS ▸"
        if not _save_connection_setting("connection","endpoint",endpoint_edit.text.strip_edges(),"trust_private_http",lan_trust.pressed):
            status_label.text="Connected; settings could not be saved. Existing file was left untouched."
        kind="tracks"
        offset=0
        var restored=false
        if playback_owner!=null and playback_owner.music_ui!=null:
            restored=restore_library_location(playback_owner.music_ui.saved_library_location(catalog.endpoint))
        if not restored:catalog.browse(kind)
    else:
        emit_signal("credential_session_closed","invalid_access")
    return accepted

func _credential_state(state,_detail):
    if state in ["auth_expired","permission_denied"]:
        _disconnect_library("auth_failed")
        token_storage_label.text="Library access was rejected. Enter a valid replacement token, or Forget saved access. Saved playback pairing is unchanged."
        status_label.text="Library disconnected: access expired or permissions were refused."
        return
    if state in ["cancelled","not_configured","disconnected","malformed_reply","command_failed","stale_reply","invalid_endpoint","auth_required"]:
        _clear_pending_credential()
        return
    if state!="ready":return
    # configure() also emits ready synchronously, before these pending fields
    # are armed. Only a later accepted server response authorizes playback RAM.
    if not pending_session_token.empty():
        if library_disconnected or catalog.epoch!=pending_session_epoch or _credential_endpoint()!=pending_session_origin or catalog.token!=pending_session_token:
            _clear_pending_credential()
            return
        emit_signal("credential_session_authorized",pending_session_token,pending_session_origin)
        pending_session_token=""
        pending_session_origin=""
        pending_session_epoch=-1
    if pending_remember_token.empty():return
    if catalog.epoch!=pending_remember_epoch or _credential_endpoint()!=pending_remember_endpoint or catalog.token!=pending_remember_token:
        _clear_pending_credential()
        return
    var vault=_credential_store()
    var endpoint=pending_remember_endpoint
    var saved=false
    if vault!=null: saved=bool(vault.storeTokenForEndpoint(pending_remember_token,endpoint))
    _clear_pending_credential()
    remember_access.pressed=false
    if saved:
        legacy_saved_token_endpoint=endpoint
        token_storage_label.text="Access saved encrypted for this server; no original plaintext token remains."
    else:
        token_storage_label.text="Could not finish secure storage. Connected for this session. Enter the token again with Remember to retry, or Forget saved access."

func _disconnect_library(reason="disconnect"):
    cancel_pending_play()
    _clear_pending_credential()
    library_disconnected=true
    _stop_sendspin_refresh()
    _cancel()
    catalog.close()
    token_edit.text=""
    remember_access.pressed=false
    status_label.text="Library disconnected on this device. Saved access and playback pairing are unchanged."
    emit_signal("credential_session_closed",reason)

func _library_endpoint_changed(_text):
    _disconnect_library("server_change")
    token_storage_label.text="Server changed. Enter its token; saved access will only be used with its original server."

func _library_trust_changed(_trusted):
    _disconnect_library("trust_change")
    token_storage_label.text="Connection trust changed. Review the server and explicitly Connect library again."

func _forget_saved_access():
    token_edit.text=""
    forget_access_dialog.popup_centered(Vector2(720,300))

func _confirm_forget_saved_access():
    _disconnect_library("forget")
    var vault=_credential_store()
    if vault==null or not bool(vault.forgetToken()):
        token_storage_label.text="Could not finish removing saved access. The current session is disconnected. Retry Forget saved access before reconnecting."
        return false
    legacy_saved_token_endpoint=""
    token_storage_label.text="Saved library access removed from this device. Playback pairing and connection settings are unchanged."
    status_label.text="Forgot local library access. Revoke the token in Music Assistant if you also want to invalidate it on the server."
    emit_signal("credential_forgotten")
    return true

func _search_submitted(_query):
    _search()

func _albums():
    if kind=="playlist_items":search_edit.text=""
    offline_mode=false
    kind="albums"
    _search()

func _tracks():
    if kind=="playlist_items":search_edit.text=""
    offline_mode=false
    kind="tracks"
    _search()

func _playlists():
    if kind=="playlist_items":search_edit.text=""
    offline_mode=false
    kind="playlists"
    _search()

func _search():
    if offline_mode:
        offset=0
        _browse_fictional()
    elif kind=="playlist_items":
        catalog.playlist_page(0,search_edit.text)
    else:
        catalog.browse(kind,search_edit.text,0)

func _previous():
    if offline_mode:
        offset=max(0,offset-offline_catalog.PAGE_SIZE)
        _browse_fictional()
    elif kind=="playlist_items":
        catalog.playlist_page(max(0,offset-catalog.PAGE_SIZE))
    else:
        catalog.browse(kind,str(catalog.current_page.get("search","")),max(0,offset-catalog.PAGE_SIZE))

func _next():
    if offline_mode:
        offset+=offline_catalog.PAGE_SIZE
        _browse_fictional()
    elif kind=="playlist_items":
        catalog.playlist_page(offset+catalog.PAGE_SIZE)
    else:
        catalog.browse(kind,str(catalog.current_page.get("search","")),offset+catalog.PAGE_SIZE)

func _playlist_items():
    if offline_mode or not _restore_selected_identity():return
    if kind in ["playlists","albums"]:library_playlist_return={"offset":offset,"search":str(catalog.current_page.get("search","")),"kind":kind}
    search_edit.text=""
    if _selected_item().get("media_type")=="album":catalog.album_items()
    else:catalog.playlist_items()

func _refresh_page():
    if offline_mode:
        _browse_fictional()
    elif kind=="playlist_items" or page_request.get("kind")=="playlist_items":
        catalog.refresh_playlist()
    else:
        catalog.browse(str(page_request.get("kind",kind)),str(page_request.get("search","")),int(page_request.get("offset",offset)))

func _back_to_playlists():
    if offline_mode:return
    kind=str(library_playlist_return.get("kind","playlists"))
    search_edit.text=str(library_playlist_return.get("search",""))
    catalog.browse(kind,search_edit.text,int(library_playlist_return.get("offset",0)))

func _select_index(index):
    if offline_mode:
        if index >= 0 and index < list.get_item_count():
            selection_label.text = "SELECTED  /  " + list.get_item_text(index)
            status_label.text = "Fictional offline group. No audio started."
        return
    catalog.select_index(index)

func _confirm():
    if offline_mode:
        return
    var selected = catalog.selection()
    if not selected.empty():
        emit_signal("media_selected", selected)

func _preview():
    if offline_mode:
        return
    # A deliberately separate explicit control; no click on row autoplays.
    var selected = catalog.selection()
    if selected.empty() or selected.get("media_type") != "track" or not selected.get("available", false):
        status_label.text = "Choose a fresh playable track first; no audio started."
        return
    emit_signal("preview_requested", selected)

func _refresh_players():
    if not catalog.token.empty():
        catalog.discover_players()

func _on_players(players):
    var queued=pending_queue_media.duplicate(true)
    var queued_client=pending_queue_client
    var queued_session=pending_queue_session
    pending_queue_media.clear()
    pending_queue_client=""
    pending_queue_session=null
    if not sendspin_refresh_target.empty() and not catalog.resolve_local_player(sendspin_refresh_target).empty():
        _stop_sendspin_refresh()
    _refresh_sendspin_play_here()
    _try_connected_play()
    if not queued.empty():
        if sendspin_paired and queued_client==sendspin_player_id and queued_session==_session_identity() and _session_matches():
            catalog.enqueue_local_media(queued_client,queued)
        else:
            status_label.text="Playback changed; nothing was queued."

    if not pending_play_item.empty():
        var pending=pending_play_item.duplicate(true)
        pending_play_item.clear()
        var same=pending_play_session==_session_identity() and _session_matches() and pending_play_client==sendspin_player_id and pending.get("item_id")==_selected_item().get("item_id") and pending.get("media_type")==_selected_item().get("media_type")
        pending_play_client=""
        pending_play_session=null
        if same and _local_play_ready():emit_signal("sendspin_play_here_requested",pending)

func _play_on_player():
    if not _restore_selected_identity():return
    pending_queue_media.clear()
    # The primary library Play action shares the exact local Sendspin route guard.
    # A Cast receiver named Shield is never a fallback.
    _refresh_sendspin_play_here()
    if play_button.disabled:return
    if not sendspin_paired:
        if not connect_play_item.empty():return
        connect_play_item=_selected_item().duplicate(true)
        connect_play_epoch=catalog.epoch
        connect_play_origin=_credential_endpoint()
        connect_play_deadline=OS.get_ticks_msec()+150000
        status_label.text="Waiting for audio. Approve pairing if asked."
        if playback_owner!=null:playback_owner._prepare_stream_visuals()
        if not _sendspin_start():
            cancel_pending_play()
            emit_signal("configuration_requested","playback")
            sendspin_box.show()
            sendspin_connect_button.grab_focus()
        else:
            connect_play_endpoint=sendspin_endpoint.text.strip_edges()
            connect_play_facade=_session_identity()
            connect_play_client=_playback_client_id()
        return
    if not _session_matches():
        status_label.text="Playback changed. Connect this device again; no play request sent."
        return
    if (catalog.request_node!=null and catalog.request_context.get("kind")=="players") or catalog.resolve_local_player(sendspin_player_id).empty():
        pending_play_session=_session_identity()
        pending_play_item=_selected_item()
        pending_play_client=sendspin_player_id
        if catalog.request_node==null:_refresh_players()
        status_label.text="Checking this device’s playback route, then playing your selection."
        return
    _sendspin_play_here()

func cancel_pending_play():
    pending_play_item.clear()
    pending_play_client=""
    pending_play_session=null
    connect_play_item.clear()
    connect_play_epoch=-1
    connect_play_origin=""
    connect_play_deadline=0
    connect_play_facade=null
    connect_play_endpoint=""
    connect_play_client=""

func _try_connected_play():
    if connect_play_item.empty():return false
    var selected=_selected_item()
    if OS.get_ticks_msec()>=connect_play_deadline or library_disconnected or catalog.epoch!=connect_play_epoch or _credential_endpoint()!=connect_play_origin or selected.get("item_id")!=connect_play_item.get("item_id") or selected.get("provider")!=connect_play_item.get("provider") or selected.get("media_type")!=connect_play_item.get("media_type"):
        cancel_pending_play()
        return false
    if connect_play_endpoint!=sendspin_endpoint.text.strip_edges() or (playback_owner!=null and (connect_play_facade!=_session_identity() or connect_play_client.empty() or connect_play_client!=_playback_client_id())):
        cancel_pending_play()
        return false
    if not sendspin_paired or not _session_matches() or not _local_play_ready():return false
    var requested=connect_play_item.duplicate(true)
    cancel_pending_play() # Consume before callback: never retry an uncertain mutation.
    sendspin_play_requested=true
    emit_signal("sendspin_play_here_requested",requested)
    return true

func restore_library_location(location):
    if typeof(location)!=TYPE_DICTIONARY or location.empty() or catalog.token.empty():return false
    var mode=str(location.get("kind","tracks"))
    var page=int(location.get("offset",0))
    if page<0 or page>catalog.MAX_BROWSE_OFFSET:return false
    restoring_library_location=true
    search_edit.text=""
    if mode=="playlist_items":
        var item=str(location.get("playlist_id",""))
        if item.empty() or not item.is_valid_integer() or item.length()>18:
            restoring_library_location=false
            return false
        restore_playlist_offset=page
        library_playlist_return={"offset":int(location.get("return_offset",0)),"search":"","kind":"albums" if location.get("collection_type")=="album" else "playlists"}
        if catalog.restore_playlist_context(item,str(location.get("collection_type","playlist"))):return true
    elif mode in ["tracks","albums","playlists"]:
        kind=mode
        if catalog.browse(mode,"",page):return true
    restoring_library_location=false
    restore_playlist_offset=-1
    return false

func _restore_playlist_page(page):
    if not catalog.playlist_page(page):restoring_library_location=false

func _on_selection(item):
    if not connect_play_item.empty() and (item.get("item_id")!=connect_play_item.get("item_id") or item.get("media_type")!=connect_play_item.get("media_type")):cancel_pending_play()
    selected_item=item.duplicate(true)
    selected_epoch=catalog.epoch
    selected_page=page_generation
    _selection_ready=true
    sendspin_play_requested=false
    selection_label.text = "SELECTED / OK FOR FULL TITLE\n" + str(item.get("name", ""))
    selection_label.hint_tooltip=str(item.get("name",""))
    playlist_button.disabled = not item.get("media_type") in ["playlist","album"]
    playlist_button.text="OPEN ALBUM" if item.get("media_type")=="album" else "OPEN PLAYLIST"
    confirm_button.disabled = false
    preview_button.disabled = item.get("media_type") != "track" or not item.get("available", false)
    status_label.text = "OK opens this collection. Right: Play / Add to Queue." if item.get("media_type") in ["album","playlist"] else "OK plays this track. Right: Add to Queue."
    _refresh_sendspin_play_here()

func _on_state(_state, detail):
    var page_kind=str(catalog.request_context.get("kind","")) if catalog!=null else ""
    if page_kind in ["tracks","albums","playlists","playlist_items"]:
        if _state=="loading":
            page_request={"kind":page_kind,"offset":catalog.request_context.get("offset",0),"search":catalog.request_context.get("search","")}
            list.clear()
            previous_button.disabled=true
            next_button.disabled=true
            refresh_page_button.disabled=true
            results_label.text="LOADING %s / PAGE %d" % ["PLAYLIST TRACKS" if page_kind=="playlist_items" else page_kind.to_upper(),int(page_request.offset/catalog.PAGE_SIZE)+1]
        elif _state in ["disconnected","malformed_reply","command_failed","stale_reply","auth_expired","permission_denied"]:
            list.clear()
            previous_button.disabled=true
            next_button.disabled=true
            refresh_page_button.disabled=false
            refresh_page_button.text="RETRY"
            results_label.text="PAGE NOT LOADED / RETRY OR CHOOSE A COLLECTION"
    if confirm_button != null and ((_state=="loading" and page_kind in ["tracks","albums","playlists","playlist_items"]) or _state in ["auth_expired","permission_denied","cancelled","not_configured"]):
        _selection_ready=false
        selected_item.clear()
        pending_play_item.clear()
        pending_play_client=""
        pending_play_session=null
        confirm_button.disabled = true
        playlist_button.disabled = true
        preview_button.disabled = true
        if selection_label != null:
            selection_label.text = "SELECTED  /  choose a track or playlist"
        if play_button != null:
            play_button.disabled = true
    if _state in ["auth_expired","permission_denied","cancelled","not_configured","disconnected","malformed_reply","unsafe_route","invalid_request"]:
        pending_queue_media.clear()
        pending_queue_client=""
        pending_queue_session=null
    if _state=="queue_added":
        _selection_ready=not _selected_item().empty()
        view_queue_button.grab_focus()
    if status_label != null:
        status_label.text = detail
        status_label.hint_tooltip=detail
    _refresh_sendspin_play_here()

func _on_page(page):
    if restoring_library_location and page.get("kind")=="playlist_items" and restore_playlist_offset>0 and int(page.get("offset",0))==0:
        var requested_offset=restore_playlist_offset
        restore_playlist_offset=-1
        call_deferred("_restore_playlist_page",requested_offset)
    else:
        restoring_library_location=false
        restore_playlist_offset=-1
    pending_queue_media.clear()
    pending_queue_client=""
    pending_queue_session=null
    _selection_ready=false
    selected_item.clear()
    pending_play_item.clear()
    pending_play_client=""
    pending_play_session=null
    page_generation+=1
    offline_mode = false
    list.clear()
    selection_label.text = "SELECTED  /  choose a track or playlist"
    play_button.disabled = true
    for item in page["items"]:
        list.add_item(item["name"])
    kind=str(page.get("kind","tracks"))
    offset=int(page.get("offset",0))
    page_request={"kind":kind,"offset":offset,"search":page.get("search","")}
    previous_button.disabled=offset==0
    next_button.disabled=not page.get("may_have_more",false)
    refresh_page_button.disabled=false
    refresh_page_button.text="REFRESH"
    back_to_playlists_button.visible=kind=="playlist_items"
    back_to_playlists_button.text="ALBUMS" if catalog.playlist_context.get("media_type")=="album" else "PLAYLISTS"
    search_edit.placeholder_text=("Filter album tracks" if catalog.playlist_context.get("media_type")=="album" else "Filter playlist tracks") if kind=="playlist_items" else "Search "+kind+" by name"
    playlist_button.disabled=true
    confirm_button.disabled=true
    preview_button.disabled=true
    results_label.text=_page_summary(page)
    results_label.hint_tooltip=_page_summary_detail(page)
    if list.get_item_count()>0:
        list.select(0)
        _select_index(0)
    if not catalog.token.empty() and catalog.request_node==null:catalog.discover_players()

func _page_summary(page):
    var count=page.get("items",[]).size()
    var number=int(int(page.get("offset",0))/catalog.PAGE_SIZE)+1
    if page.get("kind")=="playlist_items":
        var matches=int(page.get("matched_count",count))
        var pages=max(1,int(ceil(float(matches)/catalog.PAGE_SIZE)))
        var text="Page %d/%d • %d shown • %d retrieved" % [number,pages,count,int(page.get("returned_count",count))]
        if not str(page.get("search","")).empty():text+=" • %d matches" % matches
        if page.get("truncated",false):text+="\nPreview capped at %d" % int(page.get("preview_limit",catalog.MAX_PLAYLIST_ITEMS))
        return text+" • Search filters this collection"
    var text="Page %d • %d %s" % [number,count,str(page.get("kind","tracks"))]
    if int(page.get("total_count",-1))>=0:text+=" • %d total" % int(page.total_count)
    if count==0 and int(page.get("offset",0))>0:text+="\nCollection changed? Try Previous."
    if page.get("at_offset_limit",false):text+="\nBrowse limit reached; use Search."
    return text

func _page_summary_detail(page):
    var count=page.get("items",[]).size()
    var page_offset=int(page.get("offset",0))
    var begin=page_offset+1 if count>0 else 0
    var ending=page_offset+count if count>0 else 0
    var number=int(page_offset/catalog.PAGE_SIZE)+1
    if page.get("kind")=="playlist_items":
        var matched=int(page.get("matched_count",count))
        var pages=max(1,int(ceil(float(matched)/float(catalog.PAGE_SIZE))))
        var text="PLAYLIST TRACKS / PAGE %d OF %d / %d–%d SHOWN / %d RETURNED BY MUSIC ASSISTANT / PROVIDER TOTAL UNKNOWN" % [number,pages,begin,ending,int(page.get("returned_count",count))]
        if not str(page.get("search","")).empty():text+=" / %d MATCHES IN PREVIEW" % matched
        if page.get("truncated",false):text+=" / PREVIEW LIMIT %d ITEMS" % int(page.get("preview_limit",catalog.MAX_PLAYLIST_ITEMS))
        return text
    var text="%s / PAGE %d / %d–%d SHOWN" % [str(page.get("kind","tracks")).to_upper(),number,begin,ending]
    var total=int(page.get("total_count",-1))
    text+=" / %d TOTAL" % total if total>=0 else " / TOTAL UNKNOWN"
    if count==0 and page_offset>0:text+=" / COLLECTION MAY HAVE CHANGED; TRY PREVIOUS"
    elif page.get("may_have_more",false):text+=" / NEXT CHECKS FOR MORE"
    if page.get("at_offset_limit",false):text+=" / BROWSE LIMIT REACHED; USE SEARCH"
    return text

func _cancel():
    _clear_pending_credential()
    pending_queue_media.clear()
    pending_queue_client=""
    pending_queue_session=null
    _selection_ready=false
    catalog.cancel()
    list.clear()
    results_label.text = "RESULTS  /  cancelled"
    selection_label.text = "SELECTED  /  choose a track or playlist"
    play_button.disabled = true
    confirm_button.disabled = true
    playlist_button.disabled = true
    preview_button.disabled = true

func _close():
    cancel_pending_play()
    _clear_pending_credential()
    pending_queue_media.clear()
    pending_queue_client=""
    pending_queue_session=null
    _selection_ready=false
    selected_item.clear()
    pending_play_item.clear()
    pending_play_client=""
    pending_play_session=null
    _stop_sendspin_refresh()
    clear_pairing_code()
    _clear_sendspin_token()
    if sendspin_token_dialog!=null: sendspin_token_dialog.hide()
    token_edit.text = ""
    catalog.close()
    emit_signal("credential_session_closed","library_closed")
    list.clear()
    results_label.text = "RESULTS  /  disconnected"
    selection_label.text = "SELECTED  /  choose a track or playlist"
    play_button.disabled = true
    confirm_button.disabled = true
    playlist_button.disabled = true
    preview_button.disabled = true
    emit_signal("close_requested")

func play_focus_target():
    for control in [play_button,playlist_button,add_queue_button,view_queue_button,queue_all_button,confirm_button]:
        if control!=null and control.is_visible_in_tree() and not control.disabled:
            return control
    return null

func _selected_item():
    if catalog==null or catalog.token.empty() or selected_epoch!=catalog.epoch or selected_page!=page_generation or selected_item.empty():return {}
    for row in catalog.current_page.get("items",[]):
        if row.get("provider")==selected_item.get("provider") and row.get("media_type")==selected_item.get("media_type") and str(row.get("item_id"))==str(selected_item.get("item_id")):return selected_item.duplicate(true)
    return {}

func _focus_selected_list():
    list.grab_focus()
    list.ensure_current_is_visible()

func _view_queue():emit_signal("view_queue_requested")

func _activate_selection(index):
    _select_index(index)
    if offline_mode:return
    var item=_selected_item()
    if item.get("media_type") in ["playlist","album"]:_playlist_items()
    elif not item.empty():
        _play_on_player() # Select is Play. Add remains an explicit separate action.

func _restore_selected_identity():
    var item=_selected_item()
    if item.empty():
        status_label.text="Selection changed or expired. Choose a visible item again."
        return false
    var rows=catalog.current_page.get("items",[])
    for i in range(rows.size()):
        if rows[i].get("provider")==item.get("provider") and rows[i].get("media_type")==item.get("media_type") and str(rows[i].get("item_id"))==str(item.get("item_id")):return catalog.select_index(i)
    return false

func _playback_client_id():
    var facade=_session_identity()
    if facade==null or not is_instance_valid(facade) or facade.client==null:return ""
    var state=facade.client.status()
    if typeof(state)!=TYPE_DICTIONARY or typeof(state.get("client_id"))!=TYPE_STRING:return ""
    var identity=state.client_id
    return identity if not identity.empty() and identity.length()<=200 and not "://" in identity else ""

func _session_identity():
    return playback_owner.sendspin_facade if playback_owner!=null and is_instance_valid(playback_owner) else null
func _session_matches():
    if playback_owner==null:return true # Standalone catalog fixtures have no SDK owner.
    if not is_instance_valid(playback_owner):return false
    return str(playback_owner._sendspin_controls().get("client_id",""))==sendspin_player_id and not library_disconnected

func action_to_right(control):
    # Horizontal movement stays in this row. Full-width selected-title labels
    # remain reachable with Up, never between Play and Add.
    var controls=action_grid.get_children()
    var index=controls.find(control)
    if index<0:return null
    if index%action_grid.columns==action_grid.columns-1:return control
    if index+1>=controls.size():return control
    var adjacent=controls[index+1]
    if not (adjacent is Control) or adjacent.focus_mode==Control.FOCUS_NONE or not adjacent.is_visible_in_tree() or (adjacent is BaseButton and adjacent.disabled):return control
    return adjacent
