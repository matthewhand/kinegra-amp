extends SceneTree
class Runtime:
    extends Reference
    var active=true
class Client:
    extends Reference
    func status(): return {"paired":true,"client_id":"synthetic-client"}
class Facade:
    extends Reference
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    func stop(): runtime.active=false
var failures=[]
func check(ok,label):
    print("TV_BOUNDS_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func all_buttons(node):
    var result=[]
    for child in node.get_children():
        if child is Button and child.is_visible_in_tree(): result.append(child)
        result+=all_buttons(child)
    return result
func _init(): call_deferred("run")
func run():
    var app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.2),"timeout")
    var ui=app.music_ui
    app.ma_panel.sendspin_paired=true
    app.ma_panel.sendspin_player_id="synthetic-client"
    app.pose_visual.webcam_timer.stop()
    app.pose_visual.set_webcam_connected(true)
    var facade=Facade.new();app.sendspin_facade=facade
    app.ma_panel.endpoint_edit.text="https://ma.invalid"
    app.ma_panel.catalog.endpoint="https://ma.invalid"
    app.ma_panel.catalog.token="synthetic-credential"
    ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    ui.show_tv_queue_snapshot({"current":"Synthetic track", "next":"Synthetic next track with a comfortably long title"})
    for spec in [{"name":"4x3","size":Vector2(960,720)},{"name":"16x9","size":Vector2(1280,720)},{"name":"21x9","size":Vector2(1680,720)},{"name":"portrait720","size":Vector2(720,1280)},{"name":"portrait1080","size":Vector2(1080,1920)},{"name":"narrow480","size":Vector2(480,800)},{"name":"narrow640","size":Vector2(640,1080)}]:
        OS.window_size=spec.size
        app._apply_resolution_base()
        yield(create_timer(.25),"timeout")
        for large in [false,true]:
            app.tv_queue_timing={"active":true,"state":"playing","current_id":"synthetic-current","duration":120,"elapsed":20,"elapsed_updated":OS.get_unix_time()}
            app.tv_queue_timing_read_at=OS.get_ticks_msec()
            ui.set_tv_text_mode(large)
            ui._sync_transport()
            yield(create_timer(.15),"timeout")
            ui._fit_stage_button_labels()
            yield(create_timer(.05),"timeout")
            var window=ui.root.get_global_rect()
            var dock=ui.player_card.get_global_rect()
            var controls=[ui.previous_button,ui.play_button,ui.tv_pause_button,ui.next_button,ui.stop_button,ui.playlist_button,ui.favorite_button,ui.repeat_button,ui.shuffle_button,ui.preset_button,ui.body_button,ui.rewind_button,ui.forward_button,ui.clock_label,ui.tv_queue_label,ui.now_title,ui.source_label,ui.status_label]
            var ok=true
            for control in controls:
                if not control.is_visible_in_tree() or not window.encloses(control.get_global_rect()) or not dock.encloses(control.get_global_rect()):
                    ok=false
                    print("TV_BOUNDS_OUTSIDE=",spec.name,"/large=",large," control=",control.name," rect=",control.get_global_rect()," viewport=",window," dock=",dock)
            check(ok,spec.name+("_large" if large else "_normal"))
            var text_ok=true
            for button in all_buttons(ui.header_card)+controls:
                if button is Button and button.is_visible_in_tree():
                    var font=button.get_font("font")
                    var style=button.get_stylebox("normal")
                    if font!=null and style!=null and font.get_string_size(button.text).x+style.get_minimum_size().x+(button.icon.get_width()+button.get_constant("hseparation") if button.icon!=null else 0)>button.rect_size.x+1:
                        text_ok=false
                        print("TV_TEXT_CLIPPED=",spec.name,"/large=",large," text=",button.text," available=",button.rect_size.x," required=",font.get_string_size(button.text).x+style.get_minimum_size().x)
            check(text_ok,spec.name+("_large" if large else "_normal")+"_button_text")
            check(ui.timeline_row.visible and not ui.playback_progress.visible and not ui.rewind_button.disabled and not ui.forward_button.disabled,spec.name+("_large" if large else "_normal")+"_server_seek_without_offline_timeline")
            for navigation in all_buttons(ui.header_card):
                check(window.encloses(navigation.get_global_rect()),spec.name+("_large" if large else "_normal")+"_header_"+navigation.text)
            app.sendspin_facade=null
            ui.set_playback_context("offline");ui.source_label.text="OFFLINE MUSIC  •  ON THIS DEVICE"
            ui._sync_transport()
            yield(create_timer(.1),"timeout")
            var offline_ok=true
            for control in [ui.previous_button,ui.play_button,ui.next_button,ui.stop_button,ui.rewind_button,ui.forward_button,ui.clock_label,ui.playlist_button,ui.favorite_button,ui.repeat_button,ui.shuffle_button,ui.preset_button,ui.body_button]:
                if not control.is_visible_in_tree() or not ui.root.get_global_rect().encloses(control.get_global_rect()):
                    offline_ok=false
                    print("TV_BOUNDS_OFFLINE_OUTSIDE=",spec.name,"/large=",large," control=",control.name," rect=",control.get_global_rect())
            check(ui.playback_progress.visible==(ui.root.rect_size.x>=800.0),spec.name+("_large" if large else "_normal")+"_responsive_progress")
            check(offline_ok,spec.name+("_large" if large else "_normal")+"_offline")
            app.sendspin_facade=facade
            ui.set_playback_context("ma");ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
            ui.tv_queue_label.show()
            ui.queue_view="tv"
            ui.tv_queue_items=["Synthetic first item","Synthetic second item"]
            ui.tv_queue_rows=[{"name":"Synthetic first item","item_id":"future-1","index":2},{"name":"Synthetic second item","item_id":"future-2","index":3}]
            ui.tv_queue_preview_status="FIRST 2 ITEMS / READ ONLY"
            ui.queue_drawer.show()
            ui._refresh_queue()
            yield(create_timer(.1),"timeout")
            ui._fit_stage_button_labels()
            var drawer_ok=true
            for control in [ui.queue_header_label,ui.queue_help_label,ui.queue_refresh_button,ui.queue_remove_button,ui.queue_clear_button,ui.queue_close_button]:
                if not control.is_visible_in_tree() or not ui.root.get_global_rect().encloses(control.get_global_rect()) or not ui.queue_drawer.get_global_rect().encloses(control.get_global_rect()):
                    drawer_ok=false
                    print("TV_QUEUE_DRAWER_OUTSIDE=",spec.name,"/large=",large," control=",control.name," rect=",control.get_global_rect())
            check(not ui.queue_up_button.visible and not ui.queue_down_button.visible and not ui.queue_remove_button.disabled and not ui.queue_clear_button.disabled,spec.name+("_large" if large else "_normal")+"_queue_editor")
            var drawer_text_ok=true
            for button in [ui.queue_refresh_button,ui.queue_remove_button,ui.queue_clear_button,ui.queue_close_button]:
                var font=button.get_font("font")
                var style=button.get_stylebox("normal")
                if font.get_string_size(button.text).x+style.get_minimum_size().x>button.rect_size.x+1:
                    drawer_text_ok=false
                    print("TV_QUEUE_TEXT_CLIPPED=",spec.name,"/large=",large," text=",button.text)
            check(drawer_text_ok,spec.name+("_large" if large else "_normal")+"_queue_editor_text")
            check(not ui.queue_toggle_button.visible,spec.name+("_large" if large else "_normal")+"_backend_selector_not_exposed")
            check(drawer_ok,spec.name+("_large" if large else "_normal")+"_queue_preview")
            ui.queue_drawer.hide()
            ui.queue_view="local"
            ui.tv_queue_items.clear()
    app.sendspin_facade=null;app.queue_free()
    print("TV_BOUNDS_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
