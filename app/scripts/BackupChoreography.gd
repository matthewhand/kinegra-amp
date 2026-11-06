extends Reference
# Original procedural move families. Tempo drives movement speed, not just tint.
const Library=preload("res://scripts/DanceLibrary.gd")
const FAMILIES={"gentle":[0],"slow":[0,8,9],"medium":[1,5,10],"fast":[2,4,7]}
var position=0.0
var rate=0.5
var family="gentle"
var kind="none"
var enabled=false
var transition=1.0
var from_poses=[]
func reset():
    position=0.0;rate=0.5;family="gentle";kind="none";enabled=false;transition=1.0;from_poses=[]
func step(delta,tempo,live,reduced_motion,manual_bpm=0.0):
    if not live:
        reset()
        return
    enabled=true
    var target_rate=1.8
    var next_family="medium"
    kind="default_dance"
    if typeof(manual_bpm) in [TYPE_INT,TYPE_REAL] and not is_nan(float(manual_bpm)) and not is_inf(float(manual_bpm)) and manual_bpm>=30.0 and manual_bpm<=240.0:
        kind="configured_metronome"
        target_rate=float(manual_bpm)/60.0
        next_family="slow" if manual_bpm<90.0 else ("medium" if manual_bpm<140.0 else "fast")
    elif tempo.get("kind")=="estimated_onsets":
        kind="estimated_onsets"
        target_rate=float(tempo.bpm)/60.0
        next_family=tempo.family
    var dt=clamp(float(delta),0.0,0.25)
    rate=lerp(rate,target_rate,clamp(dt*2.0,0.0,1.0))
    if reduced_motion:return
    if family!=next_family:
        from_poses=[pose(0),pose(1)]
        transition=0.0
        family=next_family
    transition=min(1.0,transition+dt/0.5)
    position+=rate*dt
    if kind=="estimated_onsets":
        var error=fposmod(float(tempo.phase)-fposmod(position,1.0)+0.5,1.0)-0.5
        position+=clamp(error*dt*1.5,-0.025,0.025)
func pose(slot):
    if not enabled:return []
    var offset=0.25 if slot==0 else 0.75
    var beat=position+offset
    var choices=FAMILIES.get(family,FAMILIES.gentle)
    var phrase=int(floor(beat/8.0))
    var selected=choices[posmod(phrase+slot,choices.size())]
    var result=Library._move(selected,beat)
    var local=fposmod(beat,8.0)
    if local<0.5:
        var previous=Library._move(choices[posmod(phrase+slot-1,choices.size())],beat)
        var blend=local/0.5;blend=blend*blend*(3.0-2.0*blend)
        for index in range(result.size()):
            for axis in range(2):result[index][axis]=lerp(previous[index][axis],result[index][axis],blend)
    if family=="gentle":
        var rest=Library._move(0,0.0)
        for index in range(result.size()):
            for axis in range(2):result[index][axis]=lerp(rest[index][axis],result[index][axis],0.35)
    if transition<1.0 and from_poses.size()>slot and from_poses[slot].size()==result.size():
        var blend=transition*transition*(3.0-2.0*transition)
        for index in range(result.size()):
            for axis in range(2):result[index][axis]=lerp(from_poses[slot][index][axis],result[index][axis],blend)
    return result
