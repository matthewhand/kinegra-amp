extends SceneTree
var checks=0
var failures=[]
var capture=false
func ck(ok,name):
    checks+=1
    if not ok:
        failures.append(name)
        printerr("ARTWORK_OFF_FAIL_",name)
func _init():
    capture="--capture-artwork" in OS.get_cmdline_args()
    call_deferred("run")
func _capture(name):
    var pixels=get_root().get_texture().get_data()
    pixels.flip_y()
    pixels.save_png("user://"+name+".png")
func run():
    var app=load("res://Main.tscn").instance()
    get_root().add_child(app)
    app._set_web_remote(false)
    app.set_process(false)
    app.pose_visual.set_mode("off")
    app.set_visuals_enabled(false)
    app.reduced_motion.pressed=true
    var ui=app.music_ui
    ui.show_ma_selection("Night Drive", "Synthetic demo artist", "Generated artwork")
    var stage=preload("res://scripts/StageLayout.gd")
    for size in [Vector2(3440,1440),Vector2(1920,1080),Vector2(1280,720),Vector2(960,720),Vector2(720,1280),Vector2(1102,1440),Vector2(550,720)]:
        OS.window_size=size
        app._apply_resolution_base()
        ui._apply_tv_typography()
        for _i in range(8):yield(self,"idle_frame")
        ui.sync_static_art()
        var canvas=ui.root.rect_size
        var label=str(int(size.x))+"x"+str(int(size.y))
        var top=ui.player_card.rect_position.y+ui.player_card.rect_size.y+12 if ui.portrait_layout else ui.header_card.rect_position.y+ui.header_card.rect_size.y+12
        var bottom=canvas.y-16 if ui.portrait_layout else ui.player_card.rect_position.y-12
        var expected=stage.focused_artwork_rect(canvas,top,bottom)
        ck(not ui.track_hero.visible,"old_left_aligned_hero_hidden_"+label)
        if expected.size.x>=96:
            var box=ui.stage_cover.get_rect()
            ck(ui.stage_cover.visible,"focused_cover_visible_"+label)
            ck(abs(box.get_center().x-canvas.x*.5)<1 and abs(box.get_center().y-(top+bottom)*.5)<1,"cover_centred_in_available_canvas_"+label)
            ck(box.position.y>=top-1 and box.end.y<=bottom+1 and box.position.x>=0 and box.end.x<=canvas.x,"cover_clear_of_controls_"+label)
            ck(not ui.artwork.get_parent().visible,"no_duplicate_thumbnail_"+label)
            ck(box.size.x>min(canvas.x,bottom-top)*.60,"cover_uses_available_space_"+label)
        else:
            ck(not ui.stage_cover.visible and ui.artwork.get_parent().visible,"tight_layout_uses_dock_thumbnail_"+label)
        if capture and size in [Vector2(3440,1440),Vector2(720,1280)]:
            yield(self,"idle_frame")
            _capture("artwork-off-"+label)
        ui._enter_fullscreen()
        ui._set_cover_morph(1.0)
        for _i in range(4):yield(self,"idle_frame")
        var card=ui.fullscreen_track.get_rect()
        ck(abs(card.get_center().x-canvas.x*.5)<1 and abs(card.get_center().y-canvas.y*.5)<1,"fullscreen_card_centred_"+label)
        ck(card.position.y>=0 and card.end.y<=canvas.y and not card.intersects(ui.fullscreen_help.get_rect()),"fullscreen_card_clear_of_help_"+label)
        if canvas.x>=canvas.y*1.6 and expected.size.x>=96:
            ck(ui.fullscreen_art.rect_size.x>expected.size.x*1.15,"fullscreen_grows_cover_"+label)
        ck(not ui.stage_cover.visible and ui.fullscreen_cover==null,"one_fullscreen_cover_"+label)
        if capture and size==Vector2(3440,1440):
            yield(self,"idle_frame")
            _capture("artwork-off-fullscreen-"+label)
        ui._exit_fullscreen()
        ui.sync_static_art()
        ck(not ui.track_hero.visible,"exit_does_not_restore_duplicate_hero_"+label)
        if size==Vector2(1920,1080):
            app.backing_dancers.pressed=false
            app.set_visuals_enabled(true)
            ui.sync_static_art()
            ck(ui.track_hero.visible and not ui.stage_cover.visible and not ui.artwork.get_parent().visible,"visuals_on_hero_replaces_thumbnail")
            app.backing_dancers.pressed=true
            ui.sync_static_art()
            ck(ui.stage_cover.visible and not ui.track_hero.visible and not ui.artwork.get_parent().visible,"dancer_cover_is_the_only_cover")
            app.set_visuals_enabled(false)
            app.backing_dancers.pressed=false
        elif size==Vector2(720,1280):
            app.backing_dancers.pressed=false
            app.set_visuals_enabled(true)
            ui.sync_static_art()
            ck(not ui.stage_cover.visible and not ui.track_hero.visible and ui.artwork.get_parent().visible,"portrait_dock_cover_returns_without_large_cover")
            app.set_visuals_enabled(false)
    app.set_visuals_enabled(true)
    ck(app.visual_quality_level>0,"visuals_can_be_restored")
    app.queue_free()
    yield(self,"idle_frame")
    print("ARTWORK_OFF_LAYOUT_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
