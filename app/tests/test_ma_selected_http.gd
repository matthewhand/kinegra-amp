extends SceneTree
class Runtime extends Reference:
    var active=true
    var buffer_invalidations=0
    func invalidate_buffer_measurement():buffer_invalidations+=1
class Client extends Reference:
    var id="own-client"
    func status():return {"paired":true,"client_id":id}
class Facade extends Reference:
    var runtime=Runtime.new()
    var client=Client.new()
    var sink=null
    func stop():runtime.active=false
var app=null
var done=false
var final_state=""
var final_detail=""
var players_ready=false
func state_changed(state,detail):
    if state in ["play_requested","queue_added","disconnected","command_failed","malformed_reply","stale_reply","invalid_request","unsafe_route"]:
        final_state=state;final_detail=detail;done=true
        if app!=null:
            app.tv_queue_timer.stop();app.tv_audio_wait_timer.stop()
func players(_rows):players_ready=true
func _init():call_deferred("run")
func run():
    app=load("res://Main.tscn").instance();get_root().add_child(app)
    yield(create_timer(.15),"timeout")
    var mode=OS.get_environment("SELECTED_MODE")
    var panel=app.ma_panel;var catalog=panel.catalog
    panel.endpoint_edit.text=OS.get_environment("SELECTED_URL")
    panel.lan_trust.pressed=true
    if not catalog.configure(panel.endpoint_edit.text,"synthetic-credential",[],true):
        quit(1)
        return
    panel.library_disconnected=false
    var facade=Facade.new();app.sendspin_facade=facade
    panel.sendspin_paired=true;panel.sendspin_player_id="own-client"
    catalog.connect("state_changed",self,"state_changed");catalog.connect("players_ready",self,"players")
    var playlist=mode.begins_with("playlist")
    var item={"item_id":"42" if playlist else "7","provider":"library","media_type":"playlist" if playlist else "track","available":true,"name":"Synthetic selected playlist" if playlist else "Synthetic selected track"}
    catalog.current_page={"kind":"playlists" if playlist else "tracks","items":[item],"offset":0}
    panel._on_page(catalog.current_page)
    var guarded=mode in ["wrong-client","wrong-route","stale-page","stopped-session","add-wrong-client","add-stopped-session"]
    if not guarded:
        if mode=="playlist-add":panel._queue_selected()
        else:panel._play_on_player() # Deliberate intent during in-flight read must run once.
    else:
        for _i in range(200):
            if players_ready and catalog.request_node==null:break
            yield(create_timer(.025),"timeout")
        if mode in ["wrong-client","add-wrong-client"]:facade.client.id="other-client"
        elif mode=="stale-page":catalog.current_page={"kind":"tracks","items":[{"item_id":"99","provider":"library","media_type":"track","available":true,"name":"Different page"}]}
        elif mode in ["stopped-session","add-stopped-session"]:facade.runtime.active=false
        var accepted=false
        if mode.begins_with("add-"):
            panel._queue_selected()
            accepted=catalog.request_node!=null or not panel.pending_queue_media.empty()
        else:accepted=app._on_sendspin_play_here(item)
        done=not accepted
        final_state="guarded" if not accepted else "unexpected_accept"
    for _i in range(300):
        if done:break
        yield(create_timer(.025),"timeout")
    app.tv_queue_timer.stop();app.tv_audio_wait_timer.stop()
    yield(create_timer(.1),"timeout")
    print("SELECTED_FINAL=",final_state)
    print("SELECTED_DETAIL=",final_detail)
    print("SELECTED_CONTEXT=",app.music_ui.playback_context)
    print("SELECTED_INVALIDATIONS=",facade.runtime.buffer_invalidations)
    catalog.close();app.sendspin_facade=null;app.free()
    quit(0 if done else 1)
