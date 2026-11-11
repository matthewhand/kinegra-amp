extends Node
# MA metadata adapter; only the explicit Play action changes a selected player queue.
signal state_changed(state, detail)
signal page_ready(page)
signal selection_changed(item)
signal players_ready(players)
signal stream_candidate(candidate)
signal local_queue_snapshot(snapshot)
signal local_queue_items(items)
signal offline_queue_page(items)
signal offline_track(item)
signal queued_playlist_context(name,track_ids)

const ArtworkPolicy=preload("res://scripts/MAArtworkPolicy.gd")
const READ_COMMANDS = ["players/all", "music/tracks/library_items", "music/albums/library_items", "music/albums/album_tracks", "music/playlists/library_items", "music/playlists/playlist_tracks"]
const MAX_REPLY = 2097152
const PAGE_SIZE = 25
const MAX_PLAYLIST_ITEMS = 2000
const MAX_BROWSE_OFFSET = 10000
const SELECTION_AGE_MS = 60000
var metadata_timeout_seconds=8.0
var last_result_code=-1
var last_http_code=-1
var endpoint = ""
var trusted_private_http = false
var token = ""
var state = "not_configured"
var epoch = 0
var sequence = 0
var selected = {}
var selected_at = 0
var current_page = {}
var playlist_snapshot=[]
var playlist_snapshot_valid=false
var playlist_context={}
var playlist_returned_count=0
var playlist_query=""
var stream_origins = []
var policy = preload("res://scripts/ConnectionPolicy.gd").new()
var request_node = null
var request_context = {}
var player_media = {}
var available_players = {}
var player_routes = []
var player_routes_complete = false
var players_at = 0

func _state(value, detail):
    state = value
    emit_signal("state_changed", value, detail)

func configure(api_origin, owner_token, approved_stream_origins=[], trust_private_http=false):
    close()
    var address = str(api_origin).strip_edges().trim_suffix("/")
    if policy.origin(address, ["https", "http"], trust_private_http).empty():
        _state("invalid_endpoint", "Use HTTPS, or explicitly trust HTTP on a private IP address")
        return false
    var credential = str(owner_token).strip_edges()
    if credential.length() < 10 or credential.length() > 8192:
        _state("auth_required", "Enter an owner-provisioned MA token; it stays in memory")
        return false
    for i in range(credential.length()):
        if credential.ord_at(i) < 33 or credential.ord_at(i) > 126:
            _state("auth_required", "Invalid token characters")
            return false
    if approved_stream_origins.size() > 4:
        _state("invalid_endpoint", "At most four stream origins are supported")
        return false
    for origin in approved_stream_origins:
        if policy.origin(str(origin), ["https"]).empty():
            _state("invalid_endpoint", "Stream origins must use HTTPS and contain no credentials or path")
            return false
    endpoint = address
    trusted_private_http = trust_private_http
    token = credential
    stream_origins = approved_stream_origins.duplicate()
    _state("ready", "Read-only catalog ready; selecting music does not start playback")
    return true

func cancel():
    epoch += 1
    if request_node != null:
        request_node.cancel_request()
        request_node.queue_free()
        request_node = null
    request_context.clear()
    selected.clear()
    current_page.clear()
    playlist_snapshot.clear()
    playlist_snapshot_valid=false
    playlist_context.clear()
    playlist_returned_count=0
    playlist_query=""
    player_media.clear()
    available_players.clear()
    player_routes.clear()
    player_routes_complete=false
    _state("cancelled", "Request cancelled; previous selections expired")

func close():
    cancel()
    token = ""
    endpoint = ""
    trusted_private_http = false
    stream_origins.clear()
    _state("not_configured", "MA disconnected; your private offline music remains available")

func _notification(what):
    if what == MainLoop.NOTIFICATION_APP_PAUSED:
        close()

func _exit_tree():
    if request_node != null:
        request_node.cancel_request()
    token = ""

func _id(value):
    if typeof(value) != TYPE_STRING or value.length() == 0 or value.length() > 200:
        return false
    for i in range(value.length()):
        if value.ord_at(i) < 32 or value.ord_at(i) == 127:
            return false
    return true

func _safe(value, cap=160):
    var text = str(value).substr(0, cap)
    for i in range(text.length()):
        if text.ord_at(i) < 32 or text.ord_at(i) == 127:
            text[i] = " "
    if "://" in text:
        return "[URL REDACTED]"
    return text

func _preempt_player_metadata():
    if request_node==null or request_context.get("kind")!="players":return
    # Browsing can supersede a read-only player refresh, never a queue write.
    # Expire its callback and route proof before starting the new read.
    epoch+=1
    var previous=request_node
    request_node=null
    previous.cancel_request()
    previous.queue_free()
    request_context.clear()
    player_media.clear()
    available_players.clear()
    player_routes.clear()
    player_routes_complete=false
    players_at=0

