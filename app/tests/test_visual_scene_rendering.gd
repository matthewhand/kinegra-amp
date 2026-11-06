extends SceneTree
var failures=[]
func check(ok,label):
    print("SCENE_RENDER_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var viewport=Viewport.new();viewport.size=Vector2(192,128);viewport.usage=Viewport.USAGE_2D;viewport.render_target_update_mode=Viewport.UPDATE_ALWAYS;get_root().add_child(viewport)
    var rect=ColorRect.new();rect.rect_size=Vector2(192,128);viewport.add_child(rect)
    for path in ["milkdrop.shader","adaptive_background.shader"]:
        var material=ShaderMaterial.new();material.shader=load("res://shaders/"+path);rect.material=material
        material.set_shader_param("viewport_aspect",1.5);material.set_shader_param("motion",0.0)
        var hashes=[]
        for preset in range(3):
            material.set_shader_param("visual_preset",float(preset));material.set_shader_param("bands_0",Color(0.3,0.4,0.2,0.2));material.set_shader_param("reactive",0.3)
            if path=="milkdrop.shader":
                material.set_shader_param("bands_1",Color(0.3,0.2,0.4,0.3));material.set_shader_param("bands_2",Color(0.2,0.4,0.2,0.2));material.set_shader_param("bands_3",Color(0.2,0.2,0.2,0.2))
            yield(create_timer(.08),"timeout")
            var active=viewport.get_texture().get_data();var active_hash=active.get_data().hex_encode().sha256_text();hashes.append(active_hash)
            yield(create_timer(.08),"timeout")
            check(viewport.get_texture().get_data().get_data().hex_encode().sha256_text()==active_hash,path+"_"+str(preset)+"_reduced_motion_freezes_phase")
            material.set_shader_param("motion",1.0);material.set_shader_param("bands_0",Color(0,0,0,0));material.set_shader_param("reactive",0.0)
            if path=="milkdrop.shader":
                for band in ["bands_1","bands_2","bands_3"]:material.set_shader_param(band,Color(0,0,0,0))
            yield(create_timer(.08),"timeout")
            var idle_hash=viewport.get_texture().get_data().get_data().hex_encode().sha256_text()
            yield(create_timer(.12),"timeout")
            check(viewport.get_texture().get_data().get_data().hex_encode().sha256_text()==idle_hash and idle_hash!=active_hash,path+"_"+str(preset)+"_silence_has_no_fake_animated_energy")
            material.set_shader_param("motion",0.0)
        check(hashes[0]!=hashes[1] and hashes[1]!=hashes[2] and hashes[0]!=hashes[2],path+"_three_presets_render_distinct_forms")
    viewport.queue_free();print("SCENE_RENDER_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
