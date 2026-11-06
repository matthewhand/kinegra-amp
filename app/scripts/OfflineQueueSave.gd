extends Node
# Explicit local-file copies, separate from Music Assistant's playback streams.
signal changed
const MAX_TRACKS=1024
const MAX_BYTES=67108864
var app=null
var state="idle"
var message=""
var active=false
var copied=0
var skipped=0
var failed=0
var entries=[]
var seen_queue_ids={}
var saved_indices=[]
var source_origin=""
var source_key=""
var catalog=null
var request=null
var session=null
var client_id=""
var queue_id=""
var offset=0
var remaining=0
var position=0
var phase=""
var part=""
var prepared={}
var hash_thread=null
var config_path="user://offline_source.cfg"
var saved_queue_path="user://saved_offline_queue.cfg"
var queue_store=preload("res://scripts/QueueStore.gd").new()
var policy=preload("res://scripts/ConnectionPolicy.gd").new()

func _ready():
    set_process(false)
    var saved=queue_store.read(saved_queue_path)
    if saved.ok:saved_indices=saved.items.duplicate()

func _origin(value):
    if typeof(value)!=TYPE_STRING:return ""
    var parsed=policy.origin(value,["http"],true)
    return parsed.get("prefix","") if not parsed.empty() else ""

func configured():
    var config=ConfigFile.new()
    return config.load(config_path)==OK and not _origin(config.get_value("source","origin","")).empty() and _valid_key(config.get_value("source","key",""))

func _valid_key(value):
    if typeof(value)!=TYPE_STRING or value.length()<32 or value.length()>128:return false
    for c in value:
        if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":return false
    return true

func configure(origin,key):
    if active or _origin(origin).empty() or not _valid_key(key):return false
    var config=ConfigFile.new()
    config.set_value("source","origin",_origin(origin))
    config.set_value("source","key",key)
    if config.save(config_path+".new")!=OK:return false
    return Directory.new().rename(config_path+".new",config_path)==OK

func _status(text):
    message=text
    emit_signal("changed")

func _owner_current():
    if app==null or app.app_is_paused or app.ma_panel==null or app.ma_panel.library_disconnected or catalog==null:return false
    # Once captured, this immutable snapshot may finish while local copies play.
    if state=="copying":return catalog.endpoint==app.ma_panel.endpoint_edit.text.strip_edges().trim_suffix("/")
    if session==null or not is_instance_valid(session) or app.sendspin_facade!=session or session.client==null:return false
    var status=session.client.status()
    return typeof(status)==TYPE_DICTIONARY and status.get("paired")==true and status.get("client_id")==client_id and catalog!=null and catalog.endpoint==app.ma_panel.endpoint_edit.text.strip_edges().trim_suffix("/")

func begin():
    if active or hash_thread!=null:return false
    if app==null or app.offline_music==null or app.offline_music.user_library.blocked:return false
    if not configured():
        _status("Set up a local-file source in Settings before saving. Streaming providers cannot be downloaded.")
        return false
    if not app._queue_controls_available():
        _status("Connect Music Assistant playback before saving its queue.")
        return false
    var config=ConfigFile.new()
    if config.load(config_path)!=OK:return false
    source_origin=_origin(config.get_value("source","origin",""))
    source_key=config.get_value("source","key","")
    session=app.sendspin_facade
    client_id=str(app._sendspin_controls().get("client_id",""))
    catalog=preload("res://scripts/MACatalog.gd").new()
    add_child(catalog)
    if not catalog.configure(app.ma_panel.endpoint_edit.text,app._library_credential(),[],app.ma_panel.lan_trust.pressed):
        _cleanup()
        return false
    catalog.connect("players_ready",self,"_players")
    catalog.connect("local_queue_snapshot",self,"_snapshot")
    catalog.connect("offline_queue_page",self,"_page")
    catalog.connect("offline_track",self,"_track")
    catalog.connect("state_changed",self,"_catalog_state")
    active=true
    copied=0;skipped=0;failed=0;position=0;offset=0
    entries.clear();saved_indices.clear();seen_queue_ids.clear()
    state="reading";phase="snapshot"
    _status("Reading this app's queue…")
    return catalog.discover_players()

func _players(_value):
    if not active:return
    if not _owner_current():
        _finish("cancelled","Playback connection changed; nothing further copied.")
        return
    if phase=="snapshot":
        if not catalog.local_queue_request(client_id,"read"):_finish("error","Queue route could not be verified.")
    elif phase=="page":
        if catalog.resolve_local_player(client_id)!=queue_id or not catalog.offline_queue_request(client_id,offset,min(32,remaining)):_finish("error","Queue route changed; retry Save.")

