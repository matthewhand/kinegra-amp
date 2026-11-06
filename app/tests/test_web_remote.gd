extends SceneTree
var remote=null
var requests=[]
var checks=0
var failures=[]
func check(ok,name):
    checks+=1
    if not ok:
        failures.append(name)
        printerr("FAIL ",name)
func _init():call_deferred("run")
func run():
    var Remote=load("res://scripts/WebRemote.gd")
    check(Remote.default_enabled(true) and not Remote.default_enabled(false),"explicit development-on production-off defaults")
    check(Remote.development_build(true,false) and not Remote.development_build(false,false) and not Remote.development_build(true,true),"production tag wins over debug template")
    remote=Remote.new()
    remote.settings_path="user://web_remote_test.cfg"
    get_root().add_child(remote)
    remote.configure(self,false)
    check(not remote.server.is_listening() and remote.key.empty(),"fresh production has no listener or key")
    remote.configure(self,true)
    check(remote.server.is_listening() and remote.key.length()==16,"fresh development starts authenticated remote")
    check(remote.set_enabled(false) and not remote.server.is_listening(),"disable closes service")
    remote.configure(self,true)
    check(not remote.server.is_listening(),"development opt-out persists")
    remote.configure(self,false)
    check(not remote.server.is_listening(),"development preference does not enable production")
    check(remote.set_enabled(true),"production opt-in starts listener")
    var previous=remote.key
    remote.rotate_key()
    check(remote.key!=previous and remote.key.length()==16,"key rotation revokes old key")
    remote.configure(self,false)
    check(remote.server.is_listening(),"production opt-in persists")
    remote._stop()
    remote.settings_path="user://corrupt_web_remote.cfg"
    var file=File.new()
    file.open(remote.settings_path,File.WRITE)
    file.store_string("not a config file = [[[")
    file.close()
    remote.configure(self,true)
    check(not remote.server.is_listening() and remote.key.empty(),"corrupt development preferences fail closed")
    remote.settings_path="user://socket_web_remote.cfg"
    remote.configure(self,false)
    check(not remote.server.is_listening(),"second fresh production profile stays off")
    remote.set_enabled(true)
    check(remote._private_ipv4("192.168.1.20") and remote._private_ipv4("172.16.4.3") and remote._private_ipv4("127.0.0.1"),"LAN and loopback accepted")
    check(not remote._private_ipv4("8.8.8.8") and not remote._private_ipv4("172.32.4.3") and not remote._private_ipv4("192.168.1.999") and not remote._private_ipv4("::1"),"public malformed and unsupported IPv6 rejected")
    print("WEB_REMOTE_READY ",remote.key)
    create_timer(40).connect("timeout",self,"timeout")
func web_remote_snapshot():return {"title":"Synthetic remote track", "source":"Synthetic fixture", "state":"paused"}
func web_remote_control(action):
    requests.append(action)
    if action=="stop":call_deferred("finish")
    return true
func finish():
    # Wait until the final bounded response is sent before shutting down.
    yield(create_timer(.3),"timeout")
    check(requests==["play","pause","previous","next","stop"],"only authorized supported actions reach the player in order")
    remote._stop()
    print("WEB_REMOTE_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
func timeout():
    printerr("FAIL remote fixture deadline")
    quit(1)
