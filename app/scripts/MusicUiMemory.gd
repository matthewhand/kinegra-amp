extends Reference
# Nonsecret navigation preferences only. Queue contents/position remain server-owned.
const VERSION=1
const MAX_BYTES=4096
const MAX_OFFSET=10000
const MAX_OFFLINE_INDEX=preload("res://scripts/LocalPlaylists.gd").MAX_TRACKS-1
var path="user://music_ui_state.json"
var state={"version":VERSION,"source":"ma","origin":"","location":{},"offline_index":-1}
var blocked=false
var dirty=false
var last_error=""
func _integer(value,maximum):
    if not typeof(value) in [TYPE_INT,TYPE_REAL]:return -1
    if is_nan(float(value)) or is_inf(float(value)) or value<0 or value>maximum or float(int(value))!=float(value):return -1
    return int(value)
func _id(value):
    if typeof(value)!=TYPE_STRING or value.empty() or value.length()>64:return ""
    for digit in value:
        if digit<"0" or digit>"9":return ""
    return value
func identity(origin):
    if typeof(origin)!=TYPE_STRING or origin.length()>512:return ""
    var parsed=preload("res://scripts/ConnectionPolicy.gd").new().origin(origin,["http","https"],true)
    return origin.sha256_text() if not parsed.empty() and parsed.get("prefix")==origin else ""
func _digest(value):
    if typeof(value)!=TYPE_STRING or value.length()!=64:return false
    for digit in value:
        if not digit in "0123456789abcdef":return false
    return true
func _location(value):
    if typeof(value)!=TYPE_DICTIONARY or not value.get("kind") in ["tracks","albums","playlists","playlist_items"]:return {}
    var offset=_integer(value.get("offset"),MAX_OFFSET)
    var returned=_integer(value.get("return_offset",0),MAX_OFFSET)
    if offset<0 or returned<0 or offset%25!=0 or returned%25!=0:return {}
    var selected=_id(value.get("selected_id",""))
    var playlist=_id(value.get("playlist_id","")) if value.kind=="playlist_items" else ""
    if value.kind=="playlist_items" and playlist.empty():return {}
    return {"kind":value.kind,"offset":offset,"selected_id":selected,"playlist_id":playlist,"return_offset":returned,"collection_type":"album" if value.get("collection_type")=="album" else "playlist"}
func _read(filename):
    var file=File.new()
    if not file.file_exists(filename) or file.open(filename,File.READ)!=OK:return {}
    var size=file.get_len()
    if size<=0 or size>MAX_BYTES:
        file.close()
        return {}
    var text=file.get_as_text();file.close()
    text=text.strip_edges()
    if not text.begins_with("{") or not text.ends_with("}"):return {}
    var parsed=JSON.parse(text)
    if parsed.error!=OK or typeof(parsed.result)!=TYPE_DICTIONARY:return {}
    return parsed.result
func load_state():
    blocked=false;dirty=false;last_error=""
    state={"version":VERSION,"source":"ma","origin":"","location":{},"offline_index":-1}
    var value=_read(path)
    if value.empty():value=_read(path+".bak")
    if _future(value):
        blocked=true;last_error="Newer navigation settings were left untouched";return false
    if value.empty():return false
    if _integer(value.get("version"),100000)!=VERSION or not value.get("source") in ["ma","offline"]:return false
    state.source=value.source
    state.offline_index=_integer(value.get("offline_index"),MAX_OFFLINE_INDEX)
    var location=_location(value.get("location",{}))
    if _digest(value.get("origin")) and not location.empty():
        state.origin=value.origin;state.location=location
    return true
func source():return state.source
func offline_index():return int(state.offline_index)
func remember_offline(index):
    var valid=_integer(index,MAX_OFFLINE_INDEX)
    if valid<0:return false
    if state.offline_index!=valid:
        state.offline_index=valid
        dirty=true
    return true
func set_source(value):
    var normalized="offline" if value=="offline" else ("ma" if value in ["ma","catalog","preview"] else "")
    if normalized.empty():return false
    if state.source==normalized:return true
    state.source=normalized;dirty=true
    return save()
func location(origin):
    var fingerprint=identity(origin)
    return state.location.duplicate(true) if not fingerprint.empty() and fingerprint==state.origin else {}
func remember_location(origin,page,selection,return_offset=0):
    var fingerprint=identity(origin)
    if fingerprint.empty() or typeof(page)!=TYPE_DICTIONARY or typeof(selection)!=TYPE_DICTIONARY:return false
    if not page.get("kind") in ["tracks","albums","playlists","playlist_items"]:return false
    var playlist=page.get("playlist",{})
    if typeof(playlist)!=TYPE_DICTIONARY:return false
    var filtered=not str(page.get("search","")).empty()
    var value={"kind":page.kind,"offset":0 if filtered else page.get("offset",0),"selected_id":_id(selection.get("item_id","")) if selection.get("provider")=="library" and not filtered else "","playlist_id":_id(playlist.get("item_id","")) if playlist.get("provider")=="library" else "","return_offset":return_offset,"collection_type":"album" if playlist.get("media_type")=="album" else "playlist"}
    var clean=_location(value)
    if clean.empty():return false
    if state.origin==fingerprint and state.location==clean:return true
    state.origin=fingerprint;state.location=clean;dirty=true
    return true
func _rename(from,to):return Directory.new().rename(from,to)
func _future(value):
    if typeof(value)!=TYPE_DICTIONARY:return false
    var version=value.get("version",0)
    return typeof(version) in [TYPE_INT,TYPE_REAL] and not is_nan(float(version)) and not is_inf(float(version)) and version>VERSION
func save():
    if blocked:return false
    if _future(_read(path)):
        blocked=true
        last_error="Newer navigation settings were left untouched"
        return false
    if not dirty:return true
    var text=JSON.print(state)
    if text.to_utf8().size()>MAX_BYTES:return false
    var file=File.new()
    if file.open(path+".tmp",File.WRITE)!=OK:
        last_error="Navigation preferences could not be saved"
        return false
    file.store_string(text);file.close()
    var dir=Directory.new();var had_original=dir.file_exists(path)
    if had_original:
        if dir.file_exists(path+".bak") and dir.remove(path+".bak")!=OK:return false
        if _rename(path,path+".bak")!=OK:return false
    if _rename(path+".tmp",path)!=OK:
        if had_original:_rename(path+".bak",path)
        last_error="Previous navigation preferences were preserved";return false
    dirty=false;last_error=""
    return true
