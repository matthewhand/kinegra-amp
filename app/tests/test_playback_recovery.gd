extends SceneTree
var failures=[]
var count=0
func check(ok,label):
    count+=1
    if not ok:failures.append(label)
    print("RECOVERY_"+("PASS_" if ok else "FAIL_")+label)
func _init():call_deferred("run")
func run():
    var policy=preload("res://scripts/PlaybackRecovery.gd").new()
    check(policy.step(60000,"owner",-1,true,false,"playing",true)=="","cold_start_never_autoplays")
    policy.play_intent("owner",0)
    check(policy.step(29000,"owner",-1,true,false,"playing",true)=="","startup_wait_is_bounded_but_not_premature")
    check(policy.step(30000,"owner",-1,true,false,"playing",true)=="reconnect","missing_startup_audio_reconnects")
    check(policy.step(31000,"owner",-1,true,false,"playing",true)=="","backoff_prevents_retry_storm")
    check(policy.step(60000,"owner",-1,true,false,"playing",true)=="reconnect","second_attempt")
    check(policy.step(90000,"owner",-1,true,false,"playing",true)=="reconnect","third_attempt")
    check(policy.step(150000,"owner",-1,true,false,"playing",true)=="exhausted" and not policy.armed,"stops_after_three_attempts")
    for state in ["paused","stopped","idle"]:
        policy.play_intent("owner",0)
        check(policy.step(40000,"owner",-1,true,false,state,true)=="" and not policy.armed,"external_"+state+"_respected")
    policy.play_intent("owner",0)
    check(policy.step(40000,"changed",-1,true,false,"playing",true)=="" and not policy.armed,"changed_origin_or_identity_cancels")
    policy.play_intent("owner",0)
    check(policy.step(40000,"owner",-1,true,true,"playing",true)=="","pending_mutation_is_never_repeated")
    policy.cancel()
    check(policy.step(80000,"owner",-1,true,false,"playing",true)=="","explicit_cancel_stays_cancelled")
    policy.play_intent("owner",0)
    for i in range(80):
        check(policy.step(i*1000,"owner",i*1000,false,false,"playing",true)=="","silent_pcm_is_healthy_"+str(i))
    check(policy.step(87000,"owner",79000,true,false,"playing",true)=="reconnect","eight_second_live_stall_recovers")
    check(policy.step(88000,"owner",88000,false,false,"playing",true)=="","audio_return_does_not_reconnect")
    print("RECOVERY_CHECKS=",count," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
