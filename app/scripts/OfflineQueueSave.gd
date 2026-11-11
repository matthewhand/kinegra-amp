extends Node
# Explicit local-file copies, separate from Music Assistant's playback streams.
signal changed
const MAX_TRACKS=1024
const MAX_BYTES=67108864
const SEGMENT_BYTES=1048576
const MAX_CHECKPOINT_BYTES=4194304
const MAX_RETRIES=2
var app=null
var state="idle"
var message=""
var active=false
var copied=0
var skipped=0
var failed=0
var entries=[]
var capture_rows=[]
var track_path=""
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
var prepared={}
var outcomes=[]
var checkpoint_binding=""
var download_hash=""
var segment_start=0
var segment_end=0
var retry_timer=null
var retries=0
var checkpoint_path="user://offline_queue_copy_v1.json"
var queue_policy=preload("res://scripts/MAQueuePolicy.gd").new()
var hash_thread=null
var config_path="user://offline_source.cfg"
var saved_queue_path="user://saved_offline_queue.cfg"
var queue_store=preload("res://scripts/QueueStore.gd").new()
var policy=preload("res://scripts/ConnectionPolicy.gd").new()

func _ready():
    set_process(false)
    retry_timer=Timer.new()
    retry_timer.one_shot=true
    add_child(retry_timer)
    retry_timer.connect("timeout",self,"_perform")
    var saved=queue_store.read(saved_queue_path)
    if saved.ok:saved_indices=saved.items.duplicate()
    call_deferred("_restore_checkpoint")

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

func _binding(endpoint, origin):
    return (endpoint+"\n"+origin).sha256_text()

func _part_path():
    return app.offline_music.user_library.directory.plus_file("queue-download.part")

func _length(path):
    var file=File.new()
    if file.open(path,File.READ)!=OK:return 0
    var bytes=file.get_len()
    file.close()
    return bytes

func _save_checkpoint():
    var value={"version":1,"binding":checkpoint_binding,"entries":entries,"outcomes":outcomes,"download_hash":download_hash}
    var encoded=to_json(value)
    if encoded.to_utf8().size()>MAX_CHECKPOINT_BYTES:return false
    var temporary=checkpoint_path+".new"
    var file=File.new()
    if file.open(temporary,File.WRITE)!=OK:return false
    file.store_string(encoded)
    var ok=file.get_error()==OK
    file.close()
    var dir=Directory.new()
    if ok and dir.rename(temporary,checkpoint_path)==OK:return true
    dir.remove(temporary)
    return false

func _restore_checkpoint():
    if app==null or app.offline_music==null or active:return
    var store=app.offline_music.user_library
    var value=store._json(checkpoint_path,MAX_CHECKPOINT_BYTES)
    if typeof(value)!=TYPE_DICTIONARY or value.get("version")!=1 or not store._hex(value.get("binding")):return
    var rows=value.get("entries")
    var results=value.get("outcomes")
    var digest=value.get("download_hash")
    if typeof(rows)!=TYPE_ARRAY or rows.empty() or rows.size()>MAX_TRACKS or typeof(results)!=TYPE_ARRAY or results.size()!=rows.size():return
    if digest!="" and not store._hex(digest):return
    var validator=preload("res://scripts/MACatalog.gd").new()
    var seen={}
    var valid=true
    for i in range(rows.size()):
        var row=rows[i]
        if typeof(row)!=TYPE_DICTIONARY or not queue_policy.item_id(row.get("queue_item_id")) or seen.has(row.get("queue_item_id")) or typeof(row.get("name"))!=TYPE_STRING or row.name.length()>120 or typeof(row.get("media"))!=TYPE_DICTIONARY or not validator._id(row.media.get("item_id")) or not validator._id(row.media.get("provider")) or (not results[i] in ["","skipped","failed"] and not store._hex(results[i])):
            valid=false
            break
        seen[row.queue_item_id]=true
    validator.free()
    if not valid:return
    entries=rows
    outcomes=results
    checkpoint_binding=value.binding
    download_hash=digest
    _sync_saved_queue()
    state="paused" if has_pending() else "complete"
    if has_pending():_status("Offline copy paused. Choose Resume Saving to continue.")

func has_pending():
    return not checkpoint_binding.empty() and ("" in outcomes or "failed" in outcomes)

