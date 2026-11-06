extends SceneTree
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    func status(): return {"active":OS.get_environment("TVQ_MODE")!="resume-play","paired":true,"client_id":"synthetic-client"}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
class Host:
    extends Node
    var sendspin_facade=null
var done=false
func _init(): call_deferred("run")
func on_complete(ok,action,snapshot,detail):
    done=true
    print("FIXTURE_DETAIL=",detail)
    print("FIXTURE_OK=",ok)
    print("FIXTURE_ACTION=",action)
    print("FIXTURE_CURRENT=",snapshot.get("current",""))
func run():
    var host=Host.new();get_root().add_child(host)
    var facade=Facade.new();host.sendspin_facade=facade
    var req=load("res://scripts/MATvQueueRequest.gd").new();host.add_child(req)
    req.connect("completed",self,"on_complete")
    var mode=OS.get_environment("TVQ_MODE")
    var action="items" if mode in ["items","raw-items","items-wrong","items-too-many"] else ("read" if mode in ["read","raw-read","wrong-queue"] else ("play" if mode in ["play","resume-play","raw-play","empty-play","bad-count-play"] else "pause"))
    if not req.begin(host,facade,OS.get_environment("TVQ_URL"),"synthetic-credential",true,action):
        print("FIXTURE_START_FAILED");quit(1);return
    if mode in ["owner-change","owner-after-send"]:
        yield(create_timer(.05 if mode=="owner-change" else .25),"timeout")
        host.sendspin_facade=Facade.new()
    for _i in range(480):
        if done: break
        yield(create_timer(.025),"timeout")
    if not done: print("FIXTURE_TIMEOUT")
    var released=not req.active and req.catalog==null and req.client_id.empty()
    print("FIXTURE_CREDENTIAL_RELEASED=",released)
    req.cancel();host.queue_free();quit(0 if done and released else 1)