func _start(command, args, context):
    var local_queue = context.get("kind") == "local_queue_action" and command in ["player_queues/play", "player_queues/resume", "player_queues/pause", "player_queues/stop", "player_queues/next", "player_queues/previous", "player_queues/seek", "player_queues/delete_item", "player_queues/clear"]
    var queue_read = (context.get("kind")=="local_queue_read" and command=="player_queues/get") or (context.get("kind")=="local_queue_items" and command=="player_queues/items")
    if not command in READ_COMMANDS and not (command == "player_queues/play_media" and context.get("kind") in ["play","enqueue"]) and not local_queue and not queue_read and not (context.get("kind")=="offline_page" and command=="player_queues/items") and not (context.get("kind")=="offline_track" and command=="music/tracks/get"):
        _state("invalid_request", "Only catalog/player metadata reads are supported")
        return false
    if context.get("kind") in ["tracks","albums","playlists","playlist_items"]:_preempt_player_metadata()
    if request_node != null:
        _state("busy", "One catalog request at a time; Cancel stops the current request")
        return false
    if endpoint.empty() or token.empty():
        _state("auth_required", "Configure MA with an owner-provisioned token first")
        return false
    sequence += 1
    request_context = context.duplicate(true)
    if context.get("kind") in ["tracks","albums","playlists","playlist_items"]:
        selected.clear()
        current_page.clear()
        if context.get("kind")=="playlist_items":
            playlist_snapshot.clear()
            playlist_snapshot_valid=false
            playlist_returned_count=0
    request_context["started_ms"]=OS.get_ticks_msec()
    request_context["message_id"] = "shield-catalog-" + str(get_instance_id()) + "-" + str(OS.get_ticks_usec()) + "-" + str(sequence)
    request_node = HTTPRequest.new()
    request_node.body_size_limit = MAX_REPLY
    request_node.timeout = clamp(metadata_timeout_seconds,8.0,15.0) if context.get("kind") in ["tracks","albums","playlists","playlist_items"] else 8.0
    request_node.max_redirects = 0
    request_node.download_chunk_size = 16384
    add_child(request_node)
    request_node.connect("request_completed", self, "_complete", [epoch])
    var body = to_json({"message_id": request_context["message_id"], "command": command, "args": args})
    var result = request_node.request(endpoint + "/api", ["Content-Type: application/json", "Authorization: Bearer " + token], true, HTTPClient.METHOD_POST, body)
    if result != OK:
        _dispose_request()
        _state("disconnected", "MA request could not start; retry or Cancel")
        return false
    _state("loading", "Adding tracks to the queue" if context.get("kind")=="enqueue" else ("Sending TV queue request" if local_queue else "Reading MA metadata; no playback or queue changes"))
    return true

func browse(kind="tracks", search="", offset=0):
    if not kind in ["tracks", "albums", "playlists"] or typeof(offset) != TYPE_INT or offset < 0 or offset > MAX_BROWSE_OFFSET or str(search).length() > 100:
        _state("invalid_request", "Unsupported catalog request")
        return false
    _preempt_player_metadata()
    if request_node!=null:
        _state("busy","Wait for the current request, or cancel it")
        return false
    playlist_snapshot.clear()
    playlist_snapshot_valid=false
    playlist_context.clear()
    playlist_query=""
    return _start("music/" + kind + "/library_items", {"limit": PAGE_SIZE, "offset": offset, "search": _safe(search, 100), "order_by": "sort_name", "summary": true}, {"kind": kind, "offset": offset,"search":str(search)})

func discover_players():
    return _start("players/all", {"return_unavailable": true, "return_disabled": true}, {"kind": "players"})

