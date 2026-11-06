extends SceneTree
class Plugin:
    extends Reference
    var text=""
    var status="missing"
    var reject=false
    func loadSendspinSnapshotBase64(): return text
    func sendspinSnapshotStatus(): return status
    func replaceSendspinSnapshotBase64(value):
        if reject: return false
        text=value; status="secure"; return true
var count=0
var failed=false
func check(value):
    count+=1
    if not value:
        printerr("ADAPTER_CHECK_FAILED_",count)
        failed=true
func _init(): call_deferred("run")
func run():
    var bridge=load("res://AndroidSendspinVaultAdapter.gd").new()
    check(not bridge.bind(null))
    var plugin=Plugin.new()
    check(bridge.bind(plugin))
    check(bridge.loadSendspinSnapshot().empty() and bridge.sendspinSnapshotStatus()=="missing")
    var bytes=PoolByteArray()
    for i in range(4096): bytes.append(i%256)
    check(bridge.replaceSendspinSnapshot(bytes))
    check(bridge.loadSendspinSnapshot()==bytes)
    check(bridge.sendspinSnapshotStatus()=="secure")
    var oversized=bytes; oversized.append(1)
    check(not bridge.replaceSendspinSnapshot(oversized))
    check(not bridge.replaceSendspinSnapshot(PoolByteArray()))
    check(not bridge.replaceSendspinSnapshot("bad type"))
    plugin.reject=true
    check(not bridge.replaceSendspinSnapshot(bytes))
    plugin.text="AQ==\n"
    check(bridge.loadSendspinSnapshot().empty() and bridge.sendspinSnapshotStatus()=="error")
    plugin.text="AAAA";plugin.status="missing"
    check(bridge.loadSendspinSnapshot().empty() and bridge.sendspinSnapshotStatus()=="error")
    plugin.text="";plugin.status="secure"
    check(bridge.loadSendspinSnapshot().empty() and bridge.sendspinSnapshotStatus()=="error")
    plugin.text="A".repeat(5468)
    check(bridge.loadSendspinSnapshot().empty() and bridge.sendspinSnapshotStatus()=="error")
    print("ANDROID_VAULT_ADAPTER_CHECKS=",count)
    quit(1 if failed else 0)
