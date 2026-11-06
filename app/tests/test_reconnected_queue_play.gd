extends SceneTree
class Client:
    extends Reference
    var streaming=false
    func status():return {"active":streaming,"paired":true,"client_id":"synthetic-client"}
class Facade:
    extends Reference
    var client=Client.new()
class Request:
    extends "res://scripts/MATvQueueRequest.gd"
    var sent=[]
    func _owner_is_current():return true
    func _send_mutation(command,value=null):sent.append(command)
var failures=[]
var checks=0
func check(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
    var request=Request.new()
    get_root().add_child(request)
    request.session=Facade.new()
    request.active=true
    request.action="play"
    request._on_snapshot({"item_count":3})
    check(request.sent==["resume"],"reconnected player restarts saved stream with Resume")
    request.sent.clear()
    request.session.client.streaming=true
    request._on_snapshot({"item_count":3})
    check(request.sent==["play"],"existing stream uses normal unpause")
    request.sent.clear()
    request._on_snapshot({"item_count":0})
    check(request.sent.empty() and request.failure_reason=="queue_empty","empty queue does not send a playback mutation")
    request.free()
    print("RECONNECTED_QUEUE_PLAY_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
