extends Control
# Opt-in loopback-only Kinegra pose consumer. No camera capture or pose storage.
signal status_changed(value)
var status_presenter=preload("res://scripts/StatusStability.gd").new()
var presented_status=""
var display_points=[]
var last_body_height=0.0
var display_fade=preload("res://scripts/TrackingFade.gd").new()
signal webcam_changed(connected)
signal gesture_sample(points,source_epoch,frame,captured_at)
signal gesture_tracking_lost(reason)
var webcam_connected=false
var _gesture_source_epoch=-1
var _gesture_source_frame=-1
var _gesture_capture_at=-1
var webcam_timer=null
var fullscreen_visual=false
var stage_top=-1.0
var draw_skeleton=true
var enabled=false
var mode="off"
var demo_time=0.0
var tracking_live=false
var view_mode="body"
var view_candidate="body"
var view_candidate_count=0
var demo_move="Side step"
const DanceLibrary=preload("res://scripts/DanceLibrary.gd")
var request_node=null
var pending=false
var poll_attempts=0
var last_poll=0
var performance_hz=4
var performance_suspended=false
var request_epoch=0
var last_pose=0
const DROPOUT_HOLD_MS=750
var points=[]
var intensity=0.0
var status="OFF"
const EDGES=[[11,12],[11,13],[13,15],[12,14],[14,16],[11,23],[12,24],[23,24],[23,25],[25,27],[24,26],[26,28]]
func _ready():
    mouse_filter=Control.MOUSE_FILTER_IGNORE
    set_anchors_and_margins_preset(Control.PRESET_WIDE)
    _reset_pose_request()
    set_process(mode!="off" and not performance_suspended)
    webcam_timer=Timer.new()
    webcam_timer.wait_time=2.0
    add_child(webcam_timer)
    webcam_timer.connect("timeout",self,"_check_webcam")
    webcam_timer.start()
    call_deferred("_check_webcam")
func _reset_pose_request():
    # A distinct node/generation prevents a completion queued before a pause
    # from becoming a fresh pose after quality or the owner's mode changes.
    emit_signal("gesture_tracking_lost","source_reset")
    request_epoch+=1
    pending=false
    if request_node!=null:
        request_node.cancel_request()
        request_node.queue_free()
        request_node=null
    if not is_inside_tree():return
    request_node=HTTPRequest.new()
    request_node.timeout=2.0
    request_node.body_size_limit=262144
    add_child(request_node)
    request_node.connect("request_completed",self,"_completed",[request_epoch])
func set_performance_budget(hz):
    if not typeof(hz) in [TYPE_INT,TYPE_REAL] or not hz in [0,2,4]:return false
    if performance_hz==int(hz):return true
    var was_suspended=performance_suspended
    performance_hz=int(hz)
    performance_suspended=performance_hz==0
    _reset_pose_request()
    last_poll=0
    if performance_suspended or was_suspended:
        points=[]
        tracking_live=false
        last_pose=0
        view_mode="body"
        view_candidate="body"
        view_candidate_count=0
    set_process(enabled and not performance_suspended)
    if mode=="off":_status("OFF")
    elif performance_suspended:_status("PAUSED FOR AUDIO")
    elif mode=="demo":_status("DEMO DANCER")
    elif was_suspended or not tracking_live:_status("WAITING FOR KINEGRA")
    update()
    return true
func _poll_interval_ms():
    return int(1000/performance_hz) if performance_hz>0 else 0
func _check_webcam():
    var connected=false
    if Engine.has_singleton("ShieldAmpTokenStore"):
        var platform=Engine.get_singleton("ShieldAmpTokenStore")
        connected=_platform_webcam_connected(platform)
    set_webcam_connected(connected)
func _platform_webcam_connected(platform):
    if platform==null:return false
    # Godot 3 JNISingleton does not advertise Java methods via has_method.
    # The APK DEX gate requires this packaged API; validate its return type.
    var value=platform.hasUsbWebcam()
    return typeof(value)==TYPE_BOOL and value