func discard():
    if active or hash_thread!=null or not has_pending():return false
    if Directory.new().remove(checkpoint_path)!=OK:
        _status("Could not discard the pending copy. Try again.")
        return false
    _remove_part()
    checkpoint_binding="";download_hash="";outcomes.clear();entries.clear()
    state="idle"
    _status("Pending copy discarded. Completed files remain in Offline Library.")
    return true

func _owner_current():
    if app==null or app.app_is_paused or app.ma_panel==null or app.ma_panel.library_disconnected or catalog==null:return false
    if catalog.endpoint!=app.ma_panel.endpoint_edit.text.strip_edges().trim_suffix("/"):return false
    # A captured snapshot can finish independently of the current playback route.
    if state=="copying":return true
    if session==null or not is_instance_valid(session) or app.sendspin_facade!=session or session.client==null:return false
    var status=session.client.status()
    return typeof(status)==TYPE_DICTIONARY and status.get("paired")==true and status.get("client_id")==client_id

func begin():
    if active or hash_thread!=null:return false
    if app==null or app.offline_music==null or app.offline_music.user_library.blocked:return false
    var config=ConfigFile.new()
    if config.load(config_path)!=OK or _origin(config.get_value("source","origin","")).empty() or not _valid_key(config.get_value("source","key","")):
        _status("Set up a local-file source in Settings before saving.")
        return false
    var resuming=has_pending()
    if not resuming and not app._queue_controls_available():
        _status("Connect Music Assistant playback before saving its queue.")
        return false
    var endpoint=app.ma_panel.endpoint_edit.text.strip_edges().trim_suffix("/")
    var origin=_origin(config.get_value("source","origin",""))
    if resuming and _binding(endpoint,origin)!=checkpoint_binding:
        _status("This copy belongs to another source. Restore its settings or discard the pending copy.")
        return false
    var credential=app._library_credential()
    if credential.empty():
        _status("Connect Music Assistant library access to continue saving.")
        return false
    source_origin=origin
    source_key=config.get_value("source","key","")
    session=app.sendspin_facade
    client_id=str(app._sendspin_controls().get("client_id",""))
    catalog=preload("res://scripts/MACatalog.gd").new()
    add_child(catalog)
    if not catalog.configure(endpoint,credential,[],app.ma_panel.lan_trust.pressed):
        _cleanup()
        _status("Could not connect Music Assistant library access.")
        return false
    catalog.connect("players_ready",self,"_players")
    catalog.connect("local_queue_snapshot",self,"_snapshot")
    catalog.connect("offline_queue_page",self,"_page")
    catalog.connect("offline_track",self,"_track")
    catalog.connect("state_changed",self,"_catalog_state")
    active=true
    retries=0;position=0;offset=0
    if resuming:
        for i in range(outcomes.size()):
            if outcomes[i]=="failed":outcomes[i]=""
        state="copying"
        _sync_saved_queue()
        _next()
    else:
        seen_queue_ids.clear()
        capture_rows.clear()
        state="reading";phase="snapshot"
        _status("Reading this app's queue…")
        _perform()
    return true

func _perform():
    if not active:return
    if not _owner_current():
        _finish("paused","Offline copy paused because the connection changed.")
        return
    match phase:
        "snapshot","page":
            if not catalog.discover_players():_retry(phase)
        "track":
            if not catalog.offline_track_request(entries[position].media):_retry("track")
        "prepare":
            _http("/prepare",HTTPClient.METHOD_POST,to_json({"path":track_path}),2048)
        "download":
            _download()

func _players(_value):
    if not active:return
    if not _owner_current():
        _finish("paused","Offline copy paused because the connection changed.")
        return
    if phase=="snapshot":
        if not catalog.local_queue_request(client_id,"read"):_retry("snapshot")
    elif phase=="page":
        if catalog.resolve_local_player(client_id)!=queue_id:
            _finish("error","Queue route changed. Start saving again.")
        elif not catalog.offline_queue_request(client_id,offset,min(32,remaining)):
            _retry("page")

