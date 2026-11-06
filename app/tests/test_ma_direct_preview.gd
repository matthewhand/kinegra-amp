extends SceneTree
# Synthetic IDs and tokens only; no network or sound. Assert no URL injection.
var checks = 0
var failures = []
class MockPreviewReply:
    extends Reference
    var headers = []
    var code = 200
    var body_length = 123
    func get_response_code():
        return code
    func get_response_headers():
        return headers
    func get_response_body_length():
        return body_length
    func close():
        pass
func check(ok, name):
    checks += 1
    if not ok:
        failures.append(name)
        printerr("FAIL ", name)
func _init():
    call_deferred("run")
func run():
    var route = load("res://scripts/MAPreviewRoute.gd").new()
    var item = {"item_id":"track 42", "provider":"filesystem--x", "media_type":"track", "name":"Fiction", "available":true}
    var good = route.prepare(item, "https://ma.example", false)
    check(good.get("preview_only") == true, "clear preview-only contract")
    check(good.get("codec") == 1, "MP3 decoder selected")
    check(good.get("url") == "https://ma.example/preview?path=track%252042&provider=filesystem--x", "official double-encoding")
    check(not good.has("token") and not good.has("authorization"), "no credentials in route")
    check(route.prepare(item, "http://10.77.0.111:8095", false).empty(), "cleartext must opt in")
    check(not route.prepare(item, "http://10.77.0.111:8095", true).empty(), "explicit trusted private LAN permitted")
    check(route.prepare(item, "http://8.8.8.8:8095", true).empty(), "public HTTP refused")
    check(route.prepare(item, "https://ma.example/path", false).empty(), "origin cannot include route")
    check(route.prepare(item, "https://user:pass@ma.example", false).empty(), "URL embedded credentials refused")
    for kind in ["playlist", "album", "radio", "unknown"]:
        item["media_type"] = kind
        check(route.prepare(item, "https://ma.example", false).empty(), "reject nontrack " + kind)
    item["media_type"] = "track"
    item["available"] = false
    check(route.prepare(item, "https://ma.example", false).empty(), "unavailable track rejected")
    item["available"] = true
    for id in ["", "bad\nid", "tab\tid", "long" + "x".repeat(201)]:
        item["item_id"] = id
        check(route.prepare(item, "https://ma.example", false).empty(), "invalid item ID rejected")
    item["item_id"] = "../me?token=unsafe"
    good = route.prepare(item, "https://ma.example", false)
    check(not good.empty() and not "../" in good["url"] and not "token=" in good["url"], "URL percent escapes original ID")
    var decoder = load("res://scripts/NativeDecoderPlayer.gd").new()
    get_root().add_child(decoder)
    var t = load("res://scripts/NativeHTTPTransport.gd").new()
    get_root().add_child(t)
    t.configure(decoder, "https://ma.example", false)
    check(not t.start_authorized_preview("https://ma.example/preview?path=ok&provider=library", "bad"), "short bearer rejected")
    check(t.ma_preview_token.empty() and not t.active, "invalid token never kept")
    check(not t.start_authorized_preview("https://ma.example/preview?path=ok&provider=library", "bad\nbearer-with-chars"), "header injection rejected")
    check(t.ma_preview_token.empty(), "header injection never retained")
    check(not t._valid_preview_path("/preview?path=good&provider=x&secret=bad"), "no additional query field")
    check(not t._valid_preview_path("/preview?path=x&provider=x%0d%0a"), "reject unsafe control-derived path")
    check(t._valid_preview_path("/preview?path=track%252042&provider=filesystem--x"), "official path accepted")
    check(not t._valid_preview_path("//preview?path=a&provider=b"), "reject ambiguous double slash")
    check(not t._valid_preview_path("/preview?path=x#fragment&provider=a"), "fragment rejected")
    check(not t._valid_preview_path("/preview?path=x&provider=abc@else"), "userinfo rejected")
    t.ma_preview_token = "fictional-bearer"
    t.ma_preview_mode = true
    t.stop()
    check(t.ma_preview_token.empty() and not t.ma_preview_mode, "Stop clears bearer")
    # No network: fictional response headers exercise real MIME/code/body gates.
    var mock = MockPreviewReply.new()
    mock.headers = ["Content-Type: audio/mpeg; charset=binary"]
    mock.code = 200
    mock.body_length = 1234
    t.client = mock
    t.ma_preview_mode = true
    check(t._response_ok() and t.response_checked, "only 200 MP3 preview accepted")
    t.stop()
    mock = MockPreviewReply.new()
    mock.headers = ["Content-Type: application/json"]
    t.client = mock
    t.ma_preview_mode = true
    t.ma_preview_token = "fictional-bearer"
    check(not t._response_ok() and not t.active and t.ma_preview_token.empty(), "JSON/error page aborts and clears credentials")
    mock = MockPreviewReply.new()
    mock.code = 302
    mock.headers = ["Content-Type: audio/mpeg"]
    t.client = mock
    t.ma_preview_mode = true
    check(not t._response_ok(), "never follow preview redirects")
    mock = MockPreviewReply.new()
    mock.headers = ["Content-Type: audio/mpeg"]
    mock.body_length = t.PREVIEW_MAX_BYTES + 1
    t.client = mock
    t.ma_preview_mode = true
    check(not t._response_ok(), "oversized MA preview refused")
    t.ma_preview_token = "fictional-bearer"
    t._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(t.ma_preview_token.empty(), "background clears bearer")
    t.queue_free()
    decoder.queue_free()
    print("MA_DIRECT_PREVIEW_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
