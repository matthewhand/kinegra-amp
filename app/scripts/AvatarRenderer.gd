extends Control
signal appearance_changed
# Original procedural 3D avatar. 2D Kinegra landmarks are an approximation,
# not full motion capture. No VRM assets, network or camera access.
var viewport_3d = null
var camera = null
var scene = null
var picture = null
var segments = []
var head = null
var torso = null
var neck=null
var anatomy=preload("res://scripts/AvatarAnatomy.gd")
var body_unit=0.64
var body_anchor=Vector3(0,0.84,0)
var _head_local=Vector2.ZERO
var _head_local_valid=false
var _face_neutral=0.50
var _face_yaw_neutral=0.0
var _face_neutral_valid=false
var tracking_hold=false
var calibrated_body_ratio=0.0
var tracking_fade=preload("res://scripts/TrackingFade.gd").new()
var face_details = []
var costume_parts = {}
var joints = []
var mode = "neon"
var fullscreen_visual = false
var grouped = false
var stage_slot = 0
var stage_top=-1.0
var render_size = 512
var view_mode = "body"
var active = false
var render_budget_fps = 60
var _render_elapsed = 0.0
var intensity = 0.0
var body_material = null
var joint_material = null
var last_points = []
const STYLES = ["neon", "sunset", "ice", "starlight", "synth"]
const EDGES = [[11,12],[11,13],[13,15],[12,14],[14,16],[11,23],[12,24],[23,24],[23,25],[25,27],[24,26],[26,28]]
const JOINTS = [11,12,13,14,15,16,23,24,25,26,27,28]
func _ready():
    name = "ProceduralAvatar3D"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_margins_preset(Control.PRESET_WIDE)
    viewport_3d = Viewport.new()
    viewport_3d.size = Vector2(render_size,render_size)
    viewport_3d.usage = Viewport.USAGE_3D
    viewport_3d.transparent_bg = true
    viewport_3d.render_target_update_mode = Viewport.UPDATE_DISABLED
    viewport_3d.own_world = true
    add_child(viewport_3d)
    scene = Spatial.new()
    viewport_3d.add_child(scene)
    camera = Camera.new()
    camera.projection = Camera.PROJECTION_ORTHOGONAL
    camera.size = 4.5
    camera.translation = Vector3(0,0,8)
    camera.current = true
    scene.add_child(camera)
    var light = DirectionalLight.new()
    light.rotation_degrees = Vector3(-30,-30,0)
    light.light_energy = 1.2
    scene.add_child(light)
    # A low-poly block character reads clearly across a living room while
    # retaining the live audio-reactive material used by the visualizer.
    var tube = CubeMesh.new()
    tube.size = Vector3.ONE
    var sphere = SphereMesh.new()
    sphere.radius = 0.5
    sphere.height = 1.0
    sphere.radial_segments = 12
    sphere.rings = 6
    for i in range(EDGES.size()):
        var part = MeshInstance.new()
        part.mesh = tube
        scene.add_child(part)
        segments.append(part)
    for i in range(JOINTS.size()):
        var joint = MeshInstance.new()
        joint.mesh = sphere
        joint.scale = Vector3.ONE * 0.20
        scene.add_child(joint)
        joints.append(joint)
    torso = MeshInstance.new()
    torso.mesh = tube
    scene.add_child(torso)
    neck=MeshInstance.new()
    neck.mesh=tube
    neck.visible=false
    scene.add_child(neck)
    head = MeshInstance.new()
    head.mesh = tube
    head.scale = Vector3(0.62,0.68,0.50)
    scene.add_child(head)
    # Three simple front-facing details make the avatar a character, not a
    # wireframe. They inherit the tracked head position and disappear with it.
    var face_material = SpatialMaterial.new()
    face_material.flags_unshaded = true
    face_material.albedo_color = Color(0.92, 0.99, 1.0)
    for face_part in [[-0.22, 0.12, 0.14, 0.13], [0.22, 0.12, 0.14, 0.13], [0.0, -0.21, 0.35, 0.055]]:
        var detail = MeshInstance.new()
        detail.mesh = tube
        detail.translation = Vector3(face_part[0], face_part[1], 0.51)
        detail.scale = Vector3(face_part[2], face_part[3], 0.025)
        detail.material_override = face_material
        head.add_child(detail)
        face_details.append(detail)
    # Original stage costumes, built from small meshes attached to the puppet.
    # No external character designs or textures are used.
    var gold = SpatialMaterial.new()
    gold.flags_unshaded = true
    gold.albedo_color = Color(1.0, 0.72, 0.12)
    var cyan = SpatialMaterial.new()
    cyan.flags_unshaded = true
    cyan.albedo_color = Color(0.22, 0.96, 1.0)
    var dark = SpatialMaterial.new()
    dark.flags_unshaded = true
    dark.albedo_color = Color(0.025, 0.04, 0.12)
    var star_parts = []
    for spike in [[-0.32, 0.60, -25], [0.0, 0.68, 0], [0.32, 0.60, 25]]:
        var piece = MeshInstance.new()
        piece.mesh = tube
        piece.translation = Vector3(spike[0], spike[1], 0.12)
        piece.rotation_degrees.z = spike[2]
        piece.scale = Vector3(0.18, 0.40, 0.32)
        piece.material_override = gold
        head.add_child(piece)
        star_parts.append(piece)
    for side in [-1.0, 1.0]:
        var pad = MeshInstance.new()
        pad.mesh = tube
        pad.translation = Vector3(side * 0.54, 0.34, 0.15)
        pad.rotation_degrees.z = -side * 18.0
        pad.scale = Vector3(0.28, 0.14, 0.72)
        pad.material_override = gold
        torso.add_child(pad)
        star_parts.append(pad)
    costume_parts["starlight"] = star_parts
    var synth_parts = []
    for spec in [[dark, 0.0, 0.10, 0.75, 0.30], [cyan, 0.0, 0.10, 0.62, 0.055]]:
        var piece = MeshInstance.new()
        piece.mesh = tube
        piece.translation = Vector3(spec[1], spec[2], 0.62 if spec[0] == cyan else 0.54)
        piece.scale = Vector3(spec[3], spec[4], 0.05)
        piece.material_override = spec[0]
        head.add_child(piece)
        synth_parts.append(piece)
    for side in [-1.0, 1.0]:
        var fin = MeshInstance.new()
        fin.mesh = tube
        fin.translation = Vector3(side * 0.56, 0.05, 0.0)
        fin.scale = Vector3(0.15, 0.50, 0.50)
        fin.material_override = cyan
        head.add_child(fin)
        synth_parts.append(fin)
    costume_parts["synth"] = synth_parts
    picture = TextureRect.new()
    picture.texture = viewport_3d.get_texture()
    picture.flip_v = true
    picture.expand = true
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(picture)
    _set_materials()
    _sync_render_state()
