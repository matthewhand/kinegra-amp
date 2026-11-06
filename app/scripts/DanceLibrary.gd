extends Reference
# Original, lightweight 2D proxy motions; inspired by familiar dance gestures.
# These are procedural interpretations, not mocap or licensed animation clips.
const NAMES=["Side step","Sprinkler","Robot","Disco point","Floss","Macarena",
    "Arms up","Chicken dance","Twist","Air guitar","Wave","Batusi"]
const SECONDS_PER_MOVE=8.0
static func move_name(seconds):
    return NAMES[posmod(int(floor(max(0.0,seconds)/SECONDS_PER_MOVE)),NAMES.size())]
static func pose(seconds):
    var t=max(0.0,seconds)
    var current=posmod(int(floor(t/SECONDS_PER_MOVE)),NAMES.size())
    var local=fposmod(t,SECONDS_PER_MOVE)
    var a=_move(current,local)
    if local<0.75 and t>=SECONDS_PER_MOVE:
        var before=_move(posmod(current-1,NAMES.size()),SECONDS_PER_MOVE+local)
        var mix=clamp(local/0.75,0.0,1.0)
        mix=mix*mix*(3.0-2.0*mix)
        for i in range(a.size()):
            for j in range(2): a[i][j]=lerp(before[i][j],a[i][j],mix)
    return a
static func _move(which,t):
    var beat=sin(t*3.14159)
    var sway=sin(t*1.57)*0.055
    var bounce=sin(t*3.14159)*0.02
    var pose=[]
    for i in range(33): pose.append([0.5,0.5,0.0])
    pose[0]=[0.50+sway,0.15+bounce,1.0]
    pose[11]=[0.42+sway,0.29+bounce,1.0]
    pose[12]=[0.58+sway,0.29+bounce,1.0]
    pose[13]=[0.34+sway,0.42+bounce,1.0]
    pose[14]=[0.66+sway,0.42+bounce,1.0]
    pose[15]=[0.27+sway,0.36+bounce,1.0]
    pose[16]=[0.73+sway,0.36+bounce,1.0]
    pose[23]=[0.45-sway*0.4,0.58+bounce,1.0]
    pose[24]=[0.55-sway*0.4,0.58+bounce,1.0]
    pose[25]=[0.40-sway*0.5,0.75+bounce,1.0]
    pose[26]=[0.60-sway*0.5,0.75+bounce,1.0]
    pose[27]=[0.37-sway*0.6,0.95,1.0]
    pose[28]=[0.63-sway*0.6,0.95,1.0]
    if which==0: # Side step
        pose[27][0]-=0.08*max(0.0,beat)
        pose[28][0]+=0.08*max(0.0,-beat)
    elif which==1: # Sprinkler: one arm sweeps, the other stays bent.
        pose[13]=[0.31+sway,0.30+bounce,1.0]
        pose[15]=[0.20+sway,0.28+0.08*beat+bounce,1.0]
        pose[14]=[0.65+sway,0.23+bounce,1.0]
        pose[16]=[0.59+sway,0.16+bounce,1.0]
    elif which==2: # Robot: elbows square.
        pose[13]=[0.32+sway,0.29+bounce,1.0]
        pose[15]=[0.32+sway,0.39+0.05*beat+bounce,1.0]
        pose[14]=[0.68+sway,0.29+bounce,1.0]
        pose[16]=[0.68+sway,0.19+0.05*beat+bounce,1.0]
    elif which==3: # Disco point.
        pose[13]=[0.32+sway,0.20+bounce,1.0]
        pose[15]=[0.23+sway,0.08+bounce,1.0]
        pose[14]=[0.65+sway,0.47+bounce,1.0]
        pose[16]=[0.72+sway,0.56+bounce,1.0]
    elif which==4: # Floss-inspired arms swing across hips.
        pose[13]=[0.38+sway,0.48+bounce,1.0]
        pose[14]=[0.62+sway,0.48+bounce,1.0]
        pose[15]=[0.38+0.16*beat,0.61+bounce,1.0]
        pose[16]=[0.62+0.16*beat,0.61+bounce,1.0]
    elif which==5: # Macarena-inspired alternating arm positions.
        pose[13]=[0.34+sway,0.30+bounce,1.0]
        pose[14]=[0.66+sway,0.30+bounce,1.0]
        pose[15]=[0.29+sway,0.30+0.10*max(0.0,beat),1.0]
        pose[16]=[0.71+sway,0.30+0.10*max(0.0,-beat),1.0]
    elif which==6: # Arms-up party pose.
        pose[13]=[0.35+sway,0.20+bounce,1.0]
        pose[14]=[0.65+sway,0.20+bounce,1.0]
        pose[15]=[0.29+sway,0.08+bounce,1.0]
        pose[16]=[0.71+sway,0.08+bounce,1.0]
    elif which==7: # Chicken elbows.
        pose[13]=[0.30+sway,0.34+0.06*beat,1.0]
        pose[14]=[0.70+sway,0.34+0.06*beat,1.0]
        pose[15]=[0.43+sway,0.43+bounce,1.0]
        pose[16]=[0.57+sway,0.43+bounce,1.0]
    elif which==8: # Twist.
        pose[23][0]+=beat*0.06;pose[24][0]+=beat*0.06
        pose[25][0]-=beat*0.05;pose[26][0]-=beat*0.05
    elif which==9: # Air guitar.
        pose[13]=[0.35+sway,0.42,1.0];pose[15]=[0.52+sway,0.48,1.0]
        pose[14]=[0.66+sway,0.40,1.0];pose[16]=[0.58+sway,0.50+0.05*beat,1.0]
    elif which==10: # Wave overhead.
        pose[13]=[0.35+sway,0.20,1.0]
        pose[15]=[0.28+sway+0.06*beat,0.08,1.0]
    else: # Batusi-inspired raised fingers / alternating arms.
        pose[13]=[0.35+sway,0.21+0.05*beat,1.0]
        pose[14]=[0.65+sway,0.21-0.05*beat,1.0]
        pose[15]=[0.39+sway,0.12+0.05*beat,1.0]
        pose[16]=[0.61+sway,0.12-0.05*beat,1.0]
    return pose
