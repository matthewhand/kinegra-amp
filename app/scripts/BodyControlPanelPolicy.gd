extends Reference
# Screen-plane reach controls. No measured depth, face dependency or I/O.
const ACTIONS=["previous","play_pause","next","stop","close"]
const CENTERS=[Vector2(.20,.36),Vector2(.50,.36),Vector2(.80,.36),Vector2(.35,.58),Vector2(.65,.58)]
var panel_open=false
var feedback="Lower arms, then cross them to open controls"
var hands=[]
var hover=-1
var armed=false
var neutral_since=-1
var cross_since=-1
var candidate=-1
var candidate_at=-1
var candidate_samples=0
var cooldown_until=0
var last_epoch=-1
var last_frame=-1
var last_capture=-1
var last_received=-1
var last_activity=0
var previous_hands=[]
func cancel(reason="Lower arms, then cross them to open controls"):
    panel_open=false;armed=false;neutral_since=-1;cross_since=-1
    candidate=-1;candidate_at=-1;candidate_samples=0;hands=[];previous_hands=[];hover=-1;feedback=reason
func number(value):return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value))
func joint(points,index,confidence):
    if typeof(points)!=TYPE_ARRAY or points.size()!=33:return false
    var p=points[index]
    if typeof(p)!=TYPE_ARRAY or p.size()<3:return false
    for value in p:
        if not number(value):return false
    return p[0]>=0 and p[0]<=1 and p[1]>=0 and p[1]<=1 and p[2]>=confidence and p[2]<=1
func point(points,index):return Vector2(points[index][0],points[index][1])
func tick(now,allowed):
    if not allowed:cancel("Controls paused / close menus or return to the visible player")
    elif last_received>=0 and now-last_received>750:cancel("Tracking interrupted / show shoulders and wrists")
    elif panel_open and now-last_activity>12000:cancel("Controls closed / cross arms to reopen")
func sample(now,epoch,frame,captured,points,allowed):
    tick(now,allowed)
    if not allowed:return ""
    for value in [now,epoch,frame,captured]:
        if not number(value) or value<0 or value>9007199254740991 or floor(float(value))!=float(value):
            cancel("Waiting for fresh identified frames")
            return ""
    if captured>now or now-captured>500:
        cancel("Waiting for fresh webcam frames")
        return ""
    if epoch!=last_epoch:
        cancel();last_epoch=epoch;last_frame=-1;last_capture=-1
    if frame<=last_frame or captured<=last_capture:return ""
    if last_capture>=0 and captured-last_capture>650:cancel("Tracking gap / lower arms to rearm")
    var dt=max(.001,float(captured-last_capture)/1000.0) if last_capture>=0 else .25
    last_frame=frame;last_capture=captured;last_received=now
    for index in [11,12,15,16]:
        if not joint(points,index,.65 if index in [11,12] else .45):
            cancel("Show both shoulders and wrists / head tracking is not required")
            return ""
    var left=point(points,11);var right=point(points,12)
    var center=(left+right)*.5;var span=left.distance_to(right)
    if span<.06 or span>.65 or abs(left.y-right.y)>span*.6:
        cancel("Face the camera with shoulders visible")
        return ""
    var wrists=[point(points,15),point(points,16)]
    var down=wrists[0].y>left.y+span*.65 and wrists[1].y>right.y+span*.65
    var crossed=wrists[0].distance_to(right)<span*.70 and wrists[1].distance_to(left)<span*.70
    hands=[]
    for wrist in wrists:hands.append(Vector2(clamp(.5-(wrist.x-center.x)/span*.30,0,1),clamp(.35+(wrist.y-center.y)/span*.25,0,1)))
    if not panel_open:
        if down:
            if neutral_since<0:neutral_since=captured
            if captured-neutral_since>=500:armed=true
        elif not crossed:neutral_since=-1
        if armed and crossed:
            if cross_since<0:cross_since=captured
            feedback="Crossed arms / hold briefly to open controls"
            if captured-cross_since>=650:
                panel_open=true;armed=false;neutral_since=-1;cross_since=-1;last_activity=now
                feedback="Controls open / lower hands, then reach into a button"
        else:
            cross_since=-1
            feedback="Cross arms to open controls" if armed else "Lower arms briefly, then cross them"
        previous_hands=hands.duplicate();return ""
    if not armed:
        if down and now>=cooldown_until:
            if neutral_since<0:neutral_since=captured
            if captured-neutral_since>=300:
                armed=true
                feedback="Reach into a button / lower hands after each action"
        else:neutral_since=-1
        previous_hands=hands.duplicate();return ""
    hover=-1
    var moving_into=false
    for hand_index in range(hands.size()):
        if not joint(points,15 if hand_index==0 else 16,.60):continue
        var wrist=wrists[hand_index];var shoulder=left if hand_index==0 else right
        if wrist.distance_to(shoulder)<span*.35:continue
        for index in range(CENTERS.size()):
            var distance=hands[hand_index].distance_to(CENTERS[index])
            if distance<.115:
                hover=index
                if previous_hands.size()==2:
                    var previous_distance=previous_hands[hand_index].distance_to(CENTERS[index])
                    moving_into=moving_into or (previous_distance>distance+.025 and hands[hand_index].distance_to(previous_hands[hand_index])/dt>.25)
    previous_hands=hands.duplicate()
    if hover<0:
        candidate=-1
        candidate_samples=0
        return ""
    if hover!=candidate:
        candidate=-1
        if not moving_into:return ""
        candidate=hover;candidate_at=captured;candidate_samples=1
        feedback="Target: "+ACTIONS[candidate].replace("_"," ")
        return ""
    candidate_samples+=1
    if candidate_samples>=2 and captured-candidate_at>=200:
        var action=ACTIONS[candidate];candidate=-1;candidate_samples=0;cooldown_until=now+1200;armed=false;neutral_since=-1;last_activity=now
        if action=="close":
            cancel("Controls closed / cross arms to reopen")
            return ""
        feedback="Accepted / lower hands before the next control"
        return action
    return ""