func _snapshot(value):
    if not active or phase!="snapshot":return
    if not _owner_current():
        _finish("paused","Offline copy paused because the connection changed.")
        return
    queue_id=catalog.resolve_local_player(client_id)
    var start=value.get("current_index",0)
    var count=value.get("item_count",-1)
    if start==null or start==-1:start=0
    if not typeof(start) in [TYPE_INT,TYPE_REAL] or int(start)!=start or not typeof(count) in [TYPE_INT,TYPE_REAL] or int(count)!=count or start<0 or count<start:
        _finish("error","Queue position is unavailable. Refresh playback and retry.")
        return
    if count-start<1 or count-start>MAX_TRACKS:
        _finish("error","Choose a queue with 1 to 1,024 current and upcoming tracks.")
        return
    offset=int(start);remaining=int(count)-offset;phase="page"
    retries=0
    _perform()

func _page(value):
    if not active or phase!="page":return
    if not _owner_current() or value.empty() or value.size()>remaining:
        _finish("error","Queue changed while reading. Start saving again.")
        return
    for row in value:
        var id=row.get("queue_item_id","")
        if not queue_policy.item_id(id) or seen_queue_ids.has(id):
            _finish("error","Queue changed while reading. Start saving again.")
            return
        seen_queue_ids[id]=true
    capture_rows.append_array(value)
    offset+=value.size();remaining-=value.size();retries=0
    if remaining>0:
        _perform()
        return
    entries=capture_rows.duplicate()
    capture_rows.clear()
    outcomes=[]
    outcomes.resize(entries.size())
    for i in range(outcomes.size()):outcomes[i]=""
    if not _remove_part():
        _finish("paused","Could not clear the old partial file.")
        return
    download_hash=""
    checkpoint_binding=_binding(catalog.endpoint,source_origin)
    state="copying"
    if not _save_checkpoint():
        _finish("error","Could not save the queue checkpoint. Check offline storage.")
        return
    _sync_saved_queue()
    _next()

func _catalog_state(value,_detail):
    if not active:return
    if value in ["disconnected","malformed_reply","command_failed","stale_reply"]:
        _retry(phase)
    elif value in ["auth_expired","permission_denied","unsafe_route","invalid_request"]:
        _finish("paused","Offline copy paused. Check Music Assistant library access and its queue.")

func _retry(next_phase):
    if not active or phase.empty() or not retry_timer.is_stopped():return
    if retries>=MAX_RETRIES:
        if state=="copying":_complete_track("failed")
        else:_finish("error","Could not read the Music Assistant queue. Try saving again.")
        return
    retries+=1
    phase=next_phase
    _status("Retrying %s (%d/%d)…" % ["track %d of %d" % [position+1,entries.size()] if state=="copying" else "the queue",retries,MAX_RETRIES])
    retry_timer.start(pow(2,retries-1))

func _next():
    if not active:return
    while position<outcomes.size() and outcomes[position]!="":position+=1
    if position>=entries.size():
        var result="complete" if failed==0 and copied>0 else ("partial" if copied>0 else "error")
        var summary="Saved %d queue entries; %d unsupported; %d failed." % [copied,skipped,failed]
        if failed>0:summary+=" Choose Resume Saving to retry failed tracks."
        _finish(result,summary)
        return
    retries=0
    phase="track"
    _status("Saving %d / %d · %d saved · %d skipped · %d failed" % [position+1,entries.size(),copied,skipped,failed])
    _perform()

func _track(value):
    if not active or phase!="track":return
    if value.empty():
        _complete_track("skipped")
        return
    track_path=value.path
    phase="prepare"
    _perform()

func _http(path,method,body,limit,range_header=""):
    request=HTTPRequest.new()
    request.timeout=135.0 if phase=="prepare" else 20.0
    request.body_size_limit=limit
    request.max_redirects=0
    request.download_chunk_size=32768
    request.use_threads=true
    var headers=["Authorization: Bearer "+source_key,"Content-Type: application/json"]
    if phase=="download":
        request.download_file=_part_path()+".segment"
        headers.append(range_header)
    add_child(request)
    request.connect("request_completed",self,"_response",[request])
    if request.request(source_origin+path,headers,true,method,body)!=OK:
        _response(-1,0,[],PoolByteArray(),request)

