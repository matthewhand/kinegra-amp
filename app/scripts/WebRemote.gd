extends Node
# A bounded, foreground-only HTTP remote. No UPnP, discovery or background service.
const PORT = 8765
const MAX_CLIENTS = 4
const MAX_REQUEST = 6144
const MAX_HEADER = 4096
const MAX_BODY = 1024
const ACTIONS = ["play", "pause", "previous", "next", "stop"]
var app = null
var music_api=null
var settings_path = "user://shieldamp_web_remote.cfg"
var server = TCP_Server.new()
var clients = []
var key = ""
var require_key=true
var trusted_ranges_text=""
var trusted_ranges=[]
var lan_policy=preload("res://scripts/LanAccessPolicy.gd").new()
var status = "Web remote is off."
var profile = "production"
var hosts = []
var urls = []
var _elapsed = 0.0
var _last_action = -1000
signal changed

static func development_build(debug, production):
    return bool(debug) and not bool(production)

static func default_enabled(development):
    return bool(development)

func configure(owner, development):
    set_process(false)
    app = owner
    if music_api==null:
        music_api=preload("res://scripts/WebMusicAPI.gd").new()
        music_api.app=app
        add_child(music_api)
    profile = "development" if development else "production"
    var saved = ConfigFile.new()
    var error = saved.load(settings_path)
    var enabled = default_enabled(development) if error == ERR_FILE_NOT_FOUND else false
    require_key=true
    trusted_ranges_text=lan_policy.starter(IP.get_local_addresses())
    if error==OK:
        require_key=saved.get_value(profile,"require_key",true)
        trusted_ranges_text=saved.get_value(profile,"trusted_ranges",trusted_ranges_text)
    var parsed=lan_policy.parse(trusted_ranges_text)
    if typeof(require_key)!=TYPE_BOOL or not parsed.ok:
        require_key=true
        status="Web remote is off: fix its trusted LAN ranges in Settings."
        emit_signal("changed")
        return
    trusted_ranges=parsed.ranges
    if error == OK:
        enabled = saved.get_value(profile, "enabled", default_enabled(development))
        if typeof(enabled) != TYPE_BOOL: enabled = false
    elif error != ERR_FILE_NOT_FOUND:
        status = "Web remote is off: saved setting could not be read."
    if enabled: _start()

func set_enabled(enabled):
    if enabled and not _start(): return false
    if not enabled: _stop()
    var saved = ConfigFile.new()
    var error = saved.load(settings_path)
    if error != OK and error != ERR_FILE_NOT_FOUND:
        _stop()
        status = "Web remote is off: saved setting could not be read."
        emit_signal("changed")
        return false
    saved.set_value(profile, "enabled", bool(enabled))
    if saved.save(settings_path) != OK:
        _stop()
        status = "Web remote is off: setting could not be saved."
        emit_signal("changed")
        return false
    emit_signal("changed")
    return true

func set_access(key_required,ranges_text):
    var parsed=lan_policy.parse(ranges_text)
    if typeof(key_required)!=TYPE_BOOL or not parsed.ok:
        status=parsed.get("error","Invalid access setting.")
        emit_signal("changed")
        return false
    var saved=ConfigFile.new()
    var result=saved.load(settings_path)
    if result!=OK and result!=ERR_FILE_NOT_FOUND:
        status="Access not saved: settings could not be read."
        emit_signal("changed")
        return false
    saved.set_value(profile,"require_key",key_required)
    saved.set_value(profile,"trusted_ranges",parsed.text)
    if saved.save(settings_path)!=OK:
        status="Access not saved: settings could not be written."
        emit_signal("changed")
        return false
    var running=server.is_listening()
    _stop()
    require_key=key_required
    trusted_ranges_text=parsed.text
    trusted_ranges=parsed.ranges
    if running:_start()
    else:status="Access saved. Web remote is off."
    emit_signal("changed")
    return true