func _snapshot(value):
    if not active or phase!="snapshot":return
    queue_id=catalog.resolve_local_player(client_id)
    var start=value.get("current_index",0)
    var count=value.get("item_count",-1)
    if start==null or start==-1:start=0
    if not typeof(start) in [TYPE_INT,TYPE_REAL] or int(start)!=start or not typeof(count) in [TYPE_INT,TYPE_REAL] or int(count)!=count or start<0 or count<start:
        _finish("error","Queue position is unavailable / refresh playback and retry.")
        return
    if count-start<1:
        _finish("error","Your queue is empty / add tracks in Music Assistant first.")
        return
    if count-start>MAX_TRACKS:
        _finish("error","This queue has %d current/upcoming tracks; the limit is 1024. Choose a smaller queue." % int(count-start))
        return
    offset=int(start);remaining=int(count)-offset;phase="page"
    catalog.discover_players()

func _page(value):
    if not active or phase!="page":return
    if not _owner_current() or value.empty() or value.size()>remaining:
        _finish("error","Queue changed while reading; retry Save.")
        return
    for row in value:
        var id=row.get("queue_item_id","")
        if not preload("res://scripts/MAQueuePolicy.gd").new().item_id(id) or seen_queue_ids.has(id):
            _finish("error","Queue changed while reading; retry Save.")
            return
        seen_queue_ids[id]=true
    entries.append_array(value)
    offset+=value.size();remaining-=value.size()
    if remaining>0:
        catalog.discover_players()
    else:
        state="copying";phase="track"
        _next()

func _catalog_state(value,_detail):
    if active and value in ["auth_expired","permission_denied","disconnected","malformed_reply","command_failed","stale_reply","unsafe_route","invalid_request"]:
        _finish("error","Could not read queue metadata. Completed copies remain in Offline Library.")

func _next():
    if not active:return
    if position>=entries.size():
        _finish("complete" if copied>0 else "error","Saved %d tracks; %d unsupported; %d failed. Choose Play Saved Queue or Offline Library." % [copied,skipped,failed])
        return
    _status("Saving %d / %d · %d saved · %d skipped · %d failed" % [position+1,entries.size(),copied,skipped,failed])
    var entry=entries[position]
    phase="track"
    if not _owner_current():
        _finish("cancelled","Playback connection changed; completed copies remain available.")
    elif not catalog.offline_track_request(entry.media):
        skipped+=1;position+=1
        call_deferred("_next")

func _track(value):
    if not active or phase!="track":return
    if value.empty():
        skipped+=1;position+=1;call_deferred("_next")
        return
    entries[position]["path"]=value.path
    phase="prepare"
    _http("/prepare",HTTPClient.METHOD_POST,to_json({"path":value.path}),2048)

func _http(path,method,body,limit):
    request=HTTPRequest.new()
    request.timeout=135.0
    request.body_size_limit=limit
    request.max_redirects=0
    request.download_chunk_size=32768
    request.use_threads=true
    if phase=="download":request.download_file=part
    add_child(request)
    request.connect("request_completed",self,"_response",[request])
    if request.request(source_origin+path,["Authorization: Bearer "+source_key,"Content-Type: application/json"],true,method,body)!=OK:
        _response(-1,0,[],PoolByteArray(),request)

