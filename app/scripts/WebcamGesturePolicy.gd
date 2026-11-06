extends Reference
# Experimental 2D body-landmark control only. No hand model, recordings or I/O.
const ACTIONS=["previous","play_pause","next"]
const GESTURES=["none","left_hold","right_hold","both_hold","left_wave","right_wave","head_shake"]
const LABELS=["Unassigned","Left arm hold","Right arm hold","Both arms hold","Slow left hand wave","Slow right hand wave","Slow head shake (experimental)"]
const DEFAULTS={"previous":"left_wave","play_pause":"both_hold","next":"right_wave"}
const NEUTRAL_MS=1000
const COOLDOWN_MS=2500
const STALE_MS=750
var enabled=false
var bindings=DEFAULTS.duplicate()
var feedback="Gestures off"
var armed=false
var neutral_since=-1
var cooldown_until=0
var last_epoch=-1
var last_frame=-1
var last_capture=-1
var last_received=-1
var candidate=""
var candidate_since=-1
var candidate_samples=0
var hold_origin=Vector2.ZERO
var hold_other=Vector2.ZERO
var wave_side=0
var wave_turns=0
var body_origin=Vector2.ZERO
var body_span=0.0
static func recipe(gesture):
    match gesture:
        "left_hold":return "From arms down, hold your left wrist above its shoulder and keep it still for 1.2 seconds. Lower both arms to rearm."
        "right_hold":return "From arms down, hold your right wrist above its shoulder and keep it still for 1.2 seconds. Lower both arms to rearm."
        "both_hold":return "From arms down, hold both wrists above their shoulders for 1.7 seconds. Lower both arms to rearm."
        "left_wave":return "From arms down, raise your left wrist above its shoulder and move it left, right, left, right across the shoulder (three direction changes over 2–4 seconds). Lower both arms to rearm."
        "right_wave":return "From arms down, raise your right wrist above its shoulder and move it left, right, left, right across the shoulder (three direction changes over 2–4 seconds). Lower both arms to rearm."
        "head_shake":return "Experimental: keep both arms down and shoulders still, then turn your head slowly side to side three times (about 1.5 seconds per full turn cycle). Return face forward to rearm."
    return "No gesture assigned."
static func short_label(gesture):
    return {"left_hold":"Left hold","right_hold":"Right hold","both_hold":"Both arms","left_wave":"Slow L wave","right_wave":"Slow R wave","head_shake":"Slow shake"}.get(gesture,"")
func configure(value,choices):
    if typeof(choices)!=TYPE_DICTIONARY:return false
    var clean={}
    var used=[]
    for action in ACTIONS:
        var gesture=choices.get(action,"none")
        if not gesture in GESTURES or (gesture!="none" and gesture in used):return false
        clean[action]=gesture
        if gesture!="none":used.append(gesture)
    enabled=bool(value);bindings=clean
    cancel("Lower your arms to arm" if enabled else "Gestures off")
    return true
func cancel(reason="Lower your arms to arm"):
    armed=false;neutral_since=-1;candidate="";candidate_since=-1;candidate_samples=0;wave_side=0;wave_turns=0
    feedback=reason
func tick(now,allowed):
    if not enabled:cancel("Gestures off")
    elif not allowed:cancel("Gestures paused / close menus and return to player")
    elif last_received<0 or now-last_received>STALE_MS:cancel("Waiting for fresh webcam landmarks")
func _number(value):
    return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value))
func _joint(points,index,minimum=.65):
    if typeof(points)!=TYPE_ARRAY or points.size()!=33:return false
    var item=points[index]
    return typeof(item)==TYPE_ARRAY and item.size()>=3 and _number(item[0]) and _number(item[1]) and _number(item[2]) and item[0]>=0.0 and item[0]<=1.0 and item[1]>=0.0 and item[1]<=1.0 and item[2]>=minimum and item[2]<=1.0
func _point(points,index):return Vector2(points[index][0],points[index][1])
func _begin(value,now,origin):
    candidate=value;candidate_since=now;candidate_samples=0;hold_origin=origin;wave_side=0;wave_turns=0
func _action(gesture,now):
    for action in ACTIONS:
        if bindings[action]==gesture:
            cooldown_until=now+COOLDOWN_MS
            cancel("Gesture accepted / lower arms and return face forward")
            return action
    return ""
