extends Node
# Bounded jobs wrap the same catalog and exact-own-Sendspin route checks as TV.
# The browser supplies only page-local row handles, never a player or media URI.
var app=null
var catalog=null
var queue_request=null
var jobs={}
var active={}
var page={}
var page_id=0
var serial=0
var binding_origin=""
var binding_hash=""
var credential_watch=null
var _elapsed=0.0

func _reply(code,value):return {"code":code,"body":value}
func _error(message,code=409):return _reply(code,{"error":message})
func _safe(value,limit=160):
    var text=str(value).substr(0,limit)
    return "[unavailable]" if "://" in text else text
func mutation_busy():return not active.empty() and active.get("kind") in ["add","add_page","play"]
func _valid_shape(value,keys):
    if typeof(value)!=TYPE_DICTIONARY:return false
    for key in value:
        if not key in keys:return false
    return true

func route(method,path,value):
    if method=="GET" and path.begins_with("/api/operations/"):
        var id=path.trim_prefix("/api/operations/")
        return _reply(200,jobs[id].result) if jobs.has(id) else _error("This request expired. Refresh and try again.",404)
    if method!="POST":return _error("Unknown route",404)
    var kind=""
    if path=="/api/library":kind="browse"
    elif path=="/api/library/open":kind="open"
    elif path=="/api/library/page":kind="page"
    elif path=="/api/library/play":kind="play"
    elif path=="/api/queue/add":kind="add"
    elif path=="/api/queue/add-page":kind="add_page"
    elif path=="/api/queue/refresh":kind="queue"
    else:return _error("Unknown route",404)
    var allowed=["kind","search","offset"] if kind=="browse" else (["page_id","offset","search"] if kind=="page" else (["page_id","item","request_id"] if kind in ["open","play","add"] else (["page_id","request_id"] if kind=="add_page" else [])))
    if not _valid_shape(value,allowed):return _error("Invalid request fields",400)
    var request_id=str(value.get("request_id",""))
    if kind in ["add","add_page","play"]:
        var valid=RegEx.new();valid.compile("^[A-Za-z0-9_-]{8,64}$")
        if valid.search(request_id)==null:return _error("A unique request_id is required",400)
        for id in jobs:
            if jobs[id].get("request_id")==request_id:
                if jobs[id].get("fingerprint")!=to_json([kind,value]):return _error("Request ID already used for another action",409)
                return _reply(202,{"operation":id,"state":"loading"})
    if not active.empty():return _error("A music request is still in progress. Wait for its result.")
    if not _prepare_catalog():return _error("Connect your Music Assistant library in Kinegra Amp Settings first.")
    var item={}
    var media=[]
    if kind in ["open","play","add","add_page","page"]:
        if typeof(value.get("page_id"))!=TYPE_REAL and typeof(value.get("page_id"))!=TYPE_INT:return _error("Refresh the library page first.")
        if value.page_id!=page_id or page.empty():return _error("This library page changed. Refresh it before choosing music.")
        if kind in ["open","play","add"]:
            var row=value.get("item")
            if not typeof(row) in [TYPE_REAL,TYPE_INT] or int(row)!=row or row<0 or row>=catalog.current_page.get("items",[]).size():return _error("Choose a track from the current library page.",400)
            item=catalog.current_page.items[int(row)].duplicate(true)
            if kind=="open" and not item.get("media_type") in ["album","playlist"]:return _error("Choose an album or playlist.",400)
            if kind in ["play","add"] and item.get("media_type")=="track" and not item.get("available",false):return _error("This track is unavailable.")
            media=[item]
        elif kind=="add_page":
            for row in catalog.current_page.get("items",[]):
                if row.get("media_type")=="track" and row.get("available",false):media.append(row.duplicate(true))
            if media.empty():return _error("This page has no available tracks to add.")
    if kind in ["browse","page"]:
        var offset=value.get("offset",0)
        if not typeof(offset) in [TYPE_INT,TYPE_REAL] or int(offset)!=offset or offset<0 or offset>10000 or typeof(value.get("search",""))!=TYPE_STRING or value.get("search","").length()>100:return _error("Invalid search or page",400)
        if kind=="browse" and not value.get("kind","tracks") in ["tracks","albums","playlists"]:return _error("Unknown library category",400)
    serial+=1
    var id=str(serial)
    if jobs.size()>=16:
        var oldest=jobs.keys()[0]
        for key in jobs:
            if int(key)<int(oldest):oldest=key
        jobs.erase(oldest)
    jobs[id]={"request_id":request_id,"fingerprint":to_json([kind,value]),"result":{"operation":id,"state":"loading","message":"Reading your music library…"}}
    active={"id":id,"kind":kind,"phase":"catalog","deadline":OS.get_ticks_msec()+35000,"item":item,"media":media,"payload":value.duplicate(true),"sent":false}
    var started=false
    if kind=="browse":started=catalog.browse(value.get("kind","tracks"),value.get("search",""),int(value.get("offset",0)))
    elif kind=="page":started=catalog.playlist_page(int(value.get("offset",0)),value.get("search",""))
    elif kind=="open":
        catalog.select_index(int(value.item))
        started=catalog.album_items() if item.media_type=="album" else catalog.playlist_items()
    else:started=_prepare_playback()
    if not started and not active.empty():_finish(false,{},"The request could not start. Check the library/playback connection.")
    return _reply(202,{"operation":id,"state":"loading"})

