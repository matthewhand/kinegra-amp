extends Node
# Only media_player. entities are accepted. Godot 3.6 HA websocket. Never hardcode or log long-lived tokens.
signal connectivity(connected, detail)
signal track_changed(track)
signal command_result(success, description)

const DEFAULT_ENTITY = ""
const MAX_PENDING_COMMANDS = 16
var policy = preload("res://scripts/ConnectionPolicy.gd").new()
var deadline = 0
var entity_id = DEFAULT_ENTITY
var _token = ""
var _client = null
var _request_id = 1
var _pending_commands = {}
var connected = false
var track = {}

func _ready():
    set_process(true)

func start(token_value, selected_entity, endpoint="", trust_private_cleartext=false):
    stop()
    var address = str(endpoint).strip_edges()
    if not address.ends_with("/api/websocket"):
        emit_signal("connectivity", false, "Set a HA websocket endpoint ending /api/websocket")
        return
    var origin = address.trim_suffix("/api/websocket")
    if policy.origin(origin, ["ws", "wss"], trust_private_cleartext).empty():
        emit_signal("connectivity", false, "Use WSS, or explicitly trust private LAN cleartext")
        return
    _token = str(token_value).strip_edges()
    entity_id = str(selected_entity).strip_edges()
    var entity_pattern = RegEx.new()
    entity_pattern.compile("^media_player\\.[a-z0-9_]{1,100}$")
    if entity_pattern.search(entity_id) == null or _token.empty():
        emit_signal("connectivity", false, "Enter a HA token and a media_player entity")
        _token = ""
        return
    _client = WebSocketClient.new()
    _client.connect("connection_established", self, "_socket_opened")
    _client.connect("connection_closed", self, "_socket_closed")
    _client.connect("connection_error", self, "_socket_error")
    _client.connect("data_received", self, "_socket_packet")
    deadline = OS.get_ticks_msec() + 10000
    var error = _client.connect_to_url(address)
    if error != OK:
        stop()
        emit_signal("connectivity", false, "WebSocket open failed")
    else:
        emit_signal("connectivity", false, "Connecting to Home Assistant...")

func stop():
    connected = false
    _pending_commands.clear()
    if _client != null:
        _client.disconnect_from_host(1000, "Disconnect")
        _client = null
    _token = ""

func _process(_delta):
    if _client != null:
        _client.poll()
        if not connected and OS.get_ticks_msec() >= deadline:
            stop()
            emit_signal("connectivity", false, "HA connection/authentication timeout; retry")
    for id in _pending_commands.keys():
        if OS.get_ticks_msec() >= _pending_commands[id]["deadline"]:
            emit_signal("command_result", false, _pending_commands[id]["label"] + " timed out")
            _pending_commands.erase(id)

func _socket_opened(_protocol = ""):
    # HA sends auth_required. Do not transmit credentials preemptively.
    emit_signal("connectivity", false, "WebSocket open; authenticating...")

func _socket_closed(_was_clean = false):
    stop()
    emit_signal("connectivity", false, "HA disconnected; reconnect manually")

func _socket_error():
    stop()
    emit_signal("connectivity", false, "HA connection error; reconnect manually")

func _send(data):
    if _client == null:
        return false
    var peer = _client.get_peer(1)
    if peer == null:
        return false
    return peer.put_packet(to_json(data).to_utf8()) == OK

func _request(data, label = ""):
    var id = _request_id
    _request_id += 1
    data["id"] = id
    if not label.empty():
        if _pending_commands.size() >= MAX_PENDING_COMMANDS:
            emit_signal("command_result", false, "Too many outstanding commands")
            return
        _pending_commands[id] = {"label": label, "deadline": OS.get_ticks_msec() + 10000}
    if not _send(data) and not label.empty():
        _pending_commands.erase(id)
        emit_signal("command_result", false, "HA command could not be sent")

func _socket_packet():
    if _client == null:
        return
    var raw = _client.get_peer(1).get_packet()
    if raw.size() > 1048576:
        stop()
        emit_signal("connectivity", false, "HA reply exceeded limit")
        return
    var packet = raw.get_string_from_utf8()
    var obj = parse_json(packet)
    if typeof(obj) != TYPE_DICTIONARY:
        return
    match obj.get("type", ""):
        "auth_required":
            _send({"type": "auth", "access_token": _token})
        "auth_ok":
            connected = true
            _token = "" # HA session is authenticated; no copy retained in HAApi.
            emit_signal("connectivity", true, "Connected to Home Assistant")
            _request({"type": "get_states"})
            _request({"type": "subscribe_events", "event_type": "state_changed"})
        "auth_invalid":
            emit_signal("connectivity", false, "Invalid HA token")
            stop()
        "result":
            var id = int(obj.get("id", 0))
            if _pending_commands.has(id):
                emit_signal("command_result", bool(obj.get("success", false)), _pending_commands[id]["label"])
                _pending_commands.erase(id)
            if obj.get("success", false) and typeof(obj.get("result", null)) == TYPE_ARRAY:
                for state in obj["result"]:
                    if typeof(state) == TYPE_DICTIONARY and state.get("entity_id", "") == entity_id:
                        _apply_state(state)
        "event":
            var ev = obj.get("event", {})
            if ev.get("event_type", "") == "state_changed":
                var change = ev.get("data", {})
                if change.get("entity_id", "") == entity_id:
                    var state = change.get("new_state", null)
                    if typeof(state) == TYPE_DICTIONARY:
                        _apply_state(state)

func _apply_state(state):
    var attr = state.get("attributes", {})
    track = {
        "state": str(state.get("state", "unknown")),
        "title": str(attr.get("media_title", "No track")),
        "artist": str(attr.get("media_artist", "")),
        "album": str(attr.get("media_album_name", "")),
        "art": str(attr.get("entity_picture", "")),
        "position": float(attr.get("media_position", 0.0)),
        "duration": float(attr.get("media_duration", 0.0)),
        "volume": float(attr.get("volume_level", 0.0))
    }
    emit_signal("track_changed", track)

func media_command(service):
    if not connected:
        emit_signal("command_result", false, "Not connected")
        return
    if not service in ["media_play_pause", "media_next_track", "media_previous_track"]:
        return
    _request({
        "type": "call_service",
        "domain": "media_player",
        "service": service,
        "service_data": {"entity_id": entity_id}
    }, service)