func resolve_local_player(client_id):
    # Never infer from a display name. Require a recent, complete snapshot and
    # one ungrouped wrapper with exactly one available, direct Sendspin output.
    if not _id(client_id) or token.empty() or request_node!=null or not player_routes_complete or OS.get_ticks_msec()-players_at>10000:
        return ""
    var matches=[]
    var claims=0
    for player in player_routes:
        if player.get("provider")=="universal_player" and player.get("available")==true and player.get("enabled")==true and typeof(player.get("output_protocols"))==TYPE_ARRAY:
            for advertised in player["output_protocols"]:
                if typeof(advertised)==TYPE_DICTIONARY and advertised.get("output_protocol_id")==client_id and advertised.get("available")==true: claims+=1
        if not (player.get("provider")=="universal_player" and player.get("type")=="player" and player.get("available")==true and player.get("enabled")==true): continue
        if not player.has("active_group") or not player.has("synced_to") or not player.has("group_members") or not player.has("static_group_members") or not player.has("active_output_protocol"): continue
        if player["active_group"]!=null or player["synced_to"]!=null: continue
        if typeof(player["group_members"])!=TYPE_ARRAY or not player["group_members"].empty() or typeof(player["static_group_members"])!=TYPE_ARRAY or not player["static_group_members"].empty(): continue
        if player["active_output_protocol"]!=null and player["active_output_protocol"]!=client_id: continue
        var outputs=player.get("output_protocols")
        if typeof(outputs)!=TYPE_ARRAY or outputs.size()!=1 or typeof(outputs[0])!=TYPE_DICTIONARY: continue
        var output=outputs[0]
        if output.get("output_protocol_id")!=client_id or output.get("protocol_domain")!="sendspin" or output.get("available")!=true or not output.has("derived_from") or output["derived_from"]!=null: continue
        if _id(player.get("player_id")) and available_players.has(player["player_id"]): matches.append(player["player_id"])
    return matches[0] if matches.size()==1 and claims==1 else ""

func local_queue_request(client_id, action, argument=null):
    if not action in ["play", "resume", "pause", "stop", "next", "previous", "read", "items", "seek", "remove", "clear"]:
        _state("invalid_request", "Unsupported TV queue action")
        return false
    var queue_id=resolve_local_player(client_id)
    if queue_id.empty():
        _state("unsafe_route", "TV output route could not be verified")
        return false
    var kind="local_queue_read" if action=="read" else ("local_queue_items" if action=="items" else "local_queue_action")
    var args={"queue_id":queue_id}
    var offset=0
    if action=="items":
        offset=0 if argument==null else argument
        if typeof(offset)!=TYPE_INT or offset<0 or offset>100000:
            _state("invalid_request","Invalid queue page")
            return false
        args["limit"]=10
        args["offset"]=offset
    elif action=="seek":
        if typeof(argument)!=TYPE_INT or argument<0 or argument>86400:
            _state("invalid_request","Invalid seek position")
            return false
        args["position"]=argument
    elif action=="remove":
        if not preload("res://scripts/MAQueuePolicy.gd").new().item_id(argument):
            _state("invalid_request","Select a fresh upcoming queue item")
            return false
        args["item_id_or_index"]=argument # Always an opaque ID, never a position.
    elif action=="clear":
        args["skip_stop"]=false
    var command="get" if action=="read" else ("delete_item" if action=="remove" else action)
    return _start("player_queues/"+command, args, {"kind":kind,"queue_id":queue_id,"offset":offset})

func enqueue_local_media(client_id, media):
    var target=resolve_local_player(client_id)
    if target.empty() or typeof(media)!=TYPE_ARRAY or media.empty() or media.size()>MAX_PLAYLIST_ITEMS:
        _state("unsafe_route","Connect Kinegra Amp playback and choose library tracks first")
        return false
    var uris=[]
    var digits=RegEx.new()
    digits.compile("^[0-9]+$")
    for item in media:
        if typeof(item)!=TYPE_DICTIONARY or item.get("provider")!="library" or not item.get("media_type") in ["track","album","playlist"] or (item.get("media_type")=="track" and item.get("available",false)!=true) or digits.search(str(item.get("item_id","")))==null:
            _state("invalid_request","Choose available library tracks or a playlist")
            return false
        if item.get("media_type") in ["album","playlist"] and media.size()!=1:return false
        uris.append("library://"+str(item["media_type"])+"/"+str(item["item_id"]))
    var context={"kind":"enqueue","count":uris.size(),"playlist_add":media.size()==1 and media[0].get("media_type")=="playlist"}
    if playlist_snapshot_valid and current_page.get("kind")=="playlist_items" and not playlist_context.empty():
        var known={}
        for row in playlist_snapshot:known[str(row.get("item_id",""))]=true
        var ids=[]
        for item in media:
            var id=str(item["item_id"])
            if not known.has(id):
                ids.clear()
                break
            ids.append(id)
        if ids.size()==media.size():
            context["playlist_name"]=_safe(playlist_context.get("name",""),100)
            context["playlist_track_ids"]=ids
    return _start("player_queues/play_media",{"queue_id":target,"media":uris,"option":"add"},context)

