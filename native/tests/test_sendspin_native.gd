extends SceneTree
var failed=false
class Vault:
    extends Reference
    var blob=PoolByteArray()
    var status="missing"
    var fail_write=false
    func loadSendspinSnapshot(): return blob
    func sendspinSnapshotStatus(): return status
    func replaceSendspinSnapshot(value):
        if fail_write: return false
        blob=value
        status="secure"
        return true
func check(v,s):
    print("NATIVE_GODOT_"+("PASS_" if v else "FAIL_")+s)
    if not v: failed=true
func _init(): call_deferred("run")
func run():
    var plugin=load("res://ShieldSendspin.gdns").new()
    check(not plugin.open("https://invalid/"),"rejects_wrong_scheme")
    check(not plugin.open("ws://user@127.0.0.1:9/sendspin"),"rejects_credentials")
    var st=plugin.status()
    check(not st.active and not st.paired and st.generation>=0,"initial_status")
    check(not plugin.acknowledge_generation(0),"unpaired_ack_rejected")
    check(not plugin.command("play") and not plugin.command("seek",1),"unpaired_controls_rejected")
    check(plugin.read(8).bytes.empty(),"unpaired_no_pcm")
    var url=OS.get_environment("SHIELDAMP_TEST_URL")
    check(url.begins_with("ws://127.0.0.1:"),"fixture_only_loopback")
    var marker=File.new()
    check(marker.open(OS.get_environment("SHIELDAMP_TEST_PID"),File.WRITE)==OK,"pid_marker")
    marker.store_string(str(OS.get_process_id()))
    marker.close()
    var bad=Vault.new()
    bad.blob=PoolByteArray([1,2,3]); bad.status="secure"
    check(not plugin.open(url,bad) and bad.blob==PoolByteArray([1,2,3]),"corrupt_vault_no_overwrite")
    var partial=Vault.new()
    partial.status="secure"
    partial.blob=PoolByteArray([83,83,86,49,1,7])
    partial.blob.append_array("keypair".to_utf8())
    partial.blob.append(32)
    for _i in range(32): partial.blob.append(42)
    var prior_partial=PoolByteArray(partial.blob)
    check(not plugin.open(url,partial) and partial.blob==prior_partial,"incomplete_identity_never_overwritten")
    var broken=Vault.new()
    broken.status="error"
    check(not plugin.open(url,broken),"vault_error_fails_closed")
    var vault=Vault.new()
    check(plugin.open(url,vault),"explicit_start")
    var original_id=plugin.status().client_id
    check(plugin.status().persistent and vault.status=="secure" and not original_id.empty(),"identity_persisted_to_vault")
    var token=plugin.reveal_pairing_token()
    check(token.begins_with("SP:") and token.length()>20,"explicit_pairing_token_available")
    token=""
    check(not plugin.open(url),"duplicate_start_rejected")
    for _i in range(12):
        check(plugin.tick(),"sdk_loop")
        yield(create_timer(0.05),"timeout")
    check(not plugin.status().paired and plugin.read(8).bytes.empty(),"no_pcm_without_pairing")
    check(plugin.close(),"close")
    check(not plugin.status().active and not plugin.tick() and plugin.reveal_pairing_token().empty(),"close_clears_session")
    check(plugin.open(url,vault),"restart_with_vault")
    check(plugin.status().client_id==original_id,"identity_survives_restart")
    plugin.close()
    var unwritable=Vault.new()
    unwritable.fail_write=true
    check(not plugin.open(url,unwritable) and unwritable.status=="missing","write_failure_fails_closed")
    print("NATIVE_GODOT_FAILURE=",failed)
    quit(1 if failed else 0)
