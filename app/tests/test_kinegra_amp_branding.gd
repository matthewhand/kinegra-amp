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
    var brand=ui.music_ui.header_brand
    verify(brand is Label and brand.text=="Kinegra Amp", "complete name is one title label")
    verify(not brand.autowrap, "product name stays on one line")
    verify(ui.music_ui.library_button.text=="MUSIC ASSISTANT", "MA remains primary")
    verify(ui.music_ui.play_button.has_focus(), "remote navigation starts at Play")
    verify(not ui.offline_music.is_playing(), "branded app starts silent")
    verify(not ui.demo, "no automatic synthetic demo")
    verify(not ResourceLoader.exists("res://scripts/DeviceAcceptance.gd"),"tone fixture hook remains absent")
    ui._set_web_remote(false)
    ui.pose_visual.set_mode("off")
    ui.set_process(false)
    for size in [Vector2(1280,720),Vector2(1920,1080),Vector2(3440,1440),Vector2(960,720),Vector2(720,1280),Vector2(550,720)]:
        OS.window_size=size
        ui._apply_resolution_base()
        for large in [false,true]:
            ui.music_ui.set_tv_text_mode(large)
            for _i in range(8):yield(self,"idle_frame")
            var label=str(int(size.x))+"x"+str(int(size.y))+" large="+str(large)
            var card=ui.music_ui.header_card.get_global_rect()
            if brand.visible:
                var title_box=brand.get_global_rect()
                var font=brand.get_font("font")
                verify(title_box.size.x+1>=font.get_string_size(brand.text).x, "whole title fits "+label)
                verify(card.encloses(title_box), "title stays in header "+label)
            for button in [ui.music_ui.library_button,ui.music_ui.offline_button,ui.music_ui.queue_button,ui.music_ui.fullscreen_button,ui.music_ui.visuals_button,ui.music_ui.settings_button]:
                var box=button.get_global_rect()
                verify(box.position.x>=card.position.x and box.end.x<=card.end.x+1, "header action stays in width "+label)
                if brand.visible:verify(not box.intersects(brand.get_global_rect()), "title clear of actions "+label)
    ui._stop_all_music()
    print("KINEGRA_AMP_BRAND_CHECKS=",checks," FAILURES=",errors)
    quit(0 if errors.empty() else 1)
