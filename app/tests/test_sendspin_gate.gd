extends SceneTree
var failures=[]
func check(ok,label):
    print("SENDSPIN_GATE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
class Fake:
    extends Reference
    var opens=0
    var closes=0
    func open(_endpoint,_vault):
        opens+=1
        return true
    func close(): closes+=1
    func tick(): return true
    func status(): return {"active":false,"generation":0,"paired":false}
func _init(): call_deferred("run")
func run():
    var facade=load("res://scripts/SendspinExperienceFacade.gd").new()
    get_root().add_child(facade)
    var backend=Fake.new()
    var vault=Reference.new()
    check(not facade.begin_dependencies(false,"ws://10.1.2.3:8927/sendspin",true,backend,vault),"disabled_is_inert")
    check(not facade.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin",false,backend,vault),"private_network_requires_trust")
    check(not facade.begin_dependencies(true,"ws://8.8.8.8:8927/sendspin",true,backend,vault),"public_cleartext_rejected")
    check(not facade.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin?x=1",true,backend,vault),"query_rejected")
    check(not facade.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin",true,backend,null),"vault_required")
    check(backend.opens==0,"invalid_never_connects")
    check(facade.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin",true,backend,vault),"explicit_opt_in")
    check(not facade.begin_dependencies(true,"ws://10.1.2.3:8927/sendspin",true,backend,vault),"no_duplicate_session")
    facade.stop()
    check(backend.opens==1 and backend.closes==1,"stop_closes_once")
    facade.queue_free()
    print("SENDSPIN_GATE_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
