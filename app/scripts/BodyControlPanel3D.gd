extends CanvasLayer
# Original lightweight 3D controls. Detection lives in BodyControlPanelPolicy.
var app=null
var panel_root=null
var view=null
var picture=null
var scene=null
var buttons=[]
var labels=[]
var cursors=[]
var feedback_label=null
var focused=1
var open=false
var accept_held=false
var elapsed=0.0
var policy=preload("res://scripts/BodyControlPanelPolicy.gd")
func _ready():
    layer=15
    panel_root=Control.new();panel_root.set_anchors_and_margins_preset(Control.PRESET_WIDE);add_child(panel_root)
    var dim=ColorRect.new();dim.color=Color(.015,.025,.045,.90);dim.set_anchors_and_margins_preset(Control.PRESET_WIDE);panel_root.add_child(dim)
    var heading=Label.new();heading.text="CROSSED-ARMS CONTROLS";heading.align=Label.ALIGN_CENTER;heading.anchor_left=.04;heading.anchor_right=.96;heading.anchor_top=.08;heading.margin_bottom=48;_font(heading,30);panel_root.add_child(heading)
    view=Viewport.new();view.size=Vector2(640,480);view.usage=Viewport.USAGE_3D;view.own_world=true;view.transparent_bg=true;view.render_target_update_mode=Viewport.UPDATE_DISABLED;add_child(view)
    scene=Spatial.new();view.add_child(scene)
    var camera=Camera.new();camera.projection=Camera.PROJECTION_ORTHOGONAL;camera.size=2.0;camera.translation=Vector3(0,0,4);camera.current=true;scene.add_child(camera)
    var light=DirectionalLight.new();light.rotation_degrees=Vector3(-25,-20,0);scene.add_child(light)
    var captions=["PREV","PLAY\nPAUSE","NEXT","STOP","CLOSE"]
    for index in range(captions.size()):
        var box=MeshInstance.new();var mesh=CubeMesh.new();mesh.size=Vector3(.52,.30,.12);box.mesh=mesh
        var material=SpatialMaterial.new();material.albedo_color=Color(.07,.32,.37);material.emission_enabled=true;material.emission=Color(.02,.13,.16);box.material_override=material
        box.translation=_world(policy.CENTERS[index]);box.rotation_degrees=Vector3(-6,-10 if index%2==0 else 10,0);scene.add_child(box);buttons.append(box)
        var text_view=Viewport.new();text_view.size=Vector2(256,144);text_view.transparent_bg=true;text_view.render_target_update_mode=Viewport.UPDATE_ONCE;add_child(text_view)
        var label=Label.new();label.text=captions[index];label.align=Label.ALIGN_CENTER;label.valign=Label.VALIGN_CENTER;label.rect_size=Vector2(256,144);_font(label,56);text_view.add_child(label)
        var sprite=Sprite3D.new();sprite.texture=text_view.get_texture();sprite.pixel_size=.0019;sprite.flip_v=true;sprite.rotation=box.rotation;sprite.translation=box.translation+box.transform.basis.z*.075;scene.add_child(sprite);labels.append(sprite)
    for index in range(2):
        var cursor=MeshInstance.new();var ball=SphereMesh.new();ball.radius=.045;ball.height=.09;ball.radial_segments=12;ball.rings=6;cursor.mesh=ball
        var material=SpatialMaterial.new();material.albedo_color=Color(.98,.68,.28) if index==0 else Color(.25,.95,.83);material.flags_unshaded=true;cursor.material_override=material;scene.add_child(cursor);cursors.append(cursor)
    picture=TextureRect.new();picture.texture=view.get_texture();picture.expand=true;picture.flip_v=true;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.anchor_left=.035;picture.anchor_right=.965;picture.anchor_top=.20;picture.anchor_bottom=.79;panel_root.add_child(picture)
    feedback_label=Label.new();feedback_label.anchor_left=.06;feedback_label.anchor_right=.94;feedback_label.anchor_top=.81;feedback_label.anchor_bottom=.96;feedback_label.autowrap=true;feedback_label.align=Label.ALIGN_CENTER;feedback_label.valign=Label.VALIGN_CENTER;_font(feedback_label,27);panel_root.add_child(feedback_label)
    panel_root.hide();set_process(false)
func _font(label,size):
    var font=DynamicFont.new();font.font_data=load("res://assets/fonts/DejaVuSans.ttf");font.size=size;label.add_font_override("font",font)
func _world(point):return Vector3((point.x-.5)*2.6,(.5-point.y)*2.0,0)
func sync(state):
    open=state.panel_open
    panel_root.visible=open
    if not open:
        view.render_target_update_mode=Viewport.UPDATE_DISABLED
        set_process(false)
        return
    feedback_label.text=state.feedback+"\nRemote: Left / Right selects, OK activates, Back closes"
    for index in range(buttons.size()):
        var hot=index==state.hover or (state.hover<0 and index==focused)
        buttons[index].scale=Vector3.ONE*(1.09 if hot else 1.0)
        buttons[index].material_override.albedo_color=Color(.92,.57,.20) if hot else Color(.07,.32,.37)
    for index in range(cursors.size()):
        cursors[index].visible=state.hands.size()==2
        if state.hands.size()==2:cursors[index].translation=_world(state.hands[index])+Vector3(0,0,.20)
    view.render_target_update_mode=Viewport.UPDATE_ONCE
    set_process(true)
func _process(delta):
    elapsed+=delta
    if elapsed<.10:return
    elapsed=0.0
    if open and app!=null and app.visual_quality_level>0:view.render_target_update_mode=Viewport.UPDATE_ONCE
func route(event):
    if not open:
        accept_held=false
        return false
    if event.is_action_released("ui_accept"):
        accept_held=false
        return true
    if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index==1):
        app._close_body_control_panel();return true
    if event.is_action_pressed("ui_left",true):
        focused=posmod(focused-1,5)
        return true
    if event.is_action_pressed("ui_right",true):
        focused=(focused+1)%5
        return true
    if event.is_action_pressed("ui_up",true):
        focused=max(0,focused-3)
        return true
    if event.is_action_pressed("ui_down",true):
        focused=min(4,focused+3)
        return true
    if event.is_action_pressed("ui_accept"):
        if accept_held:return true
        accept_held=true
        app._perform_panel_action(policy.ACTIONS[focused]);return true
    return false
