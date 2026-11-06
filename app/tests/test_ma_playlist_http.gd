extends SceneTree
var catalog=null
var pages=[]
var failed=false
func page(value):pages.append(value)
func state(value,_detail):
    if value in ["disconnected","malformed_reply","command_failed"]:failed=true
func _init():call_deferred("run")
func wait_read():
    for _i in range(400):
        if catalog.request_node==null:return
        yield(create_timer(.025),"timeout")
func run():
    catalog=load("res://scripts/MACatalog.gd").new();get_root().add_child(catalog)
    catalog.connect("page_ready",self,"page");catalog.connect("state_changed",self,"state")
    catalog.configure(OS.get_environment("PLAYLIST_URL"),"synthetic-playlist-token",[],true)
    catalog.current_page={"items":[{"item_id":"1","provider":"library","media_type":"playlist","name":"Synthetic"}]};catalog.select_index(0)
    catalog.playlist_items();yield(wait_read(),"completed")
    var mode=OS.get_environment("PLAYLIST_MODE")
    var ok=true
    if mode in ["oversized","malformed"]:
        ok=failed and pages.empty() and catalog.current_page.empty() and not catalog.playlist_snapshot_valid
    else:
        var expected={"empty":0,"one":1,"large":500,"changing":500}[mode]
        ok=not failed and pages.size()==1 and pages[0].returned_count==expected and pages[0].items.size()==min(25,expected) and pages[0].total_count==-1
        if expected>25:
            catalog.playlist_page(25)
            ok=ok and pages.size()==2 and pages[1].offset==25 and pages[1].items[0].item_id=="26"
        if mode=="changing":
            catalog.refresh_playlist();yield(wait_read(),"completed")
            ok=ok and pages.size()==3 and pages[2].returned_count==1 and pages[2].items.size()==1 and pages[2].offset==0
    catalog.close()
    ok=ok and catalog.token.empty() and catalog.playlist_snapshot.empty() and catalog.playlist_context.empty()
    print("PLAYLIST_HTTP_"+("PASS_" if ok else "FAIL_")+mode)
    catalog.queue_free();quit(0 if ok else 1)
