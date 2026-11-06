extends Node
# Runs only inside the disposable local.shieldamp.tokenproof package.
# Never reads the real Kinegra Amp package or any real account credentials.
var checks = []
func check(name, passed):
    checks.append({"name":name,"passed":passed})
func _ready():
    var available = OS.get_name()=="Android" and Engine.has_singleton("ShieldAmpTokenStore")
    check("singleton_registered",available)
    if available:
        var vault=Engine.get_singleton("ShieldAmpTokenStore")
        var bridge=preload("res://AndroidSendspinVaultAdapter.gd").new()
        check("adapter_bound",bridge.bind(vault))
        var bytes=PoolByteArray()
        for i in range(4096): bytes.append(i%256)
        check("snapshot_jni_write",bridge.replaceSendspinSnapshot(bytes))
        var loaded=bridge.loadSendspinSnapshot()
        check("snapshot_jni_type",typeof(loaded)==TYPE_RAW_ARRAY)
        check("snapshot_jni_exact_readback",loaded==bytes)
        check("snapshot_secure_status",bridge.sendspinSnapshotStatus()=="secure")
        check("reject_invalid_encoding",not vault.replaceSendspinSnapshotBase64("!?%%"))
        check("reject_empty_snapshot",not vault.replaceSendspinSnapshotBase64(""))
        check("reject_oversize_snapshot",not vault.replaceSendspinSnapshotBase64("A".repeat(5468)))
        check("previous_snapshot_preserved",bridge.loadSendspinSnapshot()==bytes)
        var token="shieldamp-synthetic-proof-not-a-credential"
        check("synthetic_token_write",vault.storeToken(token))
        check("staged_token_readback",vault.loadTokenStaged()==token)
        check("token_status",vault.storageStatus()=="secure")
    var success=true
    for c in checks:
        if not c.passed: success=false
    var result=File.new()
    if result.open("user://synthetic-jni-result.json",File.WRITE)==OK:
        result.store_string(JSON.print({"passed":success,"checks":checks}))
        result.close()
    get_tree().quit(0 if success else 1)