func play_local_selection(client_id, item):
    # Explicit PLAY inserts/plays selected media while preserving the remaining
    # queue in pinned MA2.10.7. Never use default/replace or another output.
    var target=resolve_local_player(client_id)
    if target.empty() or token.empty() or request_node!=null or typeof(item)!=TYPE_DICTIONARY:return false
    var same=false
    for row in current_page.get("items",[]):
        if row.get("provider")==item.get("provider") and row.get("media_type")==item.get("media_type") and str(row.get("item_id"))==str(item.get("item_id")):same=true
    var digits=RegEx.new();digits.compile("^[0-9]+$")
    if not same or item.get("provider")!="library" or not item.get("media_type") in ["track","album","playlist"] or digits.search(str(item.get("item_id","")))==null or (item.get("media_type")=="track" and item.get("available",false)!=true):
        _state("invalid_request","Select a current library track or playlist")
        return false
    return _start("player_queues/play_media",{"queue_id":target,"media":"library://"+str(item.media_type)+"/"+str(item.item_id),"option":"play"},{"kind":"play","local_client":client_id})

func play_on_player(player_id):
    # A deliberate Play acts on the highlighted item and the discovered player.
    # Let the server reject an unavailable player rather than silently expiring
    # a user's selection while they navigate a TV popup.
    var item = selected.duplicate(true)
    if token.empty() or request_node != null or item.empty() or not available_players.has(player_id):
        _state("selection_expired", "Select a track or playlist and refresh players first")
        return false
    var media_type = str(item.get("media_type", ""))
    var item_id = str(item.get("item_id", ""))
    var matcher = RegEx.new()
    matcher.compile("^[0-9]+$")
    if item.get("provider") != "library" or not media_type in ["track", "album", "playlist"] or matcher.search(item_id) == null:
        _state("invalid_request", "Only library tracks, albums and playlists can be played")
        return false
    var uri = "library://" + media_type + "/" + item_id
    return _start("player_queues/play_media", {"queue_id": player_id, "media": uri}, {"kind": "play"})

func select_index(index):
    var items = current_page.get("items", [])
    if typeof(index) != TYPE_INT or index < 0 or index >= items.size():
        return false
    selected = items[index].duplicate(true)
    selected_at = OS.get_ticks_msec()
    emit_signal("selection_changed", selected.duplicate(true))
    return true

func selection():
    if token.empty() or selected.empty() or OS.get_ticks_msec() - selected_at > SELECTION_AGE_MS:
        selected.clear()
        return {}
    if request_node != null:
        return {} # Metadata refresh temporarily blocks playback, without deleting the selection.
    return selected.duplicate(true)

func restore_playlist_context(item_id,media_type="playlist"):
    # A saved same-server library ID authorizes only a bounded read, never playback.
    if not media_type in ["playlist","album"]:return false
    if typeof(item_id)!=TYPE_STRING or item_id.empty() or item_id.length()>18 or not item_id.is_valid_integer() or token.empty():return false
    if request_node!=null and request_context.get("kind")!="players":return false
    _preempt_player_metadata()
    playlist_context={"item_id":item_id,"provider":"library","name":"","media_type":media_type}
    playlist_query=""
    return refresh_playlist()

func album_items():
    _preempt_player_metadata()
    var item=selection()
    if item.empty() or item.get("media_type")!="album":return false
    playlist_context={"item_id":item.item_id,"provider":item.provider,"name":item.get("name",""),"media_type":"album"}
    playlist_query=""
    return refresh_playlist(false)

func playlist_items():
    _preempt_player_metadata()
    var item=selection()
    if item.empty() or item.get("media_type")!="playlist":
        _state("selection_expired","Select a current playlist first")
        return false
    playlist_context={"item_id":item["item_id"],"provider":item["provider"],"name":item.get("name","")}
    playlist_query=""
    return refresh_playlist(false)

func refresh_playlist(force_refresh=true):
    if playlist_context.empty() or token.empty():
        _state("selection_expired","Open a playlist before refreshing its tracks")
        return false
    # MA 2.10.7 has no playlist limit/offset parameters. Fetch one bounded
    # response, then page its sanitized snapshot locally. Never mutate it.
    if playlist_context.get("media_type")=="album":
        return _start("music/albums/album_tracks",{"item_id":playlist_context.item_id,"provider_instance_id_or_domain":"library","in_library_only":true},{"kind":"playlist_items","offset":0,"search":playlist_query})
    return _start("music/playlists/playlist_tracks",{"item_id":playlist_context["item_id"],"provider_instance_id_or_domain":playlist_context["provider"],"force_refresh":bool(force_refresh),"allow_dynamic_tracks":false},{"kind":"playlist_items","offset":0,"search":playlist_query})

