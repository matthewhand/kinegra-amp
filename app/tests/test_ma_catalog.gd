extends SceneTree
var failures = []
var checks = 0
func check(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func _init():
    call_deferred("run")
func reply(adapter, value, context):
    adapter.request_node = HTTPRequest.new()
    adapter.add_child(adapter.request_node)
    adapter.request_context = context
    adapter._complete(HTTPRequest.RESULT_SUCCESS, 200, [], to_json(value).to_utf8(), adapter.epoch)
func run():
    var adapter = load("res://scripts/MACatalog.gd").new()
    get_root().add_child(adapter)
    check(not adapter.browse(), "empty setup does not request")
    check(not adapter.configure("http://10.77.0.1:8095", "synthetic-owner-token"), "cleartext bearer refused")
    check(adapter.token.empty(), "invalid setup retains no token")
    check(not adapter.configure("http://8.8.8.8:8095", "synthetic-owner-token", [], true),
          "public cleartext never permitted even with opt-in")
    check(adapter.configure("http://10.77.0.111:8095", "synthetic-owner-token", [], true),
          "trusted private MA HTTP requires explicit opt-in")
    check(adapter.endpoint == "http://10.77.0.111:8095", "trusted private MA endpoint honored")
    adapter.close()
    check(adapter.token.empty(), "closing clears trusted LAN token")
    check(adapter.configure("https://ma.example", "synthetic-owner-token", ["https://audio.example"]), "HTTPS setup")
    check(not adapter.browse("tracks", "", -1), "negative page refused")
    check(not adapter.browse("tracks", "", 10001), "large offset refused")
    var item = {"item_id": "12", "provider": "library", "name": "Synthetic", "media_type": "track", "uri": "library://track/12", "provider_mappings": [{"url": "private"}]}
    reply(adapter, [item], {"kind": "tracks", "offset": 0})
    check(adapter.current_page.get("items", []).size() == 1, "actual read completion populates page")
    check(not adapter.current_page["items"][0].has("uri") and not adapter.current_page["items"][0].has("provider_mappings"), "metadata summary excludes raw URLs")
    check(adapter.select_index(0) and adapter.request_node == null, "selection never requests playback")
    adapter.request_node = HTTPRequest.new()
    adapter.add_child(adapter.request_node)
    check(adapter.selection().empty() and not adapter.selected.empty(), "metadata request holds selection without deleting it")
    adapter.request_node.queue_free()
    adapter.request_node = null
    check(not adapter.selection().empty(), "selection returns after metadata refresh")
    adapter.selected_at = OS.get_ticks_msec() - 60001
    check(adapter.selection().empty(), "selection expires")
    adapter.select_index(0)
    adapter.cancel()
    check(adapter.selection().empty(), "cancel expires selections")
    var stale_epoch = adapter.epoch
    adapter.cancel()
    adapter.request_node = HTTPRequest.new()
    adapter.add_child(adapter.request_node)
    adapter._complete(HTTPRequest.RESULT_SUCCESS, 200, [], to_json([item]).to_utf8(), stale_epoch)
    check(adapter.current_page.empty(), "obsolete response cannot repopulate page")
    adapter.cancel()
    check(adapter.configure("https://ma.example", "synthetic-owner-token", ["https://audio.example"]), "reconfigure")
    var player = {"player_id": "synthetic-player", "name": "Synthetic", "current_media": {"uri": "library://track/12"}}
    reply(adapter, [player], {"kind": "players"})
    check(adapter.player_stream_candidate("synthetic-player").get("playable") == false, "library identifier not stream")
    player["current_media"]["uri"] = "https://audio.example/existing.mp3"
    reply(adapter, [player], {"kind": "players"})
    var candidate = adapter.player_stream_candidate("synthetic-player")
    check(candidate.get("requires_format_probe", false) and not candidate.get("playable", true), "existing server URI remains unverified")
    var output={"output_protocol_id":"local-client", "protocol_domain":"sendspin", "is_native":false, "priority":40, "available":true, "derived_from":null}
    var wrapper={"player_id":"up-fixture", "provider":"universal_player", "type":"player", "available":true, "enabled":true, "active_group":null, "synced_to":null, "group_members":[], "static_group_members":[], "active_output_protocol":null, "output_protocols":[output]}
    reply(adapter,[wrapper],{"kind":"players"})
    check(adapter.resolve_local_player("local-client")=="up-fixture", "exact direct sendspin wrapper maps to queue")
    check(adapter.resolve_local_player("other-client").empty(), "different identity never maps")
    var hidden_claim=wrapper.duplicate(true);hidden_claim.erase("player_id")
    reply(adapter,[wrapper,hidden_claim],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "malformed snapshot cannot hide another output owner")
    reply(adapter,[wrapper,wrapper.duplicate(true)],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "duplicate player IDs make discovery incomplete")
    var second=wrapper.duplicate(true);second["player_id"]="up-other"
    reply(adapter,[wrapper,second],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "ambiguous wrappers refused")
    var bad=wrapper.duplicate(true);bad["active_group"]="other-group"
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "group redirect refused")
    bad=wrapper.duplicate(true);bad["synced_to"]="other-player"
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "sync redirect refused")
    bad=wrapper.duplicate(true);bad["group_members"]=["other-player"]
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "group leader refused")
    bad=wrapper.duplicate(true);bad["active_output_protocol"]="different"
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "other active output refused")
    bad=wrapper.duplicate(true);bad["output_protocols"].append({"output_protocol_id":"other", "available":true})
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "multi-output wrapper refused")
    bad=wrapper.duplicate(true);bad["output_protocols"][0]["derived_from"]="other"
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "derived output refused")
    bad=wrapper.duplicate(true);bad.erase("active_group")
    reply(adapter,[bad],{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "unknown group state refused")
    reply(adapter,[wrapper],{"kind":"players"})
    adapter.players_at=OS.get_ticks_msec()-10001
    check(adapter.resolve_local_player("local-client").empty(), "old routing snapshot refused")
    var oversized=[]
    for _i in range(101): oversized.append(wrapper)
    reply(adapter,oversized,{"kind":"players"})
    check(adapter.resolve_local_player("local-client").empty(), "truncated routing snapshot refused")
    adapter.request_node = HTTPRequest.new()
    adapter.add_child(adapter.request_node)
    adapter._complete(HTTPRequest.RESULT_SUCCESS, 401, [], PoolByteArray(), adapter.epoch)
    check(adapter.token.empty() and adapter.state == "auth_expired", "401 clears token")
    adapter.close()
    var panel = load("res://scripts/MASetupPanel.gd").new()
    get_root().add_child(panel)
    check(panel.token_edit.secret and panel.token_edit.text.empty(), "masked empty token UI")
    check(panel.confirm_button.disabled, "no selected item at startup")
    panel.endpoint_edit.text = "http://10.77.0.1"
    panel.token_edit.text = "synthetic-token"
    panel._connect_catalog()
    check(panel.token_edit.text.empty() and panel.catalog.token.empty(), "bad UI connection clears typed token")
    panel._close()
    check(panel.catalog.token.empty(), "disconnect clears token")
    adapter.queue_free()
    panel.queue_free()
    print("MA_GODOT_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