func _response(result,code,headers,body,owner):
    if owner!=request:return
    request.queue_free();request=null
    if not active:return
    if not _owner_current():
        _finish("paused","Offline copy paused because the connection changed.")
        return
    if code in [401,403]:
        _finish("paused","File-source access denied. Check the key and allowed client address.")
        return
    if phase=="download" and code in [404,416]:
        _retry("prepare")
        return
    if result!=HTTPRequest.RESULT_SUCCESS or not code in [200,206]:
        _retry(phase)
        return
    if phase=="prepare":
        if code!=200:_retry("prepare")
        else:_prepared(body)
    elif phase=="download":
        _receive_segment(code,headers)

func _prepared(body):
    var parsed=JSON.parse(body.get_string_from_utf8())
    var value=parsed.result if parsed.error==OK else null
    var store=app.offline_music.user_library
    if typeof(value)!=TYPE_DICTIONARY or not store._hex(value.get("sha256")) or not typeof(value.get("bytes")) in [TYPE_INT,TYPE_REAL] or value.bytes!=int(value.bytes) or value.bytes<4 or value.bytes>MAX_BYTES or not value.get("file","") in [value.sha256+".mp3",value.sha256+".ogg"]:
        _retry("prepare")
        return
    var slot=_slot_for(value.sha256)
    if slot>=0 and store.available(slot):
        _complete_track(value.sha256)
        return
    if store.blocked or (slot<0 and store.slots.size()>=store.MAX_IMPORTS):
        _finish("paused","Offline library is full or unavailable. Completed copies remain available.")
        return
    if download_hash!=value.sha256:
        if not _remove_part():
            _finish("paused","Could not clear the old partial file.")
            return
        download_hash=value.sha256
        if not _save_checkpoint():
            _finish("paused","Could not save download progress. Check offline storage.")
            return
    var title=store._title(entries[position].name)
    prepared={"bytes":int(value.bytes),"sha256":value.sha256,"file":value.file,
        "record":{"version":1,"sha256":value.sha256,"bytes":int(value.bytes),"file":"import_"+value.file,"title":"Saved track" if title.empty() else title}}
    phase="download"
    _perform()

func _download():
    var path=_part_path()
    segment_start=_length(path)
    if segment_start>prepared.bytes:
        if not _remove_part():
            _finish("paused","Could not clear an invalid partial file.")
            return
        segment_start=0
    if segment_start==prepared.bytes:
        _start_verify()
        return
    var reserve=268435456
    if _free_bytes(app.offline_music.user_library.directory)<reserve+prepared.bytes:
        _finish("paused","Offline storage is full or unavailable. Free space and resume saving.")
        return
    segment_end=min(segment_start+SEGMENT_BYTES,prepared.bytes)-1
    Directory.new().remove(path+".segment")
    _http("/audio/"+prepared.file,HTTPClient.METHOD_GET,"",MAX_BYTES,"Range: bytes=%d-%d" % [segment_start,segment_end])

func _receive_segment(code,headers):
    var path=_part_path()
    var chunk=path+".segment"
    var bytes=_length(chunk)
    if code==200:
        # Older helpers return the whole file. Replace the prefix, never append.
        if bytes!=prepared.bytes or Directory.new().rename(chunk,path)!=OK:
            _retry("download")
            return
    else:
        var expected="content-range: bytes %d-%d/%d" % [segment_start,segment_end,prepared.bytes]
        var matches=0
        for header in headers:
            if header.strip_edges().to_lower().begins_with("content-range:"):
                if header.strip_edges().to_lower()!=expected:
                    _retry("download")
                    return
                matches+=1
        if matches!=1 or bytes!=segment_end-segment_start+1 or _length(path)!=segment_start:
            _retry("download")
            return
        var source=File.new()
        var target=File.new()
        if source.open(chunk,File.READ)!=OK or target.open(path,File.WRITE if segment_start==0 else File.READ_WRITE)!=OK:
            _finish("paused","Could not write the partial file. Check offline storage.")
            return
        var payload=source.get_buffer(bytes)
        source.close()
        target.seek(segment_start)
        if payload.size()==bytes:target.store_buffer(payload)
        var written=payload.size()==bytes and target.get_error()==OK and target.get_position()==segment_end+1
        target.close()
        Directory.new().remove(chunk)
        if not written:
            _finish("paused","Could not write the partial file. Check offline storage.")
            return
    _perform()