func sample(now,source_epoch,frame,captured,points,allowed):
    tick(now,allowed)
    if not enabled or not allowed:return ""
    for value in [now,source_epoch,frame,captured]:
        if not _number(value) or value<0 or value>9007199254740991 or floor(float(value))!=float(value):
            cancel("Waiting for identified fresh webcam frames");return ""
    if captured>now or now-captured>500:
        cancel("Waiting for fresh webcam landmarks");return ""
    if source_epoch!=last_epoch:
        last_epoch=source_epoch;last_frame=-1;last_capture=-1
        cancel("New webcam source / hold neutral to arm")
    if frame<=last_frame or captured<=last_capture:return ""
    if last_capture>=0 and captured-last_capture>650:cancel("Tracking gap / hold neutral to arm")
    last_frame=frame;last_capture=captured;last_received=now
    var arm_bound=false
    for gesture in bindings.values():
        if gesture!="none" and gesture!="head_shake":arm_bound=true
    # Arm controls do not depend on the face or off-screen hips.
    for index in ([11,12,15,16] if arm_bound else [0,2,5]):
        if not _joint(points,index,.45 if index in [15,16] else .65):
            cancel("Keep shoulders and wrists visible" if arm_bound else "Keep your face visible");return ""
    var face_valid=_joint(points,0) and _joint(points,2) and _joint(points,5)
    var eye_span=_point(points,2).distance_to(_point(points,5)) if face_valid else 0.0
    face_valid=face_valid and eye_span>=.02
    var left=_point(points,11) if arm_bound else _point(points,2)
    var right=_point(points,12) if arm_bound else _point(points,5)
    var center=(left+right)*.5
    var span=left.distance_to(right)
    if span<(.06 if arm_bound else .02) or abs(left.y-right.y)>span*.5:
        cancel("Keep shoulders level" if arm_bound else "Face the camera");return ""
    var eye_center=(_point(points,2)+_point(points,5))*.5 if face_valid else Vector2.ZERO
    var yaw=(_point(points,0).x-eye_center.x)/eye_span if face_valid else 0.0
    var face_pitch=(_point(points,0).y-eye_center.y)/eye_span if face_valid else 0.5
    var left_wrist=_point(points,15) if arm_bound else left+Vector2(0,span)
    var right_wrist=_point(points,16) if arm_bound else right+Vector2(0,span)
    var down=left_wrist.y>left.y+span*.25 and right_wrist.y>right.y+span*.25
    var neutral=down and (arm_bound or (face_valid and abs(yaw)<.40 and face_pitch>-1.0 and face_pitch<3.0))
    if not armed:
        if now<cooldown_until:
            neutral_since=-1;feedback="Gesture cooldown / lower arms";return ""
        if neutral:
            if neutral_since<0:neutral_since=captured
            feedback="Arming / hold neutral %.1fs" % max(0.0,float(NEUTRAL_MS-(captured-neutral_since))/1000.0)
            if captured-neutral_since>=NEUTRAL_MS:
                armed=true;body_origin=center;body_span=span;candidate="";feedback="Gestures ready / deliberate movement only"
        else:neutral_since=-1;feedback="Lower your arms to arm"
        return ""
    if center.distance_to(body_origin)>body_span*.35 or span<body_span*.8 or span>body_span*1.2:
        cancel("Body moved / hold neutral to rearm");return ""
    var left_up=left_wrist.y<left.y-span*.15
    var right_up=right_wrist.y<right.y-span*.15
    if (left_up and not _joint(points,15,.60)) or (right_up and not _joint(points,16,.60)):
        candidate=""
        feedback="Show the raised wrist clearly to activate"
        return ""
    var options=[]
    if left_up and right_up:options=["both_hold"]
    elif left_up and right_wrist.y>right.y+span*.25:options=["left_wave","left_hold"]
    elif right_up and left_wrist.y>left.y+span*.25:options=["right_wave","right_hold"]
    elif face_valid and down and face_pitch>-1.0 and face_pitch<3.0 and (abs(yaw)>.40 or candidate=="head_shake"):options=["head_shake"]
    var selected=""
    # A wave takes precedence only after actual side excursions; stable holds
    # are still available when a different action uses a wave on the same arm.
    for option in options:
        if option in bindings.values():
            if option.ends_with("wave") and options.size()>1 and options[1] in bindings.values():
                var wrist=left_wrist if option=="left_wave" else right_wrist
                if candidate!="" and candidate==option:
                    selected=option;break
                if candidate!=options[1] or wrist.distance_to(hold_origin)<span*.18:
                    selected=options[1];break
            selected=option;break
    if selected.empty():
        candidate="";feedback="Gestures ready / deliberate movement only";return ""
    var wrist=left_wrist if selected.begins_with("left") else right_wrist
    if selected=="both_hold":wrist=left_wrist
    if candidate!=selected:
        _begin(selected,captured,wrist)
        hold_other=right_wrist
    candidate_samples+=1
    var elapsed=captured-candidate_since
    if selected.ends_with("hold"):
        if wrist.distance_to(hold_origin)>span*.18 or (selected=="both_hold" and right_wrist.distance_to(hold_other)>span*.18):
            _begin(selected,captured,wrist)
            hold_other=right_wrist
        var required=1700 if selected=="both_hold" else 1200
        feedback=short_label(selected)+" / hold %.1fs" % max(0.0,float(required-(captured-candidate_since))/1000.0)
        if captured-candidate_since>=required and candidate_samples>=5:return _action(selected,now)
    else:
        var lateral=yaw if selected=="head_shake" else (wrist.x-(left.x if selected=="left_wave" else right.x))/span
        var threshold=.40 if selected=="head_shake" else .35
        var side=-1 if lateral< -threshold else (1 if lateral>threshold else 0)
        if side!=0 and side!=wave_side:
            if wave_side!=0:wave_turns+=1
            wave_side=side
        feedback=short_label(selected)+" / %d of 3 turns" % min(3,wave_turns)
        if elapsed>5000:
            cancel("Gesture timed out / hold neutral to rearm");return ""
        if wave_turns>=3 and elapsed>=1000 and candidate_samples>=5:return _action(selected,now)
    return ""
