extends SceneTree
var failures = []
var checks = 0
func check(ok, label):
    checks += 1
    if not ok:
        failures.append(label)
        printerr("FAIL ", label)
func _init():
    var policy = load("res://scripts/ConnectionPolicy.gd").new()
    check(not policy.origin("https://music.example:443", ["https"]).empty(), "HTTPS")
    check(not policy.origin("wss://ha.example", ["wss"]).empty(), "WSS")
    for url in ["https://user:token@host", "https://host/a", "https://host?token=secret", "https://host#fragment", "https://host:0", "https://host:65536", "https://host\r\nX:1", "http://10.77.0.1"]:
        check(policy.origin(url, ["http", "https"]).empty(), "unsafe origin")
    for url in ["http://10.77.0.1:8097", "http://127.0.0.1:18097", "ws://192.168.1.5:8123", "http://172.16.0.1"]:
        check(not policy.origin(url, ["http", "ws"], true).empty(), "trusted private transport")
    for url in ["http://8.8.8.8", "http://public.example", "http://172.32.0.1", "http://10.77.0.1.evil", "http://10.77.0.1//"]:
        check(policy.origin(url, ["http"], true).empty(), "untrusted cleartext")
    print("POLICY_CHECKS=", checks, " FAILURES=", failures)
    quit(0 if failures.empty() else 1)
