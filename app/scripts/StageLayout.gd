extends Reference
static func portrait_weight(size):
    return clamp((1.35-size.x/max(1.0,size.y))/0.65,0.0,1.0)
static func avatar_rect(size,fullscreen,grouped,slot,view,stage_top=-1.0):
    var side=min(size.x*0.70,size.y*0.80) if fullscreen else min(size.x*0.28,size.y*0.34)
    var center=0.5 if fullscreen else 0.76
    var top=size.y*(0.08 if fullscreen else 0.17)
    if grouped:
        side=min(size.x*0.32,size.y*0.67) if fullscreen else min(size.x*0.15,size.y*0.30)
        center=(0.5+float(slot)*0.31) if fullscreen else (0.76+float(slot)*0.145)
        top=size.y*(0.25 if fullscreen else 0.19)
    var weight=portrait_weight(size)
    if weight>0.0:
        var begin=max(size.y*0.18,stage_top)
        var available=max(100.0,size.y-begin-48.0)
        # Full bodies need larger pictures and less spread than the wide stage.
        var spread=0.27 if view=="body" else 0.30
        var tall_side=min(size.x*((0.66 if view=="body" else (0.54 if view=="portrait" else 0.42)) if grouped else 0.88),available*1.04)
        side=lerp(side,tall_side,weight)
        center=lerp(center,0.5+float(slot)*spread if grouped else 0.5,weight)
        top=lerp(top,begin+(available-side)*0.5,weight)
    return Rect2(Vector2(size.x*center-side*0.5,top),Vector2(side,side))
static func artwork_rect(size,fullscreen,stage_top=-1.0):
    var weight=portrait_weight(size)
    var center=lerp(0.5 if fullscreen else 0.76,0.5,weight)
    var side=lerp(size.x*(0.22 if fullscreen else 0.10),size.x*0.29,weight)
    var begin=max(size.y*(0.25 if fullscreen else 0.19),stage_top)
    var middle=begin+(size.y-begin-48.0)*0.5 if weight>0.0 else size.y*(0.45 if fullscreen else 0.28)
    return Rect2(Vector2(size.x*center-side*0.5,middle-side*0.5),Vector2(side,side))


static func focused_artwork_rect(size,top,bottom):
    # Centre the cover in the free canvas, independently of webcam/dancer slots.
    var height=max(0.0,bottom-top)
    var side=max(0.0,min(size.x*.72,height-16.0))
    return Rect2(Vector2((size.x-side)*.5,(top+bottom-side)*.5),Vector2(side,side))