func _set_materials():
    if scene == null: return
    var primary = Color(0.04,0.85,0.95) if mode == "neon" else (Color(1.0,0.45,0.12) if mode == "sunset" else Color(0.58,0.82,1.0))
    var accent = Color(0.95,0.12,0.74) if mode == "neon" else (Color(1.0,0.83,0.25) if mode == "sunset" else Color(0.23,0.94,0.87))
    if mode=="starlight":
        primary=Color(0.34,0.18,0.64);accent=Color(1.0,0.76,0.20)
    elif mode=="synth":
        primary=Color(0.15,0.32,0.52);accent=Color(0.25,1.0,0.78)
    var shader=load("res://shaders/avatar_fusion.shader")
    body_material=ShaderMaterial.new()
    body_material.shader=shader
    body_material.set_shader_param("style_color",primary)
    body_material.set_shader_param("surface_style",float(STYLES.find(mode)))
    joint_material=ShaderMaterial.new()
    joint_material.shader=shader
    joint_material.set_shader_param("style_color",accent)
    joint_material.set_shader_param("surface_style",float(STYLES.find(mode)))
    for part in segments: part.material_override=body_material
    for joint in joints: joint.material_override=joint_material
    if head != null: head.material_override=joint_material
    if torso != null: torso.material_override=body_material
    if neck!=null:neck.material_override=body_material
    for costume in costume_parts:
        for piece in costume_parts[costume]:
            piece.visible = costume == mode
    for detail in face_details:
        detail.visible = mode != "synth"

