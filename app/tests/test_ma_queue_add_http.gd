extends SceneTree
var catalog=null
var finished=false
var final_state=""
var final_detail=""
var context_notices=0
func on_context(name,ids):
    if name!="Night ride" or ids.empty():push_error("Unexpected playlist context")
    context_notices+=1
func _init(): call_deferred("run")
func on_state(state,detail):
    if state in ["queue_added","unsafe_route","disconnected","command_failed","malformed_reply","stale_reply"]:
        finished=true
        final_state=state
        final_detail=detail
func on_players(_players):
    var media=[{"provider":"library","item_id":"1","media_type":"track","available":true}]
    if OS.get_environment("ADD_MODE")=="batch": media.append({"provider":"library","item_id":"2","media_type":"track","available":true})
    if context_notices!=0:push_error("Browsing fabricated queue context")
    catalog.playlist_context={"name":"Night ride"}
    catalog.playlist_snapshot=media.duplicate(true)
    catalog.playlist_snapshot_valid=true
    catalog.current_page={"kind":"playlist_items"}
    catalog.enqueue_local_media("own-client",media)
func run():
    catalog=load("res://scripts/MACatalog.gd").new();get_root().add_child(catalog)
    catalog.connect("state_changed",self,"on_state");catalog.connect("players_ready",self,"on_players")
    catalog.connect("queued_playlist_context",self,"on_context")
    if not catalog.configure(OS.get_environment("ADD_URL"),"synthetic-credential",[],true):
        quit(1)
        return
    catalog.discover_players()
    for _i in range(400):
        if finished:break
        yield(create_timer(.025),"timeout")
    yield(create_timer(.2),"timeout")
    if context_notices!=(1 if final_state=="queue_added" else 0):push_error("Playlist context accepted an unverified queue mutation")
    print("QUEUE_HTTP_CONTEXT_NOTICES=",context_notices)
    print("QUEUE_HTTP_FINAL=",final_state)
    print("QUEUE_HTTP_DETAIL=",final_detail)
    catalog.close();catalog.queue_free();quit(0 if finished else 1)
