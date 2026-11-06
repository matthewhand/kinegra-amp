extends SceneTree
# Local offline branding acceptance, no Shield/network/audio output required.
var errors=[]
var checks=0
func verify(ok, name):
    checks+=1
    if not ok:
        errors.append(name)
        printerr("FAIL ", name)
func _init():
    call_deferred("run")
func run():
    verify(str(ProjectSettings.get_setting("application/config/name"))=="Kinegra Amp", "godot application brand")
    verify(str(ProjectSettings.get_setting("application/config/icon"))=="res://assets/branding/icon_192.png", "godot app icon")
    verify(str(ProjectSettings.get_setting("application/boot_splash/image"))=="res://assets/branding/boot_splash_1280x720.png", "boot splash path")
    var icon=load("res://assets/branding/icon_192.png")
    verify(icon != null, "icon texture imported")
    if icon!=null:
        verify(icon.get_width()==192 and icon.get_height()==192, "icon dimensions")
    var splash=load("res://assets/branding/boot_splash_1280x720.png")
    verify(splash != null, "boot splash imported")
    if splash!=null:
        verify(splash.get_width()==1280 and splash.get_height()==720, "boot splash dimensions")
    var scene=load("res://Main.tscn")
    verify(scene!=null, "main scene imported")
    if scene==null:
        print("KINEGRA_AMP_BRAND_CHECKS=",checks," FAILURES=",errors)
        quit(1)
        return
    var ui=scene.instance()
    get_root().add_child(ui)
    yield(create_timer(0.2), "timeout")
    verify(ui.name=="KinegraAmp", "root scene renamed")
    verify(ui.music_ui!=null, "music-first overlay exists")
    var emblem=ui.music_ui.root.find_node("KinegraAmpEmblem",true,false)
    verify(emblem!=null, "visible brand emblem exists")
    if emblem!=null:
        verify(emblem.texture!=null, "visible brand emblem has texture")
    var header_found=false
    var pending=[ui.music_ui.root]
    while not pending.empty():
        var node=pending.pop_back()
        if node is Label and node.text=="AMP":
            header_found=true
        for c in node.get_children():
            pending.append(c)
    verify(header_found, "correct Kinegra Amp in-app header")
    verify(ui.music_ui.library_button.text=="MUSIC ASSISTANT", "MA remains primary")
    verify(ui.music_ui.play_button.has_focus(), "remote navigation starts at Play")
    verify(not ui.offline_music.is_playing(), "branded app starts silent")
    verify(not ui.demo, "no automatic synthetic demo")
    verify(not ResourceLoader.exists("res://scripts/DeviceAcceptance.gd"),"tone fixture hook remains absent")
    ui._stop_all_music()
    print("KINEGRA_AMP_BRAND_CHECKS=",checks," FAILURES=",errors)
    quit(0 if errors.empty() else 1)