func set_visual_context(preset,bass,mid,high,allow_motion):
    for material in [body_material,joint_material]:
        if material == null: continue
        material.set_shader_param("scene_preset",clamp(float(preset),0.0,2.0))
        material.set_shader_param("bass",clamp(float(bass),0.0,1.0))
        material.set_shader_param("mid",clamp(float(mid),0.0,1.0))
        material.set_shader_param("high",clamp(float(high),0.0,1.0))
        material.set_shader_param("motion",1.0 if allow_motion else 0.0)

func set_style(value):
    if not value in STYLES:return false
    if mode==value:return true
    mode=value
    _set_materials()
    emit_signal("appearance_changed")
    return true
func set_render_budget(fps):
    if not typeof(fps) in [TYPE_INT,TYPE_REAL] or not fps in [0,15,30,60]:return false
    if render_budget_fps!=int(fps):
        render_budget_fps=int(fps)
        _render_elapsed=0.0
    _sync_render_state()
    return true
func _sync_render_state():
    var rendering=active and not last_points.empty() and render_budget_fps>0
    visible=rendering
    if scene!=null: scene.visible=rendering
    if viewport_3d!=null:
        if tracking_hold:
            viewport_3d.render_target_update_mode=Viewport.UPDATE_DISABLED
        elif not rendering or render_budget_fps==60:
            var mode_value=Viewport.UPDATE_ALWAYS if rendering else Viewport.UPDATE_DISABLED
            if viewport_3d.render_target_update_mode!=mode_value:viewport_3d.render_target_update_mode=mode_value
        elif viewport_3d.render_target_update_mode==Viewport.UPDATE_ALWAYS:
            viewport_3d.render_target_update_mode=Viewport.UPDATE_DISABLED
    if not rendering:_render_elapsed=0.0
    if is_processing()!=rendering: set_process(rendering)
func _clear_pose():
    last_points=[]
    _head_local_valid=false
    _face_neutral=0.50
    _sync_render_state()
    return false
func set_active(value):
    var changed=active!=bool(value)
    active=bool(value)
    if not active:
        last_points=[]
        tracking_hold=false
        tracking_fade.reset()
        _face_neutral_valid=false
    _sync_render_state()
    if changed:emit_signal("appearance_changed")
func _point(item):
    return Vector3((0.5-float(item[0]))*4.0,(0.5-float(item[1]))*4.0,0.0)
func recenter_head():
    _face_neutral_valid=false
    head.rotation=Vector3.ZERO

func set_tracked_pose(points,available):
    var rig=anatomy.layout(points) if available else {}
    var hint=0.0
    if available and typeof(points)==TYPE_ARRAY and points.size()>=29:
        var body_height=(anatomy.point(points[11])+anatomy.point(points[12])-anatomy.point(points[23])-anatomy.point(points[24])).length()*.5
        if not rig.empty() and body_height>.20:
            calibrated_body_ratio=clamp(rig.unit/body_height,.25,1.2)
        elif calibrated_body_ratio>0.0:
            hint=clamp(body_height*calibrated_body_ratio,.30,1.40)
            rig=anatomy.layout(points,hint)
    if rig.empty() and available and view_mode=="face":rig=anatomy.face_layout(points)
    if rig.empty() or not rig.get("head_valid",false):
        if not tracking_hold:
            tracking_hold=true
            _sync_render_state()
        return false
    tracking_hold=false
    tracking_fade.was_live=true
    if tracking_fade.alpha==0.0 and last_points.empty():tracking_fade.alpha=0.0
    return set_pose(points,hint)

