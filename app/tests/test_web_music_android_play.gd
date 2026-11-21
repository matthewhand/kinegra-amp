extends SceneTree
# The real web acknowledgement handler must authorize only its own Android
# session. No Android device, audio output, server or owner credentials are used.
const API=preload("res://scripts/WebMusicAPI.gd")

class FixtureFacade:
    extends Reference
    var permitted=false
    var allow_permit=true
    var paired=true
    var commands=[]
    var events=[]
    func command(name):
        commands.append(name)
        if name=="pause":
            permitted=false
            return true
        if name!="permit":return false
        events.append("permit")
        permitted=allow_permit
        return allow_permit

class FixturePanel:
    extends Reference
    var library_disconnected=false
    var origin="https://music.example"
    func _credential_endpoint():return origin

class FixtureCatalog:
    extends Reference
    var last_result_code="fixture"
    var last_http_code=500

class FixtureOwner:
    extends Reference
    var android=true
    var ma_panel=FixturePanel.new()
    var sendspin_facade=FixtureFacade.new()
    var tv_queue_timer=null
    var credential="synthetic-library-access"
    var client_id="fixture-client"
    var events=[]
    var error=""
    var recovery_count=0
    var visual_count=0
    var playback_recovery=preload("res://scripts/PlaybackRecovery.gd").new()
    func _library_credential(_saved=true):return credential
    func _sendspin_controls():
        return {"paired":true,"client_id":client_id} if sendspin_facade!=null and sendspin_facade.paired else {}
    func _uses_android_sendspin():return android
    func _arm_playback_recovery():
        recovery_count+=1
        events.append("recovery")
        playback_recovery.play_intent("fixture-route",OS.get_ticks_msec())
    func _prepare_stream_visuals():
        visual_count+=1
        events.append("visuals")
    func _set_tv_playback_error(detail):error=detail

var checks=0
var failures=0

func _init():call_deferred("run")

func check(value,label):
    checks+=1
    if not value:
        failures+=1
        printerr("WEB_ANDROID_PLAY_FAIL_",label)
    else:
        print("WEB_ANDROID_PLAY_PASS_",label)

func fixture(kind="play"):
    var api=API.new()
    var app=FixtureOwner.new()
    app.sendspin_facade.events=app.events
    api.app=app
    api.catalog=FixtureCatalog.new()
    api.binding_origin=app.ma_panel.origin
    api.binding_hash=app.credential.sha256_text()
    api.jobs={"1":{"result":{"operation":"1","state":"loading"}}}
    api.active={"id":"1","kind":kind,"phase":"mutation","sent":true,
        "facade":app.sendspin_facade,"client":app.client_id}
    return {"api":api,"app":app}

func finish_case(value):
    # The fixture is intentionally outside the scene tree: only the real
    # acknowledgement handler runs, with no timers or HTTP requests.
    value.api.catalog=null
    value.api.app=null
    value.api.free()

func state(value):return value.api.jobs["1"].result.state