func playlist_page(page_offset=0,search=null):
    if token.empty() or playlist_context.empty() or not playlist_snapshot_valid or (request_node!=null and request_context.get("kind")!="players") or typeof(page_offset)!=TYPE_INT or page_offset<0 or page_offset>MAX_BROWSE_OFFSET:
        _state("invalid_request","Playlist page is unavailable; refresh the playlist")
        return false
    if search!=null:
        if typeof(search)!=TYPE_STRING or search.length()>100:return false
        playlist_query=search
    _publish_playlist_page(page_offset)
    return true

func _publish_playlist_page(page_offset):
    var matches=[]
    var query=playlist_query.to_lower()
    for item in playlist_snapshot:
        if query.empty() or (str(item.get("name",""))+" "+str(item.get("artist",""))+" "+str(item.get("album",""))).to_lower().find(query)>=0:matches.append(item)
    # A refresh can shrink or empty the playlist. Its first page replaces the
    # old snapshot; an invalid old offset must never manufacture a count.
    if page_offset>=matches.size() and page_offset>0:page_offset=max(0,int((matches.size()-1)/PAGE_SIZE)*PAGE_SIZE)
    var rows=[]
    for index in range(page_offset,min(page_offset+PAGE_SIZE,matches.size())):rows.append(matches[index].duplicate(true))
    current_page={"contract":"shield.catalog.v1","kind":"playlist_items","epoch":epoch,"sequence":sequence,"offset":page_offset,"search":playlist_query,"items":rows,"may_have_more":page_offset+rows.size()<matches.size(),"truncated":playlist_returned_count>playlist_snapshot.size(),"server_pagination":false,"page_size":PAGE_SIZE,"matched_count":matches.size(),"returned_count":playlist_returned_count,"preview_count":playlist_snapshot.size(),"preview_limit":MAX_PLAYLIST_ITEMS,"total_count":-1,"playlist":playlist_context.duplicate(true)}
    selected.clear()
    _state("ready","Playlist response loaded; pages use this read-only snapshot")
    emit_signal("page_ready",current_page.duplicate(true))

func _dispose_request():
    if request_node != null:
        request_node.queue_free()
        request_node = null

func _row(value, kind):
    if typeof(value) != TYPE_DICTIONARY or not _id(value.get("item_id")) or not _id(value.get("provider")):
        return {}
    var names=[]
    var artists=value.get("artists", [])
    if typeof(artists)==TYPE_ARRAY:
        for artist in artists:
            if typeof(artist)==TYPE_DICTIONARY and artist.has("name"):
                names.append(_safe(artist["name"], 80))
    var album=value.get("album", {})
    var album_name=_safe(album.get("name", "")) if typeof(album)==TYPE_DICTIONARY else ""
    return {"item_id": value["item_id"], "provider": value["provider"], "name": _safe(value.get("name", "Untitled")), "artist": ", ".join(names), "album": album_name, "media_type": _safe(value.get("media_type", "playlist" if kind == "playlists" else ("album" if kind=="albums" else "track")), 30), "available": value.get("is_playable", true) == true,"artwork_descriptor":ArtworkPolicy.sanitize(value)}