func _prepare_catalog():
    if app==null or app.ma_panel==null or app.ma_panel.library_disconnected:return false
    var token=app._library_credential()
    var origin=app.ma_panel._credential_endpoint()
    if token.empty() or origin.empty():return false
    if credential_watch!=app.ma_panel:
        credential_watch=app.ma_panel
        if credential_watch.has_signal("credential_session_closed"):credential_watch.connect("credential_session_closed",self,"_credentials_closed")
    if catalog==null:
        catalog=load("res://scripts/MACatalog.gd").new()
        catalog.metadata_timeout_seconds=12.0
        add_child(catalog)
        catalog.connect("page_ready",self,"_page_ready")
        catalog.connect("players_ready",self,"_players_ready")
        catalog.connect("state_changed",self,"_catalog_state")
        catalog.connect("queued_playlist_context",self,"_playlist_context")
    if origin!=binding_origin or token.sha256_text()!=binding_hash or catalog.token.empty():
        page.clear()
        if not catalog.configure(app.ma_panel.endpoint_edit.text,token,[],app.ma_panel.lan_trust.pressed):return false
        binding_origin=origin
        binding_hash=token.sha256_text()
    token=""
    return true

func _credentials_closed(_reason):cancel()
func _binding_current():
    if app==null or app.ma_panel==null or app.ma_panel.library_disconnected or app.ma_panel._credential_endpoint()!=binding_origin:return false
    var current=app._library_credential(false)
    return current.empty() or current.sha256_text()==binding_hash

func _prepare_playback():
    if app.tv_queue_request!=null and not app._queue_read_in_progress():return false
    if app.ma_panel.catalog.request_node!=null and app.ma_panel.catalog.request_context.get("kind") in ["enqueue","play","local_queue_action"]:return false
    if app._sendspin_controls().empty() and active.kind!="play":
        var local=app.get("offline_music")
        var pcm=app.get("local_pcm")
        var preview=app.get("native_transport")
        if (local!=null and local.is_playing()) or (pcm!=null and pcm.active) or (preview!=null and preview.active):
            _finish(false,{},"Current local playback is preserved. Stop it before connecting Music Assistant, or choose an explicit Play action.")
            return false
    active.phase="connect"
    if app._sendspin_controls().empty() and not app.ma_panel._sendspin_start():return false
    active["facade"]=app.sendspin_facade
    return app.sendspin_facade!=null

func _process(delta):
    _elapsed+=delta
    if _elapsed<.1 or active.empty():return
    _elapsed=0.0
    if not _binding_current():
        _finish(false,{},"Library access changed. Reconnect and refresh the page.")
        return
    if OS.get_ticks_msec()>active.deadline:
        _finish(false,{},"Result unknown: check Queue before retrying." if active.sent else "Playback is not ready. Check Kinegra Amp pairing and the Music Assistant connection.")
        return
    if active.get("phase")=="catalog_retry":
        if OS.get_ticks_msec()>=active.get("retry_at",0):
            active.phase="catalog"
            var payload=active.payload
            var started=catalog.browse(payload.get("kind","tracks"),payload.get("search",""),int(payload.get("offset",0))) if active.kind=="browse" else catalog.refresh_playlist(false)
            if not started and not active.empty():_finish(false,{},"The library retry could not start. Try again.")
        return
    if active.get("phase")=="route_wait":
        if OS.get_ticks_msec()>=active.get("retry_at",0):
            active.phase="players"
            if not catalog.discover_players():_finish(false,{},"Could not refresh the playback route.")
        return
    if active.get("phase")!="connect":return
    if active.get("facade")!=app.sendspin_facade:
        _finish(false,{},"Playback changed. Nothing queued; refresh and try again.")
        return
    var status=app._sendspin_controls()
    if status.empty():return
    active["client"]=str(status.get("client_id",""))
    active.phase="players"
    if not catalog.discover_players():_finish(false,{},"Could not verify this app's playback route.")