func set_pose(points,body_hint=0.0):
    if typeof(points)!=TYPE_ARRAY or points.size()<29:
        return _clear_pose()
    for item in points:
        if typeof(item)!=TYPE_ARRAY or item.size()<3:
            return _clear_pose()
        for value in item.slice(0,2):
            if not typeof(value) in [TYPE_REAL,TYPE_INT] or is_nan(float(value)) or is_inf(float(value)):
                return _clear_pose()
    last_points=points
    var rig=anatomy.layout(points,body_hint)
    if rig.empty() and view_mode=="face":rig=anatomy.face_layout(points)
    if rig.empty():return _clear_pose()
    if not rig.empty():
        body_unit=rig.unit
        body_anchor=rig.shoulder
    _sync_render_state()
    for i in range(EDGES.size()):
        var edge=EDGES[i]
        var a=points[edge[0]]
        var b=points[edge[1]]
        var part=segments[i]
        part.visible=not rig.get("face_only",false) and float(a[2])>=0.5 and float(b[2])>=0.5
        if not part.visible: continue
        var first=_point(a)
        var second=_point(b)
        var difference=second-first
        var length=difference.length()
        if length<0.0001:
            part.visible=false
            continue
        var up=difference/length
        var reference=Vector3(0,0,1)
        var right=up.cross(reference).normalized()
        var forward=right.cross(up).normalized()
        var radius=((0.28 if i in [0,4,5,6,7] else 0.22)+clamp(intensity,0.0,1.0)*0.025)*body_unit/0.64
        part.transform=Transform(Basis(right*radius,up*length,forward*radius), (first+second)*0.5)
    for i in range(JOINTS.size()):
        var joint=joints[i]
        var data=points[JOINTS[i]]
        joint.visible=not rig.get("face_only",false) and float(data[2])>=0.5
        if joint.visible:
            joint.translation=_point(data)
            joint.scale=Vector3.ONE*0.20*body_unit/0.64
    torso.visible=not rig.empty() and not rig.get("face_only",false)
    neck.visible=false
    if torso.visible:
        torso.translation=rig.torso_center
        torso.scale=rig.torso_size
        torso.rotation.z=atan2(rig.up.y,rig.up.x)-PI*0.5
        torso.rotation.y=lerp(torso.rotation.y,float(rig.get("profile_yaw",0.0)),.35)
    head.visible=not rig.empty() and rig.get("head_valid",false)
    if head.visible:
        _head_local=rig.head_local if not _head_local_valid else _head_local.linear_interpolate(rig.head_local,0.35)
        _head_local_valid=true
        head.scale=rig.head_size
        head.translation=rig.shoulder+rig.right*_head_local.x*rig.unit+rig.up*_head_local.y*rig.unit
        # Eye-line provides 2D head roll only; no inferred depth or facial expressions.
        if float(points[2][2])>=0.5 and float(points[5][2])>=0.5:
            var eye_line=_point(points[5])-_point(points[2])
            if eye_line.length()>=0.03:
                if eye_line.x<0: eye_line=-eye_line
                head.rotation.z=clamp(atan2(eye_line.y,eye_line.x),-0.75,0.75)
                # A subtle approximation from the nose offset; this is not 3D face capture.
                var midpoint=(float(points[2][0])+float(points[5][0]))*0.5
                var width=abs(float(points[2][0])-float(points[5][0]))
                var yaw=(float(points[0][0])-midpoint)/max(width,0.01)
                # Approximate pitch from the nose/eye ratio, never tracking depth.
                # Only small neutral variations calibrate; looking up cannot move
                # the head away from its neck or teach a large tilt as neutral.
                var face_ratio=(float(points[0][1])-(float(points[2][1])+float(points[5][1]))*.5)/max(width,0.01)
                if not _face_neutral_valid:
                    _face_neutral=face_ratio
                    _face_yaw_neutral=yaw
                    _face_neutral_valid=true
                if abs(face_ratio-_face_neutral)<0.12:_face_neutral=lerp(_face_neutral,face_ratio,0.02)
                # Screen positions are mirrored, so horizontal turn follows the
                # same mirror rather than fighting the character's movement.
                head.rotation.y=lerp(head.rotation.y,clamp(-(yaw-_face_yaw_neutral)*1.3,-0.65,0.65),0.35)
                var pitch=clamp((face_ratio-_face_neutral)*0.8,-0.45,0.45)
                head.rotation.x=lerp(head.rotation.x,pitch,0.35)
            else:
                head.rotation.z=0.0
                if rig.has("profile_yaw"):head.rotation.y=lerp(head.rotation.y,float(rig.profile_yaw),.35)
                # Keep the last valid face rotation when eyes overlap in profile.
        else:
            head.rotation.z=0.0
            head.rotation.y=0.0
            head.rotation.x=0.0
        var first=rig.shoulder
        var second=head.translation-head.transform.basis.y*0.48
        var difference=second-first
        if not rig.get("face_only",false) and difference.length()>0.001:
            var neck_up=difference.normalized()
            var neck_right=neck_up.cross(Vector3(0,0,1)).normalized()
            var neck_forward=neck_right.cross(neck_up).normalized()
            neck.transform=Transform(Basis(neck_right*rig.unit*0.20,neck_up*difference.length(),neck_forward*rig.unit*0.20),(first+second)*0.5)
            neck.visible=true
    else:_head_local_valid=false
    return true
