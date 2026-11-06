extends Reference
# RAM-only context from successful app queue additions, never from mere browsing.
const MAX_TRACKS=2048
var tracks={}
static func library_id(value):
    if typeof(value)!=TYPE_STRING or value.empty() or value.length()>20:return ""
    for i in range(value.length()):
        if not value.substr(i,1) in "0123456789":return ""
    return value
static func media_id(media):
    if typeof(media)!=TYPE_DICTIONARY:return ""
    if media.get("provider")=="library":return library_id(str(media.get("item_id","")))
    var uri=media.get("uri","")
    return library_id(uri.substr(16)) if typeof(uri)==TYPE_STRING and uri.begins_with("library://track/") else ""
func remember(name,ids):
    if typeof(name)!=TYPE_STRING or name.strip_edges().empty() or name.length()>100 or typeof(ids)!=TYPE_ARRAY or ids.size()>2000:return false
    for i in range(name.length()):
        if name.ord_at(i)<32:return false
    for value in ids:
        var id=library_id(value)
        if id.empty():return false
    for id in ids:
        # Conflicting contexts are unknown; never relabel a current track from
        # a later selection or claim one arbitrary origin for a mixed queue.
        if tracks.has(id) and tracks[id]!=name:tracks[id]=""
        elif not tracks.has(id) and tracks.size()<MAX_TRACKS:tracks[id]=name
    return true
func playlist(id):
    return str(tracks.get(library_id(id),""))
func clear():tracks.clear()
static func label(album,playlist_name):
    if typeof(album)==TYPE_STRING and not album.strip_edges().empty():return "ALBUM: "+album
    if typeof(playlist_name)==TYPE_STRING and not playlist_name.strip_edges().empty():return "PLAYLIST: "+playlist_name
    return ""