func set_webcam_connected(connected):
    if webcam_connected==connected: return
    webcam_connected=connected
    if not connected:emit_signal("gesture_tracking_lost","webcam_disconnected")
    if not connected and mode=="live": set_mode("off")
    emit_signal("webcam_changed",connected)
func set_enabled(value):
    set_mode("live" if value else "off")
func set_mode(value):
    if not value in ["demo","live","off"]: return
    mode=value
    display_points=[]
    last_body_height=0.0
    display_fade.reset()
    modulate.a=1.0
    enabled=mode!="off"
    set_process(enabled and not performance_suspended)
    points=[]
    tracking_live=false
    view_mode="body"
    view_candidate="body"
    view_candidate_count=0
    last_pose=0
    _reset_pose_request()
    last_poll=0
    _status("OFF" if mode=="off" else ("PAUSED FOR AUDIO" if performance_suspended else ("DEMO DANCER" if mode=="demo" else "WAITING FOR KINEGRA")))
    update()
func _status(value):
    status=value
    _publish_status()
func _publish_status():
    var urgent=status in ["OFF","PAUSED FOR AUDIO","DEMO DANCER","KINEGRA UNAVAILABLE","INVALID POSE DATA"]
    var value=status_presenter.update(status,OS.get_ticks_msec(),urgent)
    if presented_status!=value:
        presented_status=value
        emit_signal("status_changed",value)
func _process(_delta):
    if not enabled or performance_suspended:return
    _publish_status()
    demo_time+=clamp(_delta,0.0,0.1)
    if mode=="demo":
        _demo_pose()
        update()
        return
    var now=OS.get_ticks_msec()
    var pose_timeout=DROPOUT_HOLD_MS if status=="BODY HOLD / BRIEF DROPOUT" else 1500
    if tracking_live and now-last_pose>pose_timeout:
        tracking_live=false
        _status("WAITING FOR BODY")
        emit_signal("gesture_tracking_lost","stale_pose")
    if tracking_live:
        display_points=points.duplicate(true)
    modulate.a=display_fade.step(_delta,tracking_live)
    if not tracking_live:
        update()
    if not pending and now-last_poll>=_poll_interval_ms():
        last_poll=now
        pending=true
        poll_attempts+=1
        var err=request_node.request("http://127.0.0.1:8088/status.json",["X-ShieldCam-Visible: 0"])
        if err!=OK:
            pending=false
            _status("KINEGRA UNAVAILABLE")
func _demo_pose():
    view_mode="body"
    view_candidate="body"
    view_candidate_count=0
    points=DanceLibrary.pose(demo_time)
    demo_move=DanceLibrary.move_name(demo_time)
func _completed(result,code,_headers,body,completion_epoch=-1):
    if completion_epoch>=0 and completion_epoch!=request_epoch:return
    if performance_suspended or mode!="live":return
    pending=false
    if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
        emit_signal("gesture_tracking_lost","request_failed")
        _status("KINEGRA UNAVAILABLE")
        return
    var parsed=JSON.parse(body.get_string_from_utf8())
    if parsed.error!=OK or typeof(parsed.result)!=TYPE_DICTIONARY:
        emit_signal("gesture_tracking_lost","invalid_response")
        _status("INVALID POSE DATA")
        return
    accept_pose(parsed.result.get("pose",{}))
# An empty result can be a single missed frame. Keep the last valid pose for a
# short, bounded interval; malformed data and collapsed bodies are rejected.
func _missing_pose():
    emit_signal("gesture_tracking_lost","missing_pose")
    if tracking_live and OS.get_ticks_msec()-last_pose<=DROPOUT_HOLD_MS:
        _status("BODY HOLD / BRIEF DROPOUT")
    else:
        tracking_live=false
        points=[]
        _status("WAITING FOR BODY")
    update()
    return false
func _select_view(candidate):
    if candidate != view_candidate:
        view_candidate=candidate
        view_candidate_count=1
    else:
        view_candidate_count+=1
    if view_candidate_count>=3:
        view_mode=candidate

