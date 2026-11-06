extends Reference
# Screen-plane puppet proportions, not reconstructed depth or anatomical tracking.
static func point(item):
    return Vector3((0.5-float(item[0]))*4.0,(0.5-float(item[1]))*4.0,0.0)
static func valid(item):
    if typeof(item)!=TYPE_ARRAY or item.size()<3:return false
    for value in item.slice(0,2):
        if not typeof(value) in [TYPE_INT,TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)):return false
    return float(item[2])>=0.5 and float(item[0])>=-0.05 and float(item[0])<=1.05 and float(item[1])>=-0.05 and float(item[1])<=1.05
static func layout(points,calibrated_unit=0.0):
    if typeof(points)!=TYPE_ARRAY or points.size()<29:return {}
    for index in [11,12,23,24]:
        if not valid(points[index]):return {}
    var shoulder=(point(points[11])+point(points[12]))*0.5
    var hip=(point(points[23])+point(points[24]))*0.5
    var span=(point(points[11])-point(points[12])).length()
    var body=shoulder-hip
    var profile=calibrated_unit>=0.30 and calibrated_unit<=1.40 and span>=.024 and span<calibrated_unit*.70 and body.length()>=calibrated_unit*.55 and body.length()<=calibrated_unit*3.2
    if not profile and (span<0.20 or span>2.4 or body.length()<span*0.45 or body.length()>span*3.2):return {}
    var unit=calibrated_unit if profile else clamp(span,0.30,1.40)
    var up=body.normalized()
    var right=Vector3(up.y,-up.x,0.0)
    var length=clamp(body.length(),unit*0.90,unit*2.0)
    var result={"unit":unit,"shoulder":shoulder,"up":up,"right":right,"torso_center":shoulder-up*length*0.5,"torso_size":Vector3(unit*0.85,length*1.04,unit*0.60),"head_valid":false}
    if profile:
        var direction=-1.0 if float(points[0][0])>(float(points[11][0])+float(points[12][0]))*.5 else 1.0
        result["profile_yaw"]=direction*min(1.2,acos(clamp(span/unit,0.0,1.0)))
    if not valid(points[0]):return result
    var relative=point(points[0])-shoulder
    var horizontal=relative.dot(right)/unit
    var vertical=relative.dot(up)/unit
    if vertical<0.15 or vertical>2.5 or abs(horizontal)>1.5:return result
    result["head_valid"]=true
    result["head_local"]=Vector2(clamp(horizontal,-0.35,0.35),0.80)
    result["head_size"]=Vector3(unit*0.97,unit*1.06,unit*0.78)
    return result

# Face-only mode uses observed nose/eyes, with no invented body or old pose.
static func face_layout(points):
    if typeof(points)!=TYPE_ARRAY or points.size()<29:return {}
    for index in [0,2,5]:
        if not valid(points[index]) or float(points[index][2])<0.6:return {}
    var eye_line=point(points[5])-point(points[2])
    var span=eye_line.length()
    if span<0.06 or span>1.6:return {}
    if eye_line.x<0:eye_line=-eye_line
    var right=eye_line.normalized()
    var up=Vector3(-right.y,right.x,0.0)
    var unit=clamp(span*3.2,0.30,1.40)
    var center=point(points[0])
    return {"face_only":true,"head_valid":true,"unit":unit,"shoulder":center-up*unit*0.8,"right":right,"up":up,"head_local":Vector2(0,0.8),"head_size":Vector3(unit*0.97,unit*1.06,unit*0.78)}