func _start():
    if server.is_listening(): return true
    hosts = ["localhost", "127.0.0.1"]
    urls.clear()
    for address in IP.get_local_addresses():
        if _private_ipv4(address) and not address.begins_with("127."):
            hosts.append(address)
            urls.append("http://%s:%d" % [address, PORT])
    key = Crypto.new().generate_random_bytes(8).hex_encode()
    if key.length() != 16 or server.listen(PORT, "0.0.0.0") != OK:
        key = ""
        status = "Web remote is off: port %d is unavailable." % PORT
        emit_signal("changed")
        return false
    var address=PoolStringArray(urls).join(" or ") if not urls.empty() else "http://DEVICE_IP:%d" % PORT
    status="Open %s. Access key: %s" % [address,key] if require_key else "Open %s. No key required; trusted LAN ranges only." % address
    set_process(true)
    emit_signal("changed")
    return true

func _stop():
    if music_api!=null:music_api.cancel()
    server.stop()
    for client in clients: client.peer.disconnect_from_host()
    clients.clear()
    key = ""
    status = "Web remote is off."
    set_process(false)
    emit_signal("changed")

func rotate_key():
    if not server.is_listening(): return
    _stop()
    _start()

func _exit_tree():
    _stop()

func _process(delta):
    _elapsed += delta
    if _elapsed < 0.05 or not server.is_listening(): return
    _elapsed = 0.0
    for _attempt in range(MAX_CLIENTS):
        if not server.is_connection_available(): break
        var peer = server.take_connection()
        if clients.size() >= MAX_CLIENTS or not _private_ipv4(peer.get_connected_host()):
            peer.disconnect_from_host()
        else:
            clients.append({"peer":peer, "data":PoolByteArray(), "out":PoolByteArray(), "sent":0, "at":OS.get_ticks_msec()})
    for i in range(clients.size()-1, -1, -1):
        var client = clients[i]
        var peer = client.peer
        if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or OS.get_ticks_msec()-client.at > 2000:
            _close(i)
            continue
        if not client.out.empty():
            var written = peer.put_partial_data(client.out.subarray(client.sent, client.out.size()-1))
            if written[0] != OK:
                _close(i)
            else:
                client.sent += written[1]
                if client.sent == client.out.size(): _close(i)
            continue
        var available = peer.get_available_bytes()
        if available <= 0: continue
        if client.data.size()+available > MAX_REQUEST:
            _respond(client, 413, {"error":"Request too large"})
            continue
        var read = peer.get_partial_data(available)
        if read[0] != OK:
            _close(i)
            continue
        var data = client.data
        data.append_array(read[1])
        client.data = data
        _read_request(client)

func _close(index):
    clients[index].peer.disconnect_from_host()
    clients.remove(index)

func _private_ipv4(address):
    var parts = str(address).split(".")
    if parts.size() != 4: return false
    for part in parts:
        if not part.is_valid_integer() or int(part)<0 or int(part)>255 or str(int(part))!=part: return false
    return parts[0] in ["10", "127"] or (parts[0]=="192" and parts[1]=="168") or (parts[0]=="172" and int(parts[1])>=16 and int(parts[1])<=31) or (parts[0]=="169" and parts[1]=="254")

