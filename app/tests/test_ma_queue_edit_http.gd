extends SceneTree
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    var id="own-client"
    func status():return {"paired":true,"client_id":id}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
class Host:
    extends Node
    var sendspin_facade=null
var done=false
var final_ok=false
var detail=""
func _init():call_deferred("run")
func complete(ok,_action,_snapshot,message):
    done=true;final_ok=ok;detail=message
func run():
    var host=Host.new();get_root().add_child(host)
    var facade=Facade.new();host.sendspin_facade=facade
    var request=load("res://scripts/MATvQueueRequest.gd").new();host.add_child(request)
    request.connect("completed",self,"complete")
    var mode=OS.get_environment("EDIT_MODE")
    var action="seek_backward" if mode=="seek-backward" else ("clear" if mode.begins_with("clear") else ("remove" if mode.begins_with("remove") or mode=="owner-change-remove" else "seek_forward"))
    var item="future-2" if not mode in ["remove-current","remove-buffered","remove-missing"] else ("current" if mode=="remove-current" else ("buffered" if mode=="remove-buffered" else "missing"))
    if not request.begin(host,facade,OS.get_environment("EDIT_URL"),"synthetic-credential",true,action,item):
        print("EDIT_BEGIN_FAILED")
        quit(1)
        return
    if mode=="owner-change-remove":
        yield(create_timer(.1),"timeout")
        facade.client.id="changed-client"
    for _i in range(480):
        if done:break
        yield(create_timer(.025),"timeout")
    yield(create_timer(.15),"timeout")
    print("EDIT_OK=",final_ok)
    print("EDIT_DETAIL=",detail)
    print("EDIT_RELEASED=",not request.active and request.catalog==null and request.client_id.empty() and request.argument==null and request.queue_snapshot.empty())
    request.cancel();host.queue_free();quit(0 if done else 1)