func _complete(result, response_code, _headers, body, request_epoch):
    if request_epoch != epoch or request_node == null:
        return
    last_result_code=result
    last_http_code=response_code
    _dispose_request()
    if response_code in [401, 403]:
        token = ""
        selected.clear()
        player_media.clear()
        _state("auth_expired" if response_code == 401 else "permission_denied", "MA authentication expired or lacks library.read/players.read; reconnect with an owner token")
        return
    if request_context.get("kind")=="playlist_items" and (result==HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED or body.size()>MAX_REPLY):
        _state("malformed_reply","Playlist exceeds the 2 MiB response limit; no tracks loaded. Browse this collection in Music Assistant.")
        return
    var kind = request_context.get("kind", "")
    if result == HTTPRequest.RESULT_SUCCESS and kind in ["play","local_queue_action","enqueue"] and response_code >= 400 and response_code <= 599:
        # The server can put file paths and credentials in an error body.
        # Use the actual HTTP status with a bounded, client-owned description.
        var message = "Music Assistant rejected the request (HTTP %d)." % response_code
        if response_code >= 500:
            message = "Music Assistant server error (HTTP %d)." % response_code
        _state("command_failed",message)
        return
    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.size() > MAX_REPLY:
        _state("disconnected", ("Queue result unknown. Check the queue before adding again." if request_context.get("kind")=="enqueue" else "Play result unknown. Check Queue before retrying.") if request_context.get("kind") in ["enqueue","play"] else "MA request failed, timed out or exceeded its reply limit; retry or Cancel")
        return
    var parsed = JSON.parse(body.get_string_from_utf8())
    if parsed.error != OK:
        _state("malformed_reply", ("Queue result unknown. Check the queue before adding again." if request_context.get("kind")=="enqueue" else "Play result unknown. Check Queue before retrying.") if request_context.get("kind") in ["enqueue","play"] else "MA returned invalid metadata")
        return
    var value = parsed.result
    if typeof(value) == TYPE_DICTIONARY:
        if value.has("message_id"):
            if str(value["message_id"]) != request_context.get("message_id"):
                _state("stale_reply", ("Queue result unknown. Check the queue before adding again." if request_context.get("kind")=="enqueue" else "Play result unknown. Check Queue before retrying.") if request_context.get("kind") in ["enqueue","play"] else "Rejected an obsolete MA reply")
                return
        if value.has("error") or value.has("error_code") or value.get("success", true) == false:
            _state("command_failed", "Music Assistant declined the request")
            return
        if value.has("message_id"):
            value = value.get("result")
    if kind == "offline_page":
        if typeof(value)!=TYPE_ARRAY or value.size()>request_context.get("limit",0):
            _state("malformed_reply","Unexpected offline queue page")
            return
        var rows=[]
        for entry in value:
            if typeof(entry)!=TYPE_DICTIONARY or entry.get("queue_id")!=request_context.get("queue_id") or typeof(entry.get("media_item"))!=TYPE_DICTIONARY:
                _state("malformed_reply","Offline save supports queued tracks only")
                return
            var media=entry.media_item
            if media.get("media_type")!="track" or not _id(media.get("item_id")) or not _id(media.get("provider")):
                _state("malformed_reply","Offline save supports queued tracks only")
                return
            rows.append({"queue_item_id":str(entry.get("queue_item_id","")),"name":_safe(entry.get("name","Untitled"),120),"media":{"item_id":media.item_id,"provider":media.provider}})
        _state("offline_ready","Read-only queue snapshot")
        emit_signal("offline_queue_page",rows)
        return
    if kind == "offline_track":
        var local_file={}
        if typeof(value)==TYPE_DICTIONARY and value.get("media_type")=="track":
            var mappings=value.get("provider_mappings",[])
            if typeof(mappings)==TYPE_ARRAY and mappings.size()<=64:
                for mapping in mappings:
                    if typeof(mapping)==TYPE_DICTIONARY and mapping.get("provider_domain")=="filesystem_local" and mapping.get("available",true)==true and _offline_path(mapping.get("item_id")):
                        local_file={"path":mapping.item_id}
                        break
        _state("offline_ready","Read-only local-file metadata")
        emit_signal("offline_track",local_file)
        return
    if kind == "local_queue_action":
        # The HTTP API returns raw JSON null on success; unlike WebSocket it
        # need not envelope a message_id. Request node and epoch bind replies.
        if value!=null:
            _state("malformed_reply", "Unexpected queue command response")
            return
        _state("queue_accepted", "Queue request accepted")
        return
    if kind == "local_queue_read":
        if typeof(value)!=TYPE_DICTIONARY or value.get("queue_id")!=request_context.get("queue_id"):
            _state("malformed_reply", "Music Assistant returned an unexpected TV queue")
            return
        var current=value.get("current_item")
        var next=value.get("next_item")
        var clean={"state":_safe(value.get("state","unknown"),20), "current":_safe(current.get("name",""),100) if typeof(current)==TYPE_DICTIONARY else "", "next":_safe(next.get("name",""),100) if typeof(next)==TYPE_DICTIONARY else "", "artist":"", "album":""}
        var identity_policy=preload("res://scripts/MAQueuePolicy.gd").new()
        var current_id=current.get("queue_item_id") if typeof(current)==TYPE_DICTIONARY else null
        var next_id=next.get("queue_item_id") if typeof(next)==TYPE_DICTIONARY else null
        # IDs are never rendered. Preserve exact identity; truncation could
        # make current-item protection compare a different opaque string.
        clean["current_id"]=current_id if identity_policy.item_id(current_id) else ""
        var count=value.get("items")
        if typeof(count) in [TYPE_INT,TYPE_REAL] and not is_nan(float(count)) and not is_inf(float(count)) and count>=0 and count<=100000 and floor(float(count))==float(count):clean["item_count"]=int(count)
        clean["next_id"]=next_id if identity_policy.item_id(next_id) else ""
        clean["artwork_descriptor"]=ArtworkPolicy.sanitize(current)
        var media=current.get("media_item") if typeof(current)==TYPE_DICTIONARY else null
        clean["library_track_id"]=preload("res://scripts/PlaylistContext.gd").media_id(media)
        if typeof(media)==TYPE_DICTIONARY:
            var names=[]
            var artists=media.get("artists",[])
            if typeof(artists)==TYPE_ARRAY:
                for artist in artists:
                    if typeof(artist)==TYPE_DICTIONARY and artist.has("name") and names.size()<5: names.append(_safe(artist["name"],80))
            clean["artist"]=", ".join(names)
            var album=media.get("album")
            if typeof(album)==TYPE_DICTIONARY: clean["album"]=_safe(album.get("name",""),100)
        var received_ms=OS.get_ticks_msec()
        var started_ms=request_context.get("started_ms",-1)
        var response_clock=identity_policy.http_clock(_headers,received_ms,received_ms-started_ms if typeof(started_ms)==TYPE_INT and started_ms>=0 else -1)
        for clock_key in response_clock:clean[clock_key]=response_clock[clock_key]
        clean["active"]=value.get("active")==true
        clean["current_index"]=value.get("current_index")
        clean["index_in_buffer"]=value.get("index_in_buffer")
        var duration=current.get("duration") if typeof(current)==TYPE_DICTIONARY else null
        if typeof(duration) in [TYPE_INT,TYPE_REAL] and not is_nan(float(duration)) and not is_inf(float(duration)) and duration>0 and duration<=86400:clean["duration"]=float(duration)
        var updated=value.get("elapsed_time_last_updated")
        if typeof(updated) in [TYPE_INT,TYPE_REAL] and not is_nan(float(updated)) and not is_inf(float(updated)) and updated>0 and updated<=20000000000:clean["elapsed_updated"]=float(updated)
        var seconds=value.get("elapsed_time")
        if typeof(seconds) in [TYPE_INT, TYPE_REAL] and not is_nan(float(seconds)) and not is_inf(float(seconds)) and seconds>=0 and seconds<=86400: clean["elapsed"]=float(seconds)
        _state("queue_ready", "TV queue metadata read")
        emit_signal("local_queue_snapshot",clean)
        return
    if kind == "local_queue_items":
        if typeof(value)!=TYPE_ARRAY or value.size()>10:
            _state("malformed_reply", "Unexpected queue preview")
            return
        var items=[]
        var seen={}
        var offset=int(request_context.get("offset",0))
        var queue_policy=preload("res://scripts/MAQueuePolicy.gd").new()
        for entry in value:
            if typeof(entry)!=TYPE_DICTIONARY or entry.get("queue_id")!=request_context.get("queue_id") or typeof(entry.get("name"))!=TYPE_STRING or not queue_policy.item_id(entry.get("queue_item_id")) or seen.has(entry["queue_item_id"]):
                _state("malformed_reply", "Unexpected queue item")
                return
            seen[entry["queue_item_id"]]=true
            items.append({"item_id":entry["queue_item_id"],"name":_safe(entry["name"],100),"index":offset+items.size()})
        _state("queue_items_ready", "Queue preview read")
        emit_signal("local_queue_items",items)
        return
    if kind == "enqueue":
        if value!=null:
            _state("malformed_reply","Unexpected queue response; check the queue before retrying")
            return
        if request_context.has("playlist_name") and request_context.has("playlist_track_ids"):
            emit_signal("queued_playlist_context",request_context["playlist_name"],request_context["playlist_track_ids"].duplicate())
        _state("queue_added","Playlist added to your queue. View Queue to check its expanded items." if request_context.get("playlist_add",false) else "Added %d track(s) to your queue. View Queue to check." % int(request_context.get("count",0)))
        return
    if kind == "play":
        if value!=null:
            _state("malformed_reply","Play result unknown. Check Queue before retrying.")
            return
        _state("play_requested", "Play request accepted by Music Assistant; playback state is pending")
        return
    if typeof(value) != TYPE_ARRAY:
        _state("malformed_reply", "MA returned an unexpected catalog shape")
        return
    if kind == "players":
        player_media.clear()
        available_players.clear()
        player_routes.clear()
        player_routes_complete=value.size()<=100
        var players = []
        var seen_ids={}
        for i in range(min(value.size(), 100)):
            var player = value[i]
            # A filtered/malformed discovery reply cannot establish that the
            # matching output has exactly one owner in the complete snapshot.
            if typeof(player)!=TYPE_DICTIONARY or not _id(player.get("player_id")):
                player_routes_complete=false
                continue
            if seen_ids.has(player["player_id"]): player_routes_complete=false
            seen_ids[player["player_id"]]=true
            if typeof(player) == TYPE_DICTIONARY and _id(player.get("player_id")):
                if typeof(player.get("current_media")) == TYPE_DICTIONARY:
                    player_media[player["player_id"]] = player["current_media"].duplicate(true)
                if player.get("available", false) != true or player.get("enabled", true) != true:
                    continue
                available_players[player["player_id"]] = true
                # Retain only fields needed for routing; never retain credentials.
                var route={}
                for key in ["player_id","provider","type","available","enabled","active_group","synced_to","group_members","static_group_members","active_output_protocol","output_protocols"]:
                    if player.has(key): route[key]=player[key]
                player_routes.append(route)
                players.append({"player_id": player["player_id"], "name": _safe(player.get("display_name", player.get("name", "Unnamed"))), "state": _safe(player.get("playback_state", "unknown"), 30)})
        players_at = OS.get_ticks_msec()
        _state("ready", "Player metadata read; no player was controlled")
        emit_signal("players_ready", players)
        return
    var cap = MAX_PLAYLIST_ITEMS if kind == "playlist_items" else PAGE_SIZE
    if kind != "playlist_items" and value.size() > cap:
        _state("malformed_reply", "MA ignored the catalog page bound")
        return
    var rows = []
    for i in range(min(value.size(), cap)):
        var row = _row(value[i], kind)
        if row.empty():
            _state("malformed_reply", "MA returned an incomplete catalog item")
            return
        rows.append(row)
    if kind=="playlist_items":
        playlist_snapshot=rows
        playlist_snapshot_valid=true
        playlist_returned_count=value.size()
        _publish_playlist_page(0)
        return
    var page_offset=int(request_context.get("offset",0))
    current_page = {"contract": "shield.catalog.v1", "kind": kind, "epoch": epoch, "sequence": sequence, "offset":page_offset,"search":request_context.get("search",""), "items": rows, "may_have_more": rows.size()==PAGE_SIZE and page_offset<MAX_BROWSE_OFFSET, "truncated": false, "server_pagination":true,"page_size":PAGE_SIZE,"total_count":page_offset+rows.size() if rows.size()<PAGE_SIZE and (page_offset==0 or not rows.empty()) else -1,"offset_limit":MAX_BROWSE_OFFSET,"at_offset_limit":page_offset>=MAX_BROWSE_OFFSET}
    selected.clear()
    _state("ready", "Catalog loaded; select an item to inspect, not to start playback")
    emit_signal("page_ready", current_page.duplicate(true))

