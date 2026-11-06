extends SceneTree
func _init():call_deferred("run")
func run():
    var background=ColorRect.new();background.color=Color(0.02,0.035,0.065);background.rect_size=Vector2(960,720);get_root().add_child(background)
    var avatars=[]
    for slot in [-1,0,1]:
        var avatar=load("res://scripts/AvatarRenderer.gd").new();avatar.render_size=256;avatar.grouped=true;avatar.fullscreen_visual=true;avatar.stage_slot=slot
        get_root().add_child(avatar);avatar.set_active(true);avatar.set_style(["starlight","neon","synth"][slot+1]);avatar.set_visual_context(0,0,0,0,false)
        avatars.append(avatar)
    for name in ["full_body","seated","partial"]:
        for slot in range(3):
            var points=load("res://scripts/DanceLibrary.gd").pose(0.0)
            if slot==1 and name=="seated":
                for point in points:
                    if point[2]>=.5:point[1]+=.12
            if slot==1 and name=="partial":points[23][2]=.1
            avatars[slot].set_pose(points)
            avatars[slot]._process(1.0)
        yield(create_timer(.2),"timeout")
        var output=OS.get_environment("SHIELDAMP_AVATAR_IMAGES")
        if not output.empty():
            var image=get_root().get_texture().get_data();image.flip_y();image.save_png(output+"/anatomy_"+name+".png")
    for framing in ["body","portrait","face"]:
        for group in range(2):
            for slot in range(3):
                avatars[slot].view_mode=framing
                avatars[slot].set_style(avatars[slot].STYLES[(group*3+slot)%5])
                avatars[slot].set_visual_context(0,0,0,0,false)
                avatars[slot].set_pose(load("res://scripts/DanceLibrary.gd").pose(0.0))
                avatars[slot]._process(1.0)
            yield(create_timer(.2),"timeout")
            var output=OS.get_environment("SHIELDAMP_AVATAR_IMAGES")
            if not output.empty():
                var image=get_root().get_texture().get_data();image.flip_y();image.save_png(output+"/finish_"+framing+"_"+str(group)+".png")
    print("ANATOMY_GENERIC_VISUAL_PASS")
    quit()
