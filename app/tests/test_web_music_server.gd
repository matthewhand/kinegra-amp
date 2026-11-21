extends SceneTree
class FixtureClient:
    extends Reference
    func status():return {"paired":true,"client_id":"fixture-client"}
class FixtureRuntime:
    extends Reference
    var active=true
class FixtureFacade:
    extends Node
    var client=FixtureClient.new()
    var runtime=FixtureRuntime.new()
class FixturePanel:
    extends Node
    signal credential_session_closed(reason)
    var library_disconnected=false
    var endpoint_edit=LineEdit.new()
    var lan_trust=CheckBox.new()
    var catalog=preload("res://scripts/MACatalog.gd").new()
    func _credential_endpoint():return endpoint_edit.text
    func _sendspin_start():return true
    func _exit_tree():
        endpoint_edit.free()
        lan_trust.free()
        catalog.free()
class FixtureUI:
    extends Reference
    func set_playback_context(_value):pass
    func invalidate_tv_queue():pass
class FixtureOfflineMusic:
    extends Reference
    var user_library={"directory":"user://web_music_fixture_library"}
    func is_playing():return false
class FixtureOfflineSave:
    extends Reference
    var state="idle"
    var active=false
    var message="Synthetic offline status"
    var copied=0
    var saved_indices=[]
    var source_count=0
    func has_pending():return false
    func configured():return false
    func _free_bytes(_directory):return -1
class FixtureOwner:
    extends Node
    var ma_panel=FixturePanel.new()
    var sendspin_facade=FixtureFacade.new()
    var offline_music=FixtureOfflineMusic.new()
    var offline_save=FixtureOfflineSave.new()
    var local_pcm=null
    var native_transport=null
    var tv_queue_request=null
    var tv_queue_timer=Timer.new()
    var music_ui=FixtureUI.new()
    var playback_recovery=preload("res://scripts/PlaybackRecovery.gd").new()
    func _ready():
        ma_panel.endpoint_edit.text="http://127.0.0.1:18766"
        ma_panel.lan_trust.pressed=true
        add_child(ma_panel)
        add_child(sendspin_facade)
        add_child(tv_queue_timer)
    func _library_credential(_saved=true):return "synthetic-library-access"
    func _sendspin_controls():return sendspin_facade.client.status()
    func _queue_read_in_progress():return false
    func _prepare_stream_visuals():pass
    func _watch_tv_audio(_require_new_stream=false):pass
    func _uses_android_sendspin():return false
    func _arm_playback_recovery():pass
    func _set_tv_playback_error(_detail):pass
    func web_remote_snapshot():return {"title":"Synthetic remote track","source":"Synthetic fixture","state":"paused"}
    func web_remote_control(_action):return true
func _init():call_deferred("run")
func run():
    Engine.target_fps=60
    var owner=FixtureOwner.new()
    get_root().add_child(owner)
    var remote=load("res://scripts/WebRemote.gd").new()
    remote.settings_path="user://web_music_fixture.cfg"
    owner.add_child(remote)
    remote.configure(owner,false)
    remote.set_enabled(true)
    if not remote.server.is_listening() or remote.key.length()!=16:
        printerr("FAIL test port unavailable")
        quit(1)
        return
    print("WEB_MUSIC_READY ",remote.key)
    create_timer(180).connect("timeout",self,"deadline")
func deadline():quit()
