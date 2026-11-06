extends Node
# Explicitly gated experimental bridge. Not an autoload and no default UI.
# `ws` on a private IPv4 is allowed only after the owner opts into LAN trust.
# Sendspin Noise protects the stream; WSS support is not yet verified here.
var runtime=null
var sink=null
var client=null
var policy=preload("res://scripts/ConnectionPolicy.gd").new()
func _valid_endpoint(endpoint,trust_private):
    if typeof(endpoint)!=TYPE_STRING or not endpoint.ends_with("/sendspin"):
        return false
    var origin=endpoint.substr(0,endpoint.length()-"/sendspin".length())
    var parsed=policy.origin(origin,["ws"],trust_private)
    return not parsed.empty() and parsed["prefix"]==origin
func start_experimental(enabled,endpoint,trust_private):
    if enabled!=true or OS.get_name()!="Android" or not _valid_endpoint(endpoint,trust_private):
        return false
    if not Engine.has_singleton("ShieldAmpTokenStore") or not ResourceLoader.exists("res://native/ShieldSendspin.gdns"):
        return false
    var script=load("res://native/ShieldSendspin.gdns")
    if script==null: return false
    var backend=script.new()
    var vault=preload("res://scripts/AndroidSendspinVaultAdapter.gd").new()
    if not vault.bind(Engine.get_singleton("ShieldAmpTokenStore")): return false
    return begin_dependencies(enabled,endpoint,trust_private,backend,vault)
func begin_dependencies(enabled,endpoint,trust_private,backend,vault):
    if enabled!=true or not _valid_endpoint(endpoint,trust_private) or backend==null or vault==null or runtime!=null:
        return false
    sink=load("res://scripts/SendspinPcmOutput.gd").new()
    add_child(sink)
    runtime=load("res://scripts/SendspinPlaybackRuntime.gd").new()
    add_child(runtime)
    client=backend
    if not runtime.begin(client,sink,vault,endpoint):
        stop()
        return false
    return true
# A pairing token grants access like a password. Call only after the owner
# explicitly asks to reveal it; never log or persist the returned string.
func reveal_pairing_token():
    return client.reveal_pairing_token() if client!=null else ""
func pairing_code():
    return client.pairing_code() if client!=null else ""
func confirm_pairing():
    return runtime.confirm_pairing() if runtime!=null else false
func command(name,position=-1):
    return runtime.command(name,position) if runtime!=null else false
func stop():
    if runtime!=null:
        runtime.stop()
        runtime.queue_free()
    if sink!=null: sink.queue_free()
    runtime=null
    sink=null
    client=null
func _exit_tree():
    stop()
