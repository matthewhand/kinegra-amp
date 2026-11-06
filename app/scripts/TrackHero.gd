extends Control
# Artwork and movement use actual selected-track/audio state, never fake FFT.
var cover = null
var playing = false
var reduced_motion = true
var bands = []
var phase = 0.0
var repaint = 0.0
var progress = 0.0
var title_label = null
var source_label = null
var state_label = null
var render_budget_fps = 30

func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    title_label = _label(27, Color(0.94,0.97,1.0))
    source_label = _label(15, Color(0.25,0.92,0.8))
    state_label = _label(17, Color(0.68,0.77,0.84))
    connect("resized", self, "_layout")
    _layout()
    set_process(render_budget_fps>0)

func set_render_budget(fps):
    if not typeof(fps) in [TYPE_INT,TYPE_REAL] or not fps in [0,10,30]:return false
    if render_budget_fps==int(fps):return true
    render_budget_fps=int(fps)
    repaint=0.0
    set_process(render_budget_fps>0)
    update() # Budget zero still draws the static cover and text.
    return true

func _label(size, color):
    var label = Label.new()
    var font = DynamicFont.new()
    font.font_data = load("res://assets/fonts/DejaVuSans.ttf")
    font.size = size
    label.add_font_override("font",font)
    label.add_color_override("font_color",color)
    label.clip_text = true
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(label)
    return label

func _layout():
    if title_label == null:
        return
    var side = min(rect_size.y * 0.78, 180.0)
    var x = side + 56.0
    var width = max(0.0, rect_size.x - x - 24.0)
    source_label.rect_position = Vector2(x,rect_size.y*0.20)
    source_label.rect_size = Vector2(width,30)
    title_label.rect_position = Vector2(x,rect_size.y*0.20+31)
    title_label.rect_size = Vector2(width,44)
    state_label.rect_position = Vector2(x,rect_size.y*0.20+78)
    state_label.rect_size = Vector2(width,30)
    update()

func set_track(texture, title, source):
    if cover==texture and title_label!=null and title_label.text==str(title) and source_label.text==str(source):return
    cover = texture
    if title_label != null:
        title_label.text = str(title)
        title_label.hint_tooltip = str(title)
        source_label.text = str(source)
    update()

func set_artwork(texture):
    if cover==texture:return
    cover=texture
    update() # Event-driven static cover remains visible at budget zero.

func set_audio_state(is_playing, actual_bands, fraction, comfort, explicit_state = ""):
    playing = is_playing
    bands = actual_bands
    progress = clamp(float(fraction),0.0,1.0)
    reduced_motion = comfort
    if state_label != null:
        state_label.text = explicit_state if not explicit_state.empty() else ("PLAYING  /  REAL AUDIO ANALYSIS" if playing else "READY  /  PRESS PLAY TO LISTEN")

func _process(delta):
    if render_budget_fps==0 or not is_visible_in_tree():
        return
    repaint += min(max(delta,0.0),0.1)
    var interval=1.0/float(render_budget_fps)
    if repaint+0.000001<interval:return
    var elapsed=repaint
    repaint=fmod(max(0.0,repaint-interval),interval)
    if playing and not reduced_motion:phase+=elapsed
    _request_repaint()

func _request_repaint():
    update()

func _draw():
    var side = min(rect_size.y * 0.78, 180.0)
    var pulse = 0.0
    if render_budget_fps>0 and playing and not bands.empty():
        pulse = clamp(float(bands[0]),0.0,1.0)
    var drift = Vector2(0, sin(phase*0.65)*2.0) if render_budget_fps>0 and playing and not reduced_motion else Vector2.ZERO
    var art = Rect2(Vector2(22,(rect_size.y-side)*0.5)+drift,Vector2(side,side))
    draw_rect(art.grow(8),Color(0.02,0.08,0.11,0.9))
    draw_rect(art.grow(8),Color(0.22,0.85,0.76,0.3+pulse*0.35),false,2)
    if cover != null:
        draw_texture_rect(cover,art,false)
    if render_budget_fps==0:return
    var x = side+56.0
    var width = max(0.0,rect_size.x-x-24)
    var y = rect_size.y*0.77
    draw_rect(Rect2(x,y+12,width,2),Color(0.2,0.3,0.37,0.7))
    draw_rect(Rect2(x,y+12,width*progress,2),Color(0.25,0.95,0.81))