func run():
    for initial in ["cold","paused"]:
        var value=fixture()
        var facade=value.app.sendspin_facade
        if initial=="paused":
            facade.permitted=true
            facade.command("pause")
            facade.commands.clear()
        check(not facade.permitted,initial+"_starts_without_audio_permission")
        value.api._catalog_state("play_requested","")
        check(facade.permitted and facade.commands==["permit"],initial+"_permits_once")
        check(value.app.events==["permit","recovery","visuals"],initial+"_permit_precedes_recovery")
        check(state(value)=="done" and value.app.playback_recovery.armed,initial+"_job_completes")
        value.api._catalog_state("play_requested","")
        check(facade.commands==["permit"],initial+"_duplicate_ack_does_not_permit_again")
        finish_case(value)

    var denied=fixture()
    denied.app.sendspin_facade.allow_permit=false
    denied.app.playback_recovery.play_intent("fixture-route",OS.get_ticks_msec())
    denied.api._catalog_state("play_requested","")
    check(state(denied)=="error" and "Android audio is unavailable" in denied.app.error,"denied_permit_reports_error")
    check(not denied.app.sendspin_facade.permitted and denied.app.sendspin_facade.commands==["permit"],"denied_permit_does_not_play")
    check(not denied.app.playback_recovery.armed and denied.app.recovery_count==0 and denied.app.visual_count==0,"denied_permit_cancels_prior_recovery")
    denied.api._catalog_state("play_requested","")
    check(denied.app.sendspin_facade.commands==["permit"] and denied.api.active.empty(),"denied_permit_is_not_retried")
    finish_case(denied)

    for kind in ["add","add_page"]:
        var added=fixture(kind)
        added.api._catalog_state("queue_added","")
        check(state(added)=="done" and added.app.sendspin_facade.commands.empty(),kind+"_does_not_permit_audio")
        check(added.app.recovery_count==0 and added.app.visual_count==0,kind+"_does_not_arm_playback")
        finish_case(added)

    for failure in ["command_failed","disconnected"]:
        var rejected=fixture()
        rejected.api._catalog_state(failure,"Synthetic command failure")
        check(state(rejected)=="error" and rejected.app.sendspin_facade.commands.empty(),failure+"_does_not_permit")
        check(rejected.api.active.empty() and rejected.app.recovery_count==0 and not rejected.app.playback_recovery.armed,failure+"_does_not_retry_or_recover")
        finish_case(rejected)

    for kind in ["play","add"]:
        for http_code in [200,400,500]:
            var http_failure=fixture(kind)
            http_failure.api.catalog.last_http_code=http_code
            var detail="Music Assistant rejected the request (HTTP 400)." if http_code==400 else ("Music Assistant server error (HTTP 500)." if http_code==500 else "Music Assistant declined the request")
            http_failure.api._catalog_state("command_failed",detail)
            var message=http_failure.api.jobs["1"].result.message
            check(state(http_failure)=="error" and message.begins_with(detail) and "unknown" in message and "check Queue before retrying" in message,kind+"_http_"+str(http_code)+"_keeps_unknown_outcome_warning")
            http_failure.api._catalog_state("command_failed",detail)
            check(http_failure.api.active.empty() and http_failure.app.sendspin_facade.commands.empty() and http_failure.app.recovery_count==0,kind+"_http_"+str(http_code)+"_does_not_repeat_mutation_or_permit")
            finish_case(http_failure)

    var unsent=fixture("browse")
    unsent.api.active.sent=false
    unsent.api.active.phase="catalog"
    unsent.api._catalog_state("command_failed","Synthetic read rejection")
    check(state(unsent)=="error" and unsent.api.jobs["1"].result.message=="Synthetic read rejection","unsent_failure_retains_detail_without_mutation_warning")
    check(unsent.api.active.empty() and unsent.app.sendspin_facade.commands.empty() and unsent.app.recovery_count==0,"unsent_failure_does_not_start_playback")
    finish_case(unsent)

    for access_state in ["auth_expired","permission_denied"]:
        var access_failure=fixture()
        access_failure.api._catalog_state(access_state,"Ignored server description")
        check(state(access_failure)=="error" and access_failure.api.jobs["1"].result.message=="Music Assistant rejected library access. Reconnect the library on the TV.",access_state+"_retains_access_guidance")
        check(access_failure.api.active.empty() and access_failure.app.sendspin_facade.commands.empty() and access_failure.app.recovery_count==0,access_state+"_does_not_repeat_mutation_or_permit")
        finish_case(access_failure)

    for change in ["facade","client","credential","origin","disconnected","unpaired","removed"]:
        var stale=fixture()
        var original=stale.app.sendspin_facade
        stale.app.playback_recovery.play_intent("replacement-route",OS.get_ticks_msec())
        if change=="facade":
            stale.app.sendspin_facade=FixtureFacade.new()
        elif change=="client":stale.app.client_id="replacement-client"
        elif change=="credential":stale.app.credential="changed-synthetic-access"
        elif change=="origin":stale.app.ma_panel.origin="https://other.example"
        elif change=="disconnected":stale.app.ma_panel.library_disconnected=true
        elif change=="unpaired":original.paired=false
        elif change=="removed":stale.app.sendspin_facade=null
        stale.api._catalog_state("play_requested","")
        check(state(stale)=="error" and original.commands.empty(),"changed_"+change+"_rejects_late_ack")
        check(stale.app.playback_recovery.armed and stale.app.error.empty() and stale.app.recovery_count==0,"changed_"+change+"_preserves_replacement_state")
        if change=="facade":
            check(stale.app.sendspin_facade.commands.empty(),"replacement_facade_not_permitted")
        finish_case(stale)

    var other=fixture()
    other.app.android=false
    other.api._catalog_state("play_requested","")
    check(state(other)=="done" and other.app.sendspin_facade.commands.empty(),"non_android_does_not_require_permit")
    check(other.app.events==["recovery","visuals"],"non_android_preserves_playback_flow")
    finish_case(other)

    var mismatched=fixture()
    mismatched.api._catalog_state("queue_added","")
    check(state(mismatched)=="loading" and mismatched.app.sendspin_facade.commands.empty(),"queue_ack_cannot_authorize_play")
    mismatched.api._catalog_state("play_requested","")
    check(state(mismatched)=="done" and mismatched.app.sendspin_facade.commands==["permit"],"matching_ack_can_complete_play")
    finish_case(mismatched)

    var premature=fixture()
    premature.api.active.phase="connect"
    premature.api._catalog_state("play_requested","")
    check(state(premature)=="loading" and premature.app.sendspin_facade.commands.empty(),"play_ack_before_mutation_is_ignored")
    finish_case(premature)

    print("WEB_ANDROID_PLAY_CHECKS=",checks," FAILURES=",failures)
    quit(1 if failures else 0)