func accept_pose(pose):
    # Recognition never consumes a held/demo/inferred pose. Only the raw
    # identified sample below is eligible; visual dropout hold stays separate.
    if performance_suspended:return false
    if typeof(pose)!=TYPE_DICTIONARY or not pose.get("enabled",false):
        emit_signal("gesture_tracking_lost","disabled_pose")
        tracking_live=false
        points=[]
        _status("ENABLE BODY TRACKING IN KINEGRA")
        update()
        return false
    if int(pose.get("ageMs",-1))<0 or int(pose.get("ageMs",-1))>1200:
        return _missing_pose()
    var incoming=pose.get("landmarks",[])
    if typeof(incoming)!=TYPE_ARRAY or incoming.size()<29 or incoming.size()>64:
        return _missing_pose()
    var clean=[]
    for item in incoming:
        if typeof(item)!=TYPE_ARRAY or item.size()<3:
            tracking_live=false
            points=[]
            emit_signal("gesture_tracking_lost","invalid_pose")
            _status("INVALID POSE DATA")
            update()
            return false
        for value in item.slice(0,2):
            if not typeof(value) in [TYPE_INT,TYPE_REAL]:
                tracking_live=false
                points=[]
                emit_signal("gesture_tracking_lost","invalid_pose")
                _status("INVALID POSE DATA")
                update()
                return false
        var x=float(item[0]);var y=float(item[1]);var confidence=float(item[2])
        if is_nan(x) or is_inf(x) or is_nan(y) or is_inf(y) or is_nan(confidence) or is_inf(confidence):
            tracking_live=false
            points=[]
            emit_signal("gesture_tracking_lost","invalid_pose")
            _status("INVALID POSE DATA")
            update()
            return false
        clean.append([clamp(x,0.0,1.0),clamp(y,0.0,1.0),clamp(confidence,0.0,1.0)])
    _emit_gesture_sample(clean,pose)
    var torso=0
    for index in [11,12,23,24]:
        if clean[index][2]>=0.5: torso+=1
    if torso<3:
        # Kinegra must actually return a face; no separate face detector is implied.
        var eye_span=Vector2(clean[2][0]-clean[5][0],clean[2][1]-clean[5][1]).length()
        if clean[0][2]>=0.6 and clean[2][2]>=0.6 and clean[5][2]>=0.6 and eye_span>=0.015:
            points=clean
            tracking_live=true
            last_pose=OS.get_ticks_msec()-int(pose.get("ageMs",0))
            _select_view("face")
            _status("FACE LIVE")
            update()
            return true
        return _missing_pose()
    # Reject collapsed detections without requiring visible arms or legs.
    var shoulders=Vector2(clean[11][0]-clean[12][0],clean[11][1]-clean[12][1]).length()
    var hips=Vector2(clean[23][0]-clean[24][0],clean[23][1]-clean[24][1]).length()
    var upper=Vector2((clean[11][0]+clean[12][0])*0.5,(clean[11][1]+clean[12][1])*0.5)
    var lower=Vector2((clean[23][0]+clean[24][0])*0.5,(clean[23][1]+clean[24][1])*0.5)
    var height=upper.distance_to(lower)
    var profile=last_body_height>0.0 and height>.08 and height>last_body_height*.5 and height<last_body_height*1.6 and max(shoulders,hips)>.006 and torso==4
    if height<0.045 or (max(shoulders,hips)<0.035 and not profile):
        points=[]
        tracking_live=false
        _status("WAITING FOR BODY")
        update()
        return false
    if max(shoulders,hips)>=.035:last_body_height=height
    var legs_visible=0
    for joint in [25,26,27,28]:
        if clean[joint][2]>=0.5: legs_visible+=1
    _select_view("portrait" if legs_visible<=2 else "body")
    var demo=DanceLibrary.pose(demo_time)
    var scale=clamp(height/0.29,0.35,2.5)
    var partial=false
    # Infer one missing shoulder or hip from the opposite side, preserving
    # the live anchor on that side and matching the demo torso scale.
    for pair in [[11,12],[12,11],[23,24],[24,23]]:
        var joint=pair[0]
        var anchor=pair[1]
        if clean[joint][2]<0.5 and clean[anchor][2]>=0.5:
            clean[joint]=[clamp(clean[anchor][0]+(demo[joint][0]-demo[anchor][0])*scale,0.0,1.0),clamp(clean[anchor][1]+(demo[joint][1]-demo[anchor][1])*scale,0.0,1.0),1.0]
            partial=true
    # Build each missing segment from its nearest tracked or synthesized parent.
    for chain in [[11,13,15],[12,14,16],[23,25,27],[24,26,28]]:
        for i in [1,2]:
            var parent=chain[i-1]
            var joint=chain[i]
            if clean[joint][2]<0.5 and clean[parent][2]>=0.5:
                clean[joint]=[clamp(clean[parent][0]+(demo[joint][0]-demo[parent][0])*scale,0.0,1.0),clamp(clean[parent][1]+(demo[joint][1]-demo[parent][1])*scale,0.0,1.0),1.0]
                partial=true
    points=clean
    tracking_live=true
    # Preserve the source frame time: polling the same older sample must not
    # repeatedly reset the dropout clock.
    last_pose=OS.get_ticks_msec()-int(pose.get("ageMs",0))
    _status("BODY LIVE / PORTRAIT" if legs_visible<=2 else ("BODY LIVE / DEMO LIMBS" if partial else "BODY LIVE"))
    update()
    return true
