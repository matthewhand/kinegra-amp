extends Reference
# Empty legacy catalog; user imports and Music Assistant own their metadata.
# Not provider metadata. Browsing never starts playback or queries MA.
const TRACKS = []
const ARTISTS = []
const ALBUMS = []
const PAGE_SIZE = 8

func browse(kind, query="", offset=0):
    if not kind in ["albums", "artists", "tracks"] or typeof(query) != TYPE_STRING or query.length() > 100 or typeof(offset) != TYPE_INT or offset < 0 or offset > 10000:
        return {"ok": false, "items": [], "total": 0, "has_more": false}
    var items = []
    for i in range(TRACKS.size()):
        var row = {"track_index": i, "title": TRACKS[i], "artist": ARTISTS[i], "album": ALBUMS[i], "fictional": true}
        var name = row["title"] if kind == "tracks" else row["album"] if kind == "albums" else row["artist"]
        if not query.empty() and name.to_lower().find(query.strip_edges().to_lower()) < 0:
            continue
        var exists = false
        if kind != "tracks":
            for earlier in items:
                if earlier["name"] == name:
                    exists = true
                    break
        if not exists:
            items.append({"name": name, "fictional": true, "track_index": i, "type": kind})
    var page = []
    for i in range(offset, min(offset + PAGE_SIZE, items.size())):
        page.append(items[i].duplicate(true))
    return {"ok": true, "items": page, "total": items.size(), "has_more": offset + page.size() < items.size(), "kind": kind, "offset": offset}
