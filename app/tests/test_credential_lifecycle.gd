extends SceneTree
var failures=[]
var closed=[]
var forgot=0
class FakeVault:
    extends Reference
    var bound="https://one.invalid"
    var state="secure_no_legacy"
    var value="synthetic-access-token"
    var loads=0
    var writes=0
    var erasures=0
    var fail_save=false
    var fail_forget=false
    var pairing="preserve-pairing"
    func tokenEndpoint(): return bound
    func storageStatus(): return state
    func loadTokenForEndpoint(endpoint):
        loads+=1
        if endpoint!=bound:
            state="endpoint_mismatch"
            return ""
        return value if state in ["secure_no_legacy","migrated_no_legacy"] else ""
    func storeTokenForEndpoint(token,endpoint):
        writes+=1
        if fail_save:return false
        value=token
        bound=endpoint
        state="secure_no_legacy"
        return true
    func forgetToken():
        erasures+=1
        if fail_forget:return false
        value=""
        state="forgotten"
        return true
class FakeCatalog:
    extends Node
    var policy=preload("res://scripts/ConnectionPolicy.gd").new()
    var token=""
    var endpoint=""
    var epoch=0
    var cancelled=0
    var browsed=0
    func configure(address,value,_streams,_trust):
        close();endpoint=address.strip_edges().trim_suffix("/");token=value;return value.length()>=10
    func browse(_kind):browsed+=1
    func cancel():
        epoch+=1
        cancelled+=1
    func close():
        cancel()
        token=""
        endpoint=""
func check(ok,label):
    print("CREDENTIAL_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func session_closed(reason):closed.append(reason)
func access_forgotten():forgot+=1
func _init():call_deferred("run")
func run():
    var panel=load("res://scripts/MASetupPanel.gd").new()
    panel.settings_path="user://credential-lifecycle-only-test.cfg"
    get_root().add_child(panel)
    var initial=panel.catalog;panel.remove_child(initial);initial.free()
    var catalog=FakeCatalog.new();panel.add_child(catalog);panel.catalog=catalog
    var vault=FakeVault.new();panel.credential_store_override=vault
    panel.connect("credential_session_closed",self,"session_closed")
    panel.connect("credential_forgotten",self,"access_forgotten")
    panel.endpoint_edit.text="https://one.invalid"
    panel.legacy_saved_token_endpoint="https://one.invalid"
    check(panel._read_provisioned_token()==vault.value and vault.loads==1,"bound_saved_access_loads")
    catalog.token=vault.value;catalog.endpoint="https://one.invalid"
    panel.endpoint_edit.text="https://two.invalid"
    panel.endpoint_edit.emit_signal("text_changed",panel.endpoint_edit.text)
    check(catalog.token.empty() and catalog.cancelled>0 and closed.has("server_change"),"server_edit_cancels_and_clears_memory")
    var loads=vault.loads
    check(panel._read_provisioned_token().empty() and vault.loads==loads,"stored_access_never_sent_to_changed_server")
    panel.token_edit.text="synthetic-new-server-token";panel.remember_access.pressed=false
    check(panel._connect_catalog() and vault.writes==0 and panel.pending_remember_token.empty(),"typed_token_memory_only_without_consent")
    panel._disconnect_library()
    check(catalog.token.empty() and vault.value=="synthetic-access-token" and vault.pairing=="preserve-pairing","disconnect_preserves_saved_access_and_pairing")
    var before=catalog.browsed;panel.connect_saved_if_needed()
    check(catalog.browsed==before,"explicit_disconnect_blocks_session_autoconnect")
    panel.token_edit.text="synthetic-consented-token";panel.remember_access.pressed=true
    panel._connect_catalog()
    check(vault.writes==0 and not panel.pending_remember_token.empty(),"remember_waits_for_authenticated_response")
    panel._credential_state("ready","synthetic authenticated result")
    check(vault.writes==1 and vault.bound=="https://two.invalid" and panel.pending_remember_token.empty(),"successful_response_saves_bound_record")
    panel.token_edit.text="synthetic-expired-token";panel.remember_access.pressed=true;panel._connect_catalog()
    panel._credential_state("auth_expired","synthetic401")
    check(vault.writes==1 and catalog.token.empty() and panel.pending_remember_token.empty() and closed.has("auth_failed"),"revoked_access_cancels_without_saving_or_erasing")
    panel.token_edit.text="synthetic-pending-token";panel.remember_access.pressed=true;panel._connect_catalog()
    panel.endpoint_edit.text="https://three.invalid"
    panel.endpoint_edit.emit_signal("text_changed",panel.endpoint_edit.text)
    panel._credential_state("ready","stale result")
    check(vault.writes==1 and panel.pending_remember_token.empty(),"server_switch_invalidates_pending_remember")
    vault.state="legacy_conflict";vault.bound="https://three.invalid"
    check(panel._read_provisioned_token().empty() and "conflict" in panel.token_storage_label.text,"legacy_conflict_fails_closed_with_action")
    vault.state="secure_no_legacy";vault.fail_save=true
    panel.token_edit.text="synthetic-save-failure-token";panel.remember_access.pressed=true;panel._connect_catalog()
    panel._credential_state("ready","accepted but storage fails")
    check(panel.pending_remember_token.empty() and not catalog.token.empty() and "Could not finish" in panel.token_storage_label.text,"storage_failure_keeps_session_only_and_reports")
    vault.fail_save=false
    var before_forget=vault.erasures
    panel._forget_saved_access()
    check(panel.forget_access_dialog.visible and vault.erasures==before_forget and not catalog.token.empty(),"forget_requires_explicit_confirmation")
    panel.forget_access_dialog.hide()
    panel.lan_trust.emit_signal("toggled",false)
    check(catalog.token.empty() and closed.has("trust_change"),"withdrawing_trust_cancels_session")
    panel.token_edit.text="synthetic-unsent-access"
    panel.pending_remember_token="synthetic-pending-access"
    catalog.token="synthetic-session-access"
    panel._notification(MainLoop.NOTIFICATION_APP_PAUSED)
    check(panel.token_edit.text.empty() and panel.pending_remember_token.empty() and catalog.token.empty() and vault.pairing=="preserve-pairing","pause_clears_unsent_pending_and_session_access")
    vault.fail_forget=true
    check(not panel._confirm_forget_saved_access() and forgot==0 and catalog.token.empty(),"forget_failure_reports_and_disconnects")
    vault.fail_forget=false;vault.state="secure_no_legacy"
    var endpoint=panel.endpoint_edit.text
    check(panel._confirm_forget_saved_access() and forgot==1 and vault.value.empty(),"explicit_forget_removes_local_access")
    check(vault.pairing=="preserve-pairing" and panel.endpoint_edit.text==endpoint and closed.has("forget"),"forget_preserves_pairing_and_settings_contract")
    panel.queue_free()
    var dir=Directory.new()
    if File.new().file_exists("user://credential-lifecycle-only-test.cfg"):dir.remove("user://credential-lifecycle-only-test.cfg")
    print("CREDENTIAL_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
