extends SceneTree
var failures=[]
var checks=0
func check(ok,label):
    checks+=1
    print("BACKUP_TEMPO_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func feed(tracker,bpm,start,duration,jitter=0.0,bed=0.002):
    var period=60000.0/float(bpm)
    var next=float(tracker.last_onset)+period if tracker.last_onset>=0 else float(start)+200.0
    while next<start:next+=period
    var last=float(tracker.last_onset) if tracker.last_onset>=0 else -10000.0
    var count=0
    for now in range(start,start+duration,20):
        if now>=next:
            last=next
            count+=1
            next+=period+([-1.0,0.5,1.0,-0.5][count%4]*jitter)
        var age=float(now)-last
        var pulse=exp(-max(0.0,age)/60.0) if age>=0.0 and age<250.0 else 0.0
        var bands=[]
        for index in range(16):bands.append(bed+pulse*(0.45 if index<8 else 0.05))
        tracker.observe(now,bands,true,1)
    return tracker.snapshot(start+duration-20)
func _init():call_deferred("run")
func run():
    var Script=load("res://scripts/TempoTracker.gd")
    for expected in [[60.0,"slow"],[110.0,"medium"],[170.0,"fast"]]:
        var tracker=Script.new()
        var state=feed(tracker,expected[0],0,18000,15.0)
        check(state.kind=="estimated_onsets" and abs(state.bpm-expected[0])<4.0 and state.family==expected[1] and state.confidence>=tracker.MIN_CONFIDENCE,"real_onset_estimate_"+str(expected[0]))
        check(tracker.intervals.size()<=8,"history_bounded_"+str(expected[0]))
        for now in range(18000,23000,20):tracker.observe(now,[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],true,1)
        check(tracker.snapshot(22980).kind=="none" and not tracker.snapshot(22980).signal,"silence_revokes_confidence_"+str(expected[0]))
    var sparse=Script.new()
    check(feed(sparse,60.0,0,18000,10.0,0.0).kind=="estimated_onsets","silent_gaps_between_slow_beats_do_not_reset_history")
    var steady=Script.new()
    for now in range(0,18000,20):steady.observe(now,[0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2,0.2],true,1)
    check(steady.snapshot(17980).kind=="none" and steady.confidence==0.0,"constant_energy_is_not_a_beat")
    var uncertain=Script.new()
    var next=200
    var count=0
    for now in range(0,18000,20):
        var pulse=0.0
        if now>=next:
            pulse=0.7;next+=[350,1100,430,900,1270,310,780,560][count%8];count+=1
        var bands=[]
        for index in range(16):bands.append(0.002+pulse)
        uncertain.observe(now,bands,true,1)
    check(uncertain.snapshot(17980).kind=="none","irregular_onsets_do_not_claim_tempo")
    var hysteresis=Script.new()
    feed(hysteresis,84.0,0,18000,10.0)
    var held=feed(hysteresis,92.0,18000,12000,10.0)
    check(held.family=="slow","small_boundary_changes_keep_stable_family")
    var changed=feed(hysteresis,112.0,30000,12000,10.0)
    check(changed.family=="medium","sustained_new_tempo_changes_family")
    hysteresis.observe(42000,[],false,1)
    check(hysteresis.snapshot(42000).kind=="none" and hysteresis.intervals.empty(),"no_pcm_clears_tempo")
    var cast=load("res://scripts/BackupCast.gd")
    check(cast.assign("neon",["neon","sunset","ice","starlight","synth"],["starlight","synth"])==["starlight","synth"],"valid_cast_preserved")
    check(cast.assign("starlight",["neon","sunset","ice","starlight","synth"],["starlight","synth"])==["neon","synth"],"lead_collision_recasts_only_colliding_backup")
    check(cast.assign("lead",["lead","one"],["lead","one"])==["","one"],"insufficient_styles_leave_honest_empty_slot")
    var Choreo=load("res://scripts/BackupChoreography.gd")
    var positions=[]
    var poses=[]
    for expected in [[60.0,"slow"],[110.0,"medium"],[170.0,"fast"]]:
        var dance=Choreo.new()
        for index in range(250):
            var phase=fposmod(float(index)*0.02*expected[0]/60.0,1.0)
            dance.step(0.02,{"kind":"estimated_onsets","bpm":expected[0],"phase":phase,"family":expected[1]},true,false)
        positions.append(dance.position);poses.append(dance.pose(0))
        check(dance.family==expected[1] and dance.pose(0).size()==33 and dance.pose(0)!=dance.pose(1),"distinct_phase_and_family_"+expected[1])
        var before=dance.pose(0)
        for _i in range(50):dance.step(0.02,{"kind":"estimated_onsets","bpm":180.0,"phase":0.5,"family":"fast"},true,true)
        check(dance.pose(0)==before,"reduced_motion_freezes_pose_"+expected[1])
        dance.step(.02,{},false,false)
        check(dance.pose(0).empty(),"no_pcm_removes_pose_"+expected[1])
    check(positions[2]>positions[0]*2.2 and poses[0]!=poses[1] and poses[1]!=poses[2],"tempo_changes_move_speed_not_only_intensity")
    var manual=Choreo.new();manual.step(.1,{},true,false,120.0)
    check(manual.kind=="configured_metronome","manual_bpm_is_labelled_configured")
    var gentle=Choreo.new();gentle.step(.1,{},true,false)
    check(gentle.kind=="none" and gentle.family=="gentle","unreliable_tempo_uses_unclaimed_gentle_motion")
    print("BACKUP_TEMPO_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
