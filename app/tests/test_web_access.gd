extends SceneTree
var ma_panel=null
var offline_save=preload("res://scripts/OfflineQueueSave.gd").new()
var offline_music=preload("res://scripts/OfflineMusic.gd").new()
var count=0
var failures=[]
func check(ok,label):
    count+=1
    if not ok:
        failures.append(label)
        printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
    var policy=load("res://scripts/LanAccessPolicy.gd").new()
    for value in ["10.42.0.0/8","172.16.0.0/12","192.168.0.0/16","127.0.0.1/32","169.254.0.0/16","10.1.2.3-10.1.2.8","10.1.2.3", "10.1.2.3, 192.168.1.2"]:
        check(policy.parse(value).ok,"valid "+value)
    for value in ["", "0.0.0.0/0","10.42.0.0/7","8.8.8.8","172.32.0.1","10.42.0.1-11.0.0.1","10.1.2.8-10.1.2.3","10.42.0.1//24","10.42.0.1--10.42.0.2","10.42.0.1/33","10.42.0.1/-1","10.42.0.256","10.00.0.1","10.0.1","::1","10.42.0.1/","/24"]:
        check(not policy.parse(value).ok,"reject "+value)
    var parsed=policy.parse("10.42.0.0/24, 192.168.1.20-192.168.1.30")
    check(policy.allows("10.42.0.255",parsed.ranges) and policy.allows("192.168.1.20",parsed.ranges),"inclusive boundaries")
    check(not policy.allows("10.0.1.0",parsed.ranges) and not policy.allows("192.168.1.31",parsed.ranges),"outside boundaries")
    check(not policy.parse(PoolStringArray(["10.42.0.1","10.42.0.2","10.42.0.3","10.42.0.4","10.42.0.5","10.42.0.6","10.42.0.7","10.42.0.8","10.1.0.9"]).join(",")).ok,"range count bounded")
    var remote=load("res://scripts/WebRemote.gd").new()
    remote.settings_path="user://access-test.cfg"
    get_root().add_child(remote)
    remote.configure(self,false)
    check(remote.require_key and not remote.server.is_listening(),"production starts off with key required")
    check(remote.set_access(false,"127.0.0.1/32") and not remote.require_key,"explicit trusted no-key setting")
    remote.configure(self,false)
    check(not remote.require_key and not remote.server.is_listening(),"saved policy does not enable listener")
    remote.configure(self,true)
    check(remote.require_key,"development policy isolated from production")
    remote._stop()
    check(not remote.set_access(false,"0.0.0.0/0") and remote.require_key,"invalid policy leaves prior policy")
    remote.configure(self,false)
    var mode=OS.get_environment("SHIELDAMP_TEST_ACCESS")
    if mode=="restricted":remote.set_access(false,"10.42.0.0/8")
    elif mode=="no_key":remote.set_access(false,"127.0.0.1/32")
    else:remote.set_access(true,"127.0.0.1/32")
    check(remote.set_enabled(true),"explicit listener enable")
    print("WEB_ACCESS_READY ",mode," ",remote.key," CHECKS=",count," FAILURES=",failures.size())
    if not failures.empty():
        quit(1)
        return
    create_timer(25).connect("timeout",self,"done")
func web_remote_snapshot():return {"title":"Synthetic access test","state":"idle"}
func web_remote_diagnostics():return {"connection":"idle"}
func web_remote_control(_action):return true
func done():quit()
