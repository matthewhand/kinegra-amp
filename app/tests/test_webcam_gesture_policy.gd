extends SceneTree
const Policy=preload("res://scripts/WebcamGesturePolicy.gd")
var failures=[]
var checks=0
var clock=1000
var frame=0
var policy=null
var events=[]
func check(ok,label):
    checks+=1;print("GESTURE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func neutral():
    var p=[]
    for _i in range(33):p.append([.5,.5,1.0])
    p[0]=[.5,.24,1.0];p[2]=[.47,.21,1.0];p[5]=[.53,.21,1.0]
    p[11]=[.4,.4,1.0];p[12]=[.6,.4,1.0];p[23]=[.43,.7,1.0];p[24]=[.57,.7,1.0]
    p[15]=[.36,.65,1.0];p[16]=[.64,.65,1.0]
    return p
func setup(gesture="right_hold"):
    policy=Policy.new();clock=1000;frame=0;events=[]
    policy.configure(true,{"previous":"none","play_pause":"none","next":gesture})
func feed(p,dt=250,allowed=true):
    clock+=dt;frame+=1
    var action=policy.sample(clock,1,frame,clock,p,allowed)
    if not action.empty():events.append(action)
func arm():
    for _i in range(6):feed(neutral())
func perform(gesture):
    var p=neutral()
    if gesture in ["left_hold","left_wave","both_hold"]:p[15][1]=.3
    if gesture in ["right_hold","right_wave","both_hold"]:p[16][1]=.3
    for index in range(10):
        if gesture=="left_wave":p[15][0]=.3 if index%2==0 else .5
        if gesture=="right_wave":p[16][0]=.5 if index%2==0 else .7
        if gesture=="head_shake":p[0][0]=.46 if index%2==0 else .54
        feed(p)
    return p
func _init():call_deferred("run")
func run():
    setup();check(not policy.configure(true,{"previous":"right_hold","play_pause":"none","next":"right_hold"}),"duplicate_bindings_rejected_atomically")
    check(policy.bindings.next=="right_hold" and policy.bindings.previous=="none","rejected_binding_keeps_previous_assignment")
    check(not policy.configure(true,{"previous":"unknown","play_pause":"none","next":"none"}),"unknown_binding_rejected")
    for gesture in Policy.GESTURES:
        if gesture=="none":continue
        setup(gesture);perform(gesture)
        check(events.empty(),"enable_while_gesturing_never_acts_"+gesture)
        arm();check(policy.armed,"neutral_arms_"+gesture)
        var held=perform(gesture)
        check(events==["next"],"deliberate_gesture_once_"+gesture)
        for _i in range(25):feed(held)
        check(events.size()==1,"held_pose_never_repeats_"+gesture)
        for _i in range(20):feed(neutral())
        perform(gesture)
        check(events.size()==2,"neutral_rearm_after_cooldown_"+gesture)
    setup();arm()
    var raised=neutral();raised[16][1]=.3;feed(raised)
    for _i in range(20):
        clock+=100
        var action=policy.sample(clock,1,frame,policy.last_capture,raised,true)
        if not action.empty():events.append(action)
    check(events.empty() and not policy.armed,"cached_duplicate_frames_cannot_advance_hold")
    setup();arm();feed(raised);feed(raised,250,false)
    for _i in range(10):feed(raised)
    check(events.empty(),"menu_interrupt_requires_new_neutral")
    setup();arm();feed(raised);policy.cancel("dropout")
    for _i in range(10):feed(raised)
    check(events.empty(),"dropout_cannot_finish_prior_hold")
    setup();arm();feed(raised,1000)
    for _i in range(10):feed(raised)
    check(events.empty(),"sample_gap_cancels_armed_state")
    setup();arm()
    var weak=raised.duplicate(true);weak[16][2]=.4
    for _i in range(10):feed(weak)
    check(events.empty() and not policy.armed,"weak_wrist_cannot_trigger")
    setup();arm()
    var sway=neutral()
    for index in range(30):
        sway=neutral()
        for point in sway:point[0]+=.025*sin(index*.7)
        feed(sway)
    check(events.empty(),"ordinary_whole_body_sway_is_not_head_shake_or_wave")
    setup("head_shake");arm()
    for index in range(20):
        var nod=neutral();nod[0][1]=.23 if index%2==0 else .26;feed(nod)
    check(events.empty(),"vertical_head_motion_is_not_shake")
    setup();arm();var shifted=raised.duplicate(true)
    for point in shifted:point[0]+=.1
    for _i in range(10):feed(shifted)
    check(events.empty(),"large_body_motion_disarms")
    setup();arm();policy.configure(false,policy.bindings);perform("right_hold")
    check(events.empty(),"disabled_never_acts")
    setup();arm();clock+=250;frame+=1
    check(policy.sample(clock,1,frame,clock+1,raised,true).empty() and not policy.armed,"future_capture_rejected")
    setup();arm();clock+=250;frame+=1
    check(policy.sample(clock,1,frame,clock-501,raised,true).empty() and not policy.armed,"old_capture_rejected")
    setup();arm();clock+=250;frame+=1
    check(policy.sample(clock,-1,frame,clock,raised,true).empty() and not policy.armed,"unidentified_source_rejected")
    setup();arm();clock+=250;frame+=1
    policy.sample(clock,2,frame,clock,raised,true)
    for _i in range(8):feed(raised)
    check(events.empty(),"source_epoch_change_requires_new_neutral")
    for gesture in ["left_wave","right_wave","head_shake"]:
        setup(gesture);arm()
        var started=clock
        for index in range(20):
            var dt=250+([-40,20,40,-20][index%4])
            var motion=sin(float(clock+dt-started)/1600.0*TAU)
            var p=neutral()
            if gesture=="head_shake":p[0][0]=.5+motion*.05
            else:
                var joint=15 if gesture=="left_wave" else 16
                p[joint][1]=.3;p[joint][0]=(.4 if joint==15 else .6)+motion*.12
            feed(p,dt)
        check(events==["next"],"slow_gesture_at_real_4hz_with_jitter_"+gesture)
    setup();arm();policy.tick(clock+751,true)
    check(not policy.armed,"no_fresh_samples_timeout")
    print("GESTURE_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
