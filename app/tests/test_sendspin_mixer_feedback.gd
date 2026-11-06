extends SceneTree
var failures=[]
func check(ok,label):
    print("MIXER_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var f=load("res://scripts/SendspinMixerFeedback.gd").new()
    check(not f.begin(-1,10) and f.begin(7,100),"validated_start")
    check(f.pushed(7,80),"record_frames")
    var none=f.sample(7,20,1000000,1000,50000)
    check(none.frames==0,"no_consumption_no_report")
    var report=f.sample(7,50,1000000,1000,50000)
    check(report.frames==30 and report.remaining==50 and report.finish_us==1049000,"mixer_consumption_estimate")
    var retry=f.sample(7,50,1000000,1000,50000)
    check(retry.frames==report.frames and retry.finish_us==report.finish_us,"retry_same_report_until_accepted")
    check(f.committed(7,report) and f.queued==50,"commit_after_sdk_accepts")
    check(f.pushed(7,40),"new_frames_after_report")
    check(f.sample(6,20,1000000,1000,50000).empty(),"old_generation_rejected")
    check(f.sample(7,101,1000000,1000,50000).empty(),"invalid_free_count_rejected")
    check(f.sample(7,50,1000000,2000000,50000).empty(),"stale_mix_rejected")
    f.reset()
    check(f.sample(7,50,1000000,1000,50000).empty(),"reset_revokes_old_generation")
    check(f.begin(8,48000) and f.pushed(8,24000),"clock_start")
    var base=10000000
    var previous=0
    var stable=true
    var exact=true
    for index in range(250):
        var ideal=base+(index+1)*20000
        var quantized=ideal+(20000 if index%2==0 else -20000)+index*4 # 200 ppm clock drift.
        var sample=f.sample(8,48000-(f.queued-960),quantized-50000,0,50000)
        if sample.empty():
            stable=false
            break
        if sample.frames!=960:exact=false
        if index>33 and abs(sample.finish_us-previous-20000)>11:stable=false
        previous=sample.finish_us
        if not f.committed(8,sample) or not f.pushed(8,960):stable=false
    check(stable and exact,"quantized_clock_dejitter_preserves_measured_counts")
    check(abs(previous-(base+5000000+996))<3000,"clock_tracks_bounded_drift")
    var before_clock=f.last_finish_us
    var paused=f.sample(8,48000-f.queued,base+6000000,0,50000)
    check(paused.frames==0 and f.last_finish_us==before_clock,"no_consumption_does_not_invent_frames_or_time")
    f.reanchor_clock()
    var resumed=f.sample(8,48000,base+7000000,0,50000)
    check(resumed.frames==f.queued and resumed.finish_us==base+7050000,"real_underrun_reanchors_after_gap")
    print("MIXER_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