func _request_budget_frame():
    viewport_3d.render_target_update_mode=Viewport.UPDATE_ONCE
func _process(_delta):
    if picture == null or not active or last_points.empty() or render_budget_fps==0:return
    modulate.a=tracking_fade.step(_delta,not tracking_hold) if tracking_hold or tracking_fade.was_live else 1.0
    if tracking_hold:
        viewport_3d.render_target_update_mode=Viewport.UPDATE_DISABLED
        if modulate.a<=0.0:set_process(false)
        var frozen_box=preload("res://scripts/StageLayout.gd").avatar_rect(rect_size,fullscreen_visual,grouped,stage_slot,view_mode,stage_top)
        picture.rect_position=frozen_box.position
        picture.rect_size=frozen_box.size
        return
    var frame_delta=_delta
    if render_budget_fps<60:
        _render_elapsed+=clamp(_delta,0.0,0.25)
        var interval=1.0/float(render_budget_fps)
        if _render_elapsed+0.000001<interval:return
        frame_delta=_render_elapsed
        _render_elapsed=fmod(max(0.0,_render_elapsed-interval),interval)
        # Request at most one GPU frame per callback. A delayed frame never
        # creates a burst of catch-up renders or an UPDATE_ALWAYS interval.
        _request_budget_frame()
    # Camera framing is smoothed to avoid abrupt jumps on intermittent limbs.
    # Normalize framing around the same shoulder anchor/body unit for tracked
    # and synthetic puppets; a seated/cropped camera view cannot sink the torso.
    var framing_scale=body_unit/0.64
    var target_size=4.5*framing_scale
    var target_y=body_anchor.y-0.84*framing_scale
    var target_x=body_anchor.x
    if view_mode in ["portrait", "face"] and head != null and head.visible:
        target_size=(2.7 if view_mode=="portrait" else 1.35)*framing_scale
        target_x=head.translation.x
        target_y=head.translation.y-0.45*framing_scale if view_mode=="portrait" else head.translation.y
    var blend=clamp(frame_delta*4.0,0.0,1.0)
    camera.size=lerp(camera.size,target_size,blend)
    camera.translation.x=lerp(camera.translation.x,target_x,blend)
    camera.translation.y=lerp(camera.translation.y,target_y,blend)
    var box=preload("res://scripts/StageLayout.gd").avatar_rect(rect_size,fullscreen_visual,grouped,stage_slot,view_mode,stage_top)
    picture.rect_position=box.position
    picture.rect_size=box.size