func _start_verify():
    phase="verify"
    hash_thread=Thread.new()
    if hash_thread.start(self,"_verify",{"path":_part_path(),"bytes":prepared.bytes,"sha256":prepared.sha256})!=OK:
        hash_thread=null
        _finish("paused","Could not verify the file. Resume saving to retry.")
        return
    set_process(true)

func _verify(value):
    return _length(value.path)==value.bytes and File.new().get_sha256(value.path)==value.sha256

func _process(_delta):
    if hash_thread==null or hash_thread.is_alive():return
    var valid=hash_thread.wait_to_finish()
    hash_thread=null
    set_process(false)
    if not active:return
    if not _owner_current():
        _finish("paused","Offline copy paused because the connection changed.")
        return
    if not valid:
        if not _remove_part():
            _finish("paused","Could not clear a failed download.")
            return
        _retry("prepare")
        return
    var music=app.offline_music
    var store=music.user_library
    var record=prepared.record
    var slot=_slot_for(record.sha256)
    if slot>=0 and store.available(slot):
        _complete_track(record.sha256)
        return
    if store.blocked or (slot<0 and store.slots.size()>=store.MAX_IMPORTS):
        _finish("paused","Offline library is full or unavailable.")
        return
    var target=store.directory.plus_file(record.file)
    var receipt=File.new()
    var temp=target+".meta.json.new"
    var dir=Directory.new()
    if receipt.open(temp,File.WRITE)!=OK:
        _finish("paused","Could not save the offline receipt.")
        return
    receipt.store_string(to_json(record))
    var ok=receipt.get_error()==OK
    receipt.close()
    # Publish the receipt first. The library admits it only when the audio exists.
    if not ok or dir.rename(temp,target+".meta.json")!=OK or dir.rename(_part_path(),target)!=OK:
        dir.remove(temp)
        _finish("paused","Could not finish the offline copy. Check storage and resume saving.")
        return
    music.refresh_user_library()
    slot=_slot_for(record.sha256)
    if slot<0 or not store.available(slot):
        _finish("paused","Could not add the saved file to Offline Library. Resume saving to retry.")
        return
    _complete_track(record.sha256)

func _slot_for(digest):
    var slots=app.offline_music.user_library.slots
    for i in range(slots.size()):
        if slots[i].sha256==digest:return i
    return -1

func _sync_saved_queue():
    copied=0;skipped=0;failed=0
    saved_indices.clear()
    var store=app.offline_music.user_library
    var indices={}
    for i in range(store.slots.size()):
        if not store.slots[i].deleted:indices[store.slots[i].sha256]=i+4
    for result in outcomes:
        match result:
            "skipped":skipped+=1
            "failed":failed+=1
            "":
                pass
            _:
                copied+=1
                if indices.has(result):saved_indices.append(indices[result])

func _complete_track(outcome):
    if not _remove_part():
        _finish("paused","Could not clear the partial file. Check offline storage.")
        return
    phase=""
    download_hash=""
    outcomes[position]=outcome
    if not _save_checkpoint():
        outcomes[position]=""
        _finish("paused","Could not save queue progress. Resume saving to retry.")
        return
    _sync_saved_queue()
    position+=1
    call_deferred("_next")

func play_saved():
    if app==null:return false
    if not checkpoint_binding.empty():_sync_saved_queue()
    if saved_indices.empty():return false
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
    var path=_part_path()
    var dir=Directory.new()
    return not File.new().file_exists(path) or dir.remove(path)==OK

func _cleanup():
    if retry_timer!=null:retry_timer.stop()
    if request!=null:
        request.cancel_request();request.queue_free();request=null
    if catalog!=null:
        catalog.close();catalog.queue_free();catalog=null
    if app!=null and is_instance_valid(app.offline_music):Directory.new().remove(_part_path()+".segment")
    source_key="";source_origin="";session=null;client_id="";queue_id="";track_path=""
    prepared.clear()

func _finish(value,text):
    active=false;state=value
    if not saved_indices.empty() and not queue_store.write(saved_queue_path,saved_indices):
        text+=" Completed files remain in Offline Library."
    _cleanup()
    _status(text)

func cancel():
    if active:
        _finish("paused","Saving paused. Completed tracks remain in Offline Library.")

func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED:cancel()

func _exit_tree():
    active=false;_cleanup()
    if hash_thread!=null:hash_thread.wait_to_finish();hash_thread=null

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