func player_stream_candidate(player_id):
    if token.empty() or not player_media.has(player_id) or OS.get_ticks_msec() - players_at > SELECTION_AGE_MS:
        _state("selection_expired", "Refresh and explicitly select a real player first")
        return {}
    var uri = str(player_media[player_id].get("uri", ""))
    if not uri.begins_with("https://"):
        return {"status": "unresolved_library_identifier", "playable": false}
    if uri.length() > 2048 or "?" in uri or "#" in uri or "@" in uri or "%" in uri or "\\" in uri or "/../" in uri:
        return {"status": "unsafe_stream_candidate", "playable": false}
    for i in range(uri.length()):
        if uri.ord_at(i) < 33 or uri.ord_at(i) > 126:
            return {"status": "unsafe_stream_candidate", "playable": false}
    for origin in stream_origins:
        if uri.begins_with(str(origin).trim_suffix("/") + "/") and not uri.begins_with(str(origin).trim_suffix("/") + "//"):
            var candidate = {"contract": "shield.stream-candidate.v1", "uri": uri, "epoch": epoch, "status": "existing_player_uri_unverified", "playable": false, "requires_format_probe": true}
            emit_signal("stream_candidate", candidate.duplicate(true))
            return candidate
    return {"status": "stream_origin_not_configured", "playable": false}


# Separate bounded export reads; the ten-row interactive queue remains unchanged.
func offline_queue_request(client_id,offset,limit):
    var target=resolve_local_player(client_id)
    if target.empty() or typeof(offset)!=TYPE_INT or offset<0 or offset>100000 or typeof(limit)!=TYPE_INT or limit<1 or limit>32:return false
    return _start("player_queues/items",{"queue_id":target,"offset":offset,"limit":limit},{"kind":"offline_page","queue_id":target,"limit":limit})

func _offline_path(value):
    if typeof(value)!=TYPE_STRING or value.empty() or value.length()>1024 or value.begins_with("/") or "\\" in value or ":" in value:return false
    for part in value.split("/",true):
        if part in ["",".",".."]:return false
    for c in value:
        if c.ord_at(0)<32 or c.ord_at(0)==127:return false
    return true

func offline_track_request(media):
    if typeof(media)!=TYPE_DICTIONARY or not _id(media.get("item_id")) or not _id(media.get("provider")):return false
    # Metadata only; provider streams and preview clips are never downloaded.
    return _start("music/tracks/get",{"item_id":media.item_id,"provider_instance_id_or_domain":media.provider},{"kind":"offline_track"})