func _draw():
    if not enabled or performance_suspended or not draw_skeleton or (display_points.size()<29 if mode=="live" else points.size()<29): return
    var rendered=display_points if mode=="live" else points
    if rendered.size()<29:return
    var size=rect_size
    var box=preload("res://scripts/StageLayout.gd").avatar_rect(size,fullscreen_visual,false,0,view_mode,stage_top)
    var scale=box.size.x
    var offset=box.position
    var thickness=3.0+clamp(intensity,0.0,1.0)*6.0
    if rendered[0][2]>=0.5:
        var head=offset+Vector2(1.0-rendered[0][0],rendered[0][1])*scale
        draw_circle(head,scale*0.055,Color(0.92,0.16,0.84,0.33))
        draw_arc(head,scale*0.045,0,TAU,32,Color(0.25,0.98,1.0,0.9),thickness,true)
    for edge in EDGES:
        var a=rendered[edge[0]];var b=rendered[edge[1]]
        if a[2]<0.5 or b[2]<0.5: continue
        var p=offset+Vector2(1.0-a[0],a[1])*scale
        var q=offset+Vector2(1.0-b[0],b[1])*scale
        draw_line(p,q,Color(0.95,0.08,0.8,0.14),thickness*4.0,true)
        draw_line(p,q,Color(0.10,0.95,0.95,0.85),thickness,true)
        draw_circle(p,thickness*1.6,Color(0.95,0.45,0.95,0.7))

func _emit_gesture_sample(raw_points,pose):
    if mode!="live" or not webcam_connected or raw_points.size()!=33:
        emit_signal("gesture_tracking_lost","unidentified_or_stale_pose");return
    var values=[pose.get("sourceEpoch",-1),pose.get("frame",-1),pose.get("ageMs",-1)]
    for value in values:
        if not typeof(value) in [TYPE_INT,TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)) or value<0 or value>9007199254740991 or floor(float(value))!=float(value):
            emit_signal("gesture_tracking_lost","unidentified_or_stale_pose");return
    if values[2]>500:
        emit_signal("gesture_tracking_lost","unidentified_or_stale_pose");return
    var captured=OS.get_ticks_msec()-int(values[2])
    if captured<0:return
    if values[0]!=_gesture_source_epoch:
        _gesture_source_epoch=values[0];_gesture_source_frame=-1;_gesture_capture_at=-1
    if values[1]<=_gesture_source_frame or captured<=_gesture_capture_at:return
    _gesture_source_frame=values[1];_gesture_capture_at=captured
    emit_signal("gesture_sample",raw_points.duplicate(true),values[0],values[1],captured)