func _response(result,code,_headers,body,owner):
    if owner!=request:return
    request.queue_free();request=null
    if not active:return
    if code in [401,403]:
        _finish("error","File-source access denied / check its key and allowed client address.")
        return
    if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
        failed+=1;position+=1;_remove_part();call_deferred("_next")
        return
    if phase=="prepare":
        var parsed=JSON.parse(body.get_string_from_utf8())
        var value=parsed.result if parsed.error==OK else null
        var store=app.offline_music.user_library
        if typeof(value)!=TYPE_DICTIONARY or not store._hex(value.get("sha256")) or not typeof(value.get("bytes")) in [TYPE_INT,TYPE_REAL] or value.bytes!=int(value.bytes) or value.bytes<4 or value.bytes>MAX_BYTES or not value.get("file","") in [value.sha256+".mp3",value.sha256+".ogg"]:
            _finish("error","Local-file source returned invalid audio details.")
            return
        prepared=value
        var name="import_"+value.file
        var record={"sha256":value.sha256,"bytes":int(value.bytes),"file":name,"title":store._title(entries[position].name)}
        for i in range(store.slots.size()):
            if store.slots[i].sha256==value.sha256 and store.available(i):
                saved_indices.append(i+4);copied+=1;position+=1;call_deferred("_next")
                return
        var free=_free_bytes(store.directory)
        if free<0:
            _finish("error","Could not measure offline storage; completed copies remain available.")
            return
        if store.slots.size()>=store.MAX_IMPORTS or free<int(value.bytes)+268435456:
            _finish("error","Offline storage is full; completed copies remain available.")
            return
        prepared["record"]=record
        part=store.directory.plus_file("queue-download.part")
        _remove_part()
        phase="download"
        _http("/audio/"+value.file,HTTPClient.METHOD_GET,"",MAX_BYTES)
    elif phase=="download":
        phase="verify"
        hash_thread=Thread.new()
        if hash_thread.start(self,"_verify",{"path":part,"bytes":prepared.bytes,"sha256":prepared.sha256})!=OK:
            hash_thread=null
            _finish("error","Could not verify the downloaded file.")
            return
        set_process(true)

func _verify(value):
    var file=File.new()
    if file.open(value.path,File.READ)!=OK:return false
    var length=file.get_len()
    file.close()
    return length==value.bytes and file.get_sha256(value.path)==value.sha256

func _process(_delta):
    if hash_thread==null or hash_thread.is_alive():return
    var valid=hash_thread.wait_to_finish()
    hash_thread=null;set_process(false)
    if not active:
        _remove_part()
        return
    var store=app.offline_music.user_library
    var target=store.directory.plus_file(prepared.record.file)
    if not valid or Directory.new().rename(part,target)!=OK:
        failed+=1;position+=1;_remove_part();call_deferred("_next")
        return
    part=""
    var receipt=File.new()
    var record=prepared.record.duplicate(true)
    record["version"]=1
    if receipt.open(target+".meta.json.new",File.WRITE)!=OK:
        _finish("error","Could not save offline receipt.")
        return
    receipt.store_string(to_json(record))
    var ok=receipt.get_error()==OK
    receipt.close()
    if not ok or Directory.new().rename(target+".meta.json.new",target+".meta.json")!=OK:
        _finish("error","Could not save offline receipt.")
        return
    app.offline_music.refresh_user_library()
    var found=-1
    for i in range(store.slots.size()):
        if store.slots[i].sha256==record.sha256 and store.available(i):found=i+4
    if found>=0:
        saved_indices.append(found);copied+=1
    else:failed+=1
    position+=1
    call_deferred("_next")

func play_saved():
    if saved_indices.empty() or app==null:return false
    var music=app.offline_music
    if music.queue_load_blocked:return false
    for index in saved_indices:
        if not music.available(index):return false
    # Explicit Play replaces only Kinegra Amp's local queue, never the MA queue.
    music.queue_clear()
    for i in saved_indices:
        if not music.queue_track(i):return false
    app._stop_audio()
    if not music._play_queued()>0:return false
    app.music_ui.set_playback_context("offline")
    app.music_ui._close_queue()
    return true

func _remove_part():
    if not part.empty():Directory.new().remove(part)

func _cleanup():
    if request!=null:
        request.cancel_request();request.queue_free();request=null
    if catalog!=null:
        catalog.close();catalog.queue_free();catalog=null
    source_key="";source_origin="";session=null;client_id="";queue_id=""
    if hash_thread==null:_remove_part()

func _finish(value,text):
    active=false;state=value
    if not saved_indices.empty() and not queue_store.write(saved_queue_path,saved_indices):text+=" Queue order could not be saved; audio copies remain available."
    _cleanup()
    _status(text)

func cancel():
    if active:_finish("cancelled","Saving cancelled. Completed tracks remain in Offline Library.")

func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED:cancel()

func _exit_tree():
    active=false;_cleanup()
    if hash_thread!=null:hash_thread.wait_to_finish();hash_thread=null;_remove_part()

func _free_bytes(directory):
    if OS.get_name()=="Android":
        if not Engine.has_singleton("ShieldAmpTokenStore"):return -1
        var text=Engine.get_singleton("ShieldAmpTokenStore").offlineUsableBytes()
        if typeof(text)!=TYPE_STRING or not text.is_valid_integer():return -1
        return int(text)
    var dir=Directory.new()
    if dir.open(directory)!=OK:return -1
    var value=dir.get_space_left()
    return value if value>=0 else -1