func _players_ready(_players):
    if active.empty() or active.get("phase")!="players":return
    if not _binding_current() or active.get("facade")!=app.sendspin_facade or str(app._sendspin_controls().get("client_id",""))!=active.get("client"):
        _finish(false,{},"Playback changed. No queue command sent.")
        return
    var resolved=catalog.resolve_local_player(active.client)
    print("WEB_MUSIC_ROUTE players=",catalog.player_routes.size()," complete=",catalog.player_routes_complete," own=",not resolved.empty()," kind=",active.kind)
    if resolved.empty():
        active["route_attempts"]=int(active.get("route_attempts",0))+1
        if active.route_attempts<4 and OS.get_ticks_msec()+1000<active.deadline:
            active.phase="route_wait"
            active["retry_at"]=OS.get_ticks_msec()+800
            jobs[active.id].result.message="Waiting for Kinegra Amp's playback connection…"
        else:_finish(false,{},"Could not verify Kinegra Amp's own playback route. Nothing sent to another player.")
        return
    if active.kind=="queue":
        active.phase="queue"
        queue_request=load("res://scripts/MATvQueueRequest.gd").new()
        add_child(queue_request)
        queue_request.connect("completed",self,"_queue_ready")
        if not queue_request.begin(app,app.sendspin_facade,app.ma_panel.endpoint_edit.text,catalog.token,app.ma_panel.lan_trust.pressed,"items"):_finish(false,{},"Queue unavailable. Check playback pairing and retry.")
        return
    active.phase="mutation"
    active.sent=true # An ambiguous HTTP result must never cause an automatic retry.
    var accepted=catalog.play_local_selection(active.client,active.item) if active.kind=="play" else catalog.enqueue_local_media(active.client,active.media)
    if not accepted:
        _finish(false,{},"The queue request could not start. Check Queue before retrying.")
    elif active.kind=="play":
        app.music_ui.set_playback_context("ma")
        app.music_ui.invalidate_tv_queue()
        app._watch_tv_audio(true)

func _catalog_state(state,_detail):
    if active.empty():return
    if state in ["queue_added","play_requested"] and active.get("phase")=="mutation":
        if active.kind=="play":
            app._arm_playback_recovery()
            app._prepare_stream_visuals()
        if app.tv_queue_timer!=null:app.tv_queue_timer.start(.25)
        _finish(true,{},"Play requested in Kinegra Amp." if active.kind=="play" else "Added to Queue.")
    elif state in ["auth_expired","permission_denied","disconnected","malformed_reply","command_failed","stale_reply","unsafe_route","invalid_request","selection_expired","busy"]:
        print("WEB_MUSIC_CATALOG state=",state," result=",catalog.last_result_code," http=",catalog.last_http_code," kind=",active.kind)
        if not active.get("sent",false) and active.kind in ["browse","open"] and state in ["disconnected","malformed_reply","stale_reply"] and int(active.get("read_retries",0))<1 and OS.get_ticks_msec()+13000<active.deadline:
            active["read_retries"]=1
            active.phase="catalog_retry"
            active["retry_at"]=OS.get_ticks_msec()+350
            jobs[active.id].result.message="Retrying a library read…"
            return
        var detail="Result unknown: check Queue before retrying." if active.get("sent",false) else "Music Assistant could not complete this library read after a retry. Check its connection and try again."
        if state in ["auth_expired","permission_denied"]:detail="Music Assistant rejected library access. Reconnect the library on the TV."
        elif state=="command_failed":detail=_detail
        if active.kind=="play" and active.get("sent",false):app._set_tv_playback_error(detail)
        _finish(false,{},detail)

func _playlist_context(name,ids):
    if app!=null and app.music_ui!=null and app.music_ui.has_method("_remember_playlist_context"):app.music_ui._remember_playlist_context(name,ids)

func _page_ready(value):
    if active.empty() or not active.kind in ["browse","open","page"]:return
    page_id+=1
    var rows=[]
    for index in range(min(25,value.get("items",[]).size())):
        var item=value.items[index]
        rows.append({"id":index,"title":_safe(item.get("name","Untitled")),"artist":_safe(item.get("artist","")),"album":_safe(item.get("album","")),"type":str(item.get("media_type","track")),"available":item.get("available",false)==true})
    page={"page_id":page_id,"kind":value.get("kind","tracks"),"offset":value.get("offset",0),"search":value.get("search",""),"has_more":value.get("may_have_more",false),"items":rows,"collection":_safe(value.get("playlist",{}).get("name",""))}
    _finish(true,{"page":page.duplicate(true)},"Library loaded." if not rows.empty() else "No music found. Try another search or category.")

func _queue_ready(ok,_action,snapshot,_detail):
    if active.empty() or active.kind!="queue":return
    var rows=[]
    for item in snapshot.get("items",[]):
        if typeof(item)==TYPE_DICTIONARY:rows.append({"title":_safe(item.get("name","Untitled")),"artist":_safe(item.get("artist",""))})
    print("WEB_MUSIC_QUEUE ok=",ok," detail=",_safe(_detail))
    _finish(ok,{"queue":{"items":rows,"limit":10,"state":_safe(snapshot.get("state","unknown"))}},"Upcoming Queue loaded." if ok else _safe(_detail))

func _finish(ok,data,message):
    if active.empty():return
    var result={"operation":active.id,"state":"done" if ok else "error","message":message}
    for key in data:result[key]=data[key]
    jobs[active.id].result=result
    active.clear()
    if queue_request!=null:
        queue_request.cancel()
        queue_request.queue_free()
        queue_request=null

func cancel():
    if not active.empty():_finish(false,{},"Library access or web remote changed. Refresh before retrying.")
    if catalog!=null:
        catalog.close()
        catalog.queue_free()
        catalog=null
    page.clear()
    jobs.clear()
    binding_origin=""
    binding_hash=""

func _exit_tree():cancel()