func _read_request(client):
    var text = client.data.get_string_from_utf8()
    var split = text.find("\r\n\r\n")
    if split < 0:
        if client.data.size() > MAX_HEADER: _respond(client, 431, {"error":"Headers too large"})
        return
    if split > MAX_HEADER:
        _respond(client, 431, {"error":"Headers too large"})
        return
    var lines = text.substr(0, split).split("\r\n")
    var request = lines[0].split(" ", false)
    if request.size()!=3 or request[2]!="HTTP/1.1" or not request[0] in ["GET", "POST"]:
        _respond(client, 400, {"error":"Unsupported request"})
        return
    var headers = {}
    for i in range(1, lines.size()):
        var colon = lines[i].find(":")
        if colon <= 0:
            _respond(client, 400, {"error":"Invalid headers"})
            return
        var name = lines[i].substr(0, colon).to_lower()
        if headers.has(name) or name.strip_edges()!=name:
            _respond(client, 400, {"error":"Duplicate or invalid header"})
            return
        headers[name] = lines[i].substr(colon+1).strip_edges()
    var host = str(headers.get("host", ""))
    if not host.ends_with(":%d" % PORT) or not host.trim_suffix(":%d" % PORT) in hosts:
        _respond(client, 403, {"error":"Use this device's LAN address"})
        return
    if headers.has("origin") and headers.origin!="http://"+host:
        _respond(client, 403, {"error":"Cross-origin access denied"})
        return
    var length = str(headers.get("content-length", "0"))
    if headers.has("transfer-encoding") or not length.is_valid_integer() or int(length)<0 or int(length)>MAX_BODY:
        _respond(client, 400, {"error":"Invalid body length"})
        return
    var body_offset = text.substr(0,split+4).to_utf8().size()
    if client.data.size() < body_offset+int(length): return
    if client.data.size() != body_offset+int(length):
        _respond(client, 400, {"error":"One request per connection"})
        return
    if not lan_policy.allows(client.peer.get_connected_host(),trusted_ranges):
        _respond(client,403,{"error":"Your address is outside the trusted LAN ranges configured on the TV."})
        return
    var path = request[1]
    if request[0]=="GET" and path=="/api/access":
        _respond(client,200,{"require_key":require_key})
        return
    if request[0]=="GET" and path=="/" and int(length)==0:
        _respond(client, 200, preload("res://scripts/WebRemotePage.gd").HTML, "text/html; charset=utf-8")
        return
    if require_key and (str(headers.get("authorization", ""))!="Bearer "+key or key.empty()):
        _respond(client, 401, {"error":"Enter the access key shown in Kinegra Amp Settings"})
        return
    if request[0]=="GET" and path=="/api/offline-status" and int(length)==0:
        _respond(client,200,{"state":app.offline_save.state,"active":app.offline_save.active,"message":app.offline_save.message,"saved":app.offline_save.copied,"has_saved":not app.offline_save.saved_indices.empty(),"configured":app.offline_save.configured(),"free_bytes":app.offline_save._free_bytes(app.offline_music.user_library.directory)})
        return
    if request[0]=="GET" and path=="/api/diagnostics" and int(length)==0:
        _respond(client,200,app.web_remote_diagnostics())
        return
    if request[0]=="GET" and path=="/api/status" and int(length)==0:
        _respond(client, 200, app.web_remote_snapshot())
        return
    if request[0]=="GET" and path.begins_with("/api/operations/"):
        var result=music_api.route("GET",path,{})
        _respond(client,result.code,result.body)
        return
    if request[0]!="POST":
        _respond(client,404,{"error":"Unknown route"})
        return
    if headers.get("content-type", "").split(";")[0].strip_edges()!="application/json":
        _respond(client, 415, {"error":"Use application/json"})
        return
    var body = JSON.parse(text.substr(split+4))
    if body.error!=OK or typeof(body.result)!=TYPE_DICTIONARY:
        _respond(client,400,{"error":"Invalid JSON object"})
        return
    if path=="/api/offline-source":
        var saved=app.offline_save.configure(body.result.get("origin"),body.result.get("key"))
        _respond(client,200 if saved else 400,{"ok":saved})
        return
    if path=="/api/offline-save":
        var action=body.result.get("action","")
        if not action in ["save","cancel","play"]:
            _respond(client,400,{"error":"Unknown offline action"})
            return
        if action=="cancel":app.offline_save.cancel()
        elif action=="save":app.offline_save.begin()
        elif action=="play":app.offline_save.play_saved()
        _respond(client,200,{"state":app.offline_save.state,"active":app.offline_save.active,"message":app.offline_save.message,"saved":app.offline_save.copied})
        return
    if path!="/api/control":
        var result=music_api.route("POST",path,body.result)
        _respond(client,result.code,result.body)
        return
    if body.result.size()!=1 or not body.result.get("action", "") in ACTIONS:
        _respond(client, 400, {"error":"Unknown action"})
        return
    if OS.get_ticks_msec()-_last_action < 150:
        _respond(client, 429, {"error":"Please wait before the next command"})
        return
    _last_action = OS.get_ticks_msec()
    var accepted = app.web_remote_control(body.result.action)
    _respond(client, 202 if accepted else 409, {"accepted":accepted, "action":body.result.action})

func _respond(client, code, value, content_type="application/json; charset=utf-8"):
    var bytes = (value if typeof(value)==TYPE_STRING else to_json(value)).to_utf8()
    var headers = "HTTP/1.1 %d Response\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n" % [code, content_type, bytes.size()]
    var output = headers.to_utf8()
    output.append_array(bytes)
    client.out = output
