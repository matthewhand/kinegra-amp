extends SceneTree
var failures=[]
func check(ok,label):
    print("ADAPTIVE_BACKGROUND_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var viewport=Viewport.new();viewport.size=Vector2(96,64);viewport.usage=Viewport.USAGE_2D;viewport.render_target_update_mode=Viewport.UPDATE_ALWAYS
    get_root().add_child(viewport)
    var rect=ColorRect.new();rect.rect_size=Vector2(96,64)
    var material=ShaderMaterial.new();material.shader=load("res://shaders/adaptive_background.shader")
    material.set_shader_param("bands_0",Color(0.4,0.6,0.2,0.0));material.set_shader_param("reactive",0.7);material.set_shader_param("motion",0.0);material.set_shader_param("viewport_aspect",1.5);material.set_shader_param("visual_preset",1.0)
    rect.material=material;viewport.add_child(rect)
    yield(self,"idle_frame");yield(self,"idle_frame");yield(self,"idle_frame")
    var image=viewport.get_texture().get_data();image.lock()
    var upper=image.get_pixel(8,8);var lower=image.get_pixel(8,55)
    check(upper.a>0.99 and lower.a>0.99 and upper.b>0.01,"gles2_shader_draws_opaque_colored_background")
    check(upper!=lower,"light_tier_preserves_visible_gradient")
    image.unlock();viewport.queue_free();print("ADAPTIVE_BACKGROUND_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
