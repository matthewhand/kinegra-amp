extends Reference
# Supported Music Assistant preview contract, NOT a complete track stream.
# MA's official client constructs /preview?path=<double-quoted id>&provider=<provider>.
# No queue commands, guessed full-track endpoints, token in URL, or auto playback.
var policy = preload("res://scripts/ConnectionPolicy.gd").new()

func _item_part(value):
    if typeof(value) != TYPE_STRING or value.empty() or value.length() > 200:
        return false
    for i in range(value.length()):
        var code = value.ord_at(i)
        if code < 32 or code > 126:
            return false
    return true

func prepare(item, endpoint, trust_private):
    if typeof(item) != TYPE_DICTIONARY or item.get("media_type") != "track" or item.get("available", true) != true:
        return {}
    var track_id = item.get("item_id")
    var provider = item.get("provider")
    if not _item_part(track_id) or not _item_part(provider):
        return {}
    var parsed = policy.origin(endpoint, ["https", "http"], trust_private)
    if parsed.empty() or parsed["prefix"] != endpoint:
        return {}
    # Client double-encodes the id for server-side preview source lookup.
    var path = track_id.percent_encode().percent_encode()
    var provider_query = provider.percent_encode()
    # No untrusted URLs, query suffixes, absolute redirects, or credentials.
    var url = endpoint + "/preview?path=" + path + "&provider=" + provider_query
    if url.length() > 1900 or "@" in url or "#" in url:
        return {}
    return {
        "contract": "methexis.ma-preview.v1",
        "origin": endpoint,
        "url": url,
        "codec": 1,
        "track_name": str(item.get("name", "MA track")).substr(0, 100),
        "preview_only": true
    }
