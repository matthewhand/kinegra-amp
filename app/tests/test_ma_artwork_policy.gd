extends SceneTree
var failures=[]
func check(ok,label):
    print("ARTWORK_POLICY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var policy=load("res://scripts/MAArtworkPolicy.gd")
    var id="a".repeat(64)
    var raw={"metadata":{"images":[{"type":"fanart","proxy_id":"b".repeat(64)},{"type":"thumb","proxy_id":id,"path":"https://untrusted.invalid/private","provider":"fictional"}]}}
    check(policy.sanitize(raw).get("proxy_id")==id and policy.sanitize(raw).size()==1,"only_opaque_thumbnail_id_retained")
    check(policy.sanitize({"media_item":{"album":raw}}).get("proxy_id")==id,"queue_album_fallback")
    for invalid in ["",id+"1","A".repeat(64),"https://untrusted.invalid/cover",id.substr(0,63)+"/"]:
        check(policy.descriptor({"proxy_id":invalid}).empty(),"invalid_id_rejected")
    check(policy.sanitize({"image":{"path":"https://untrusted.invalid/cover","provider":"fictional"}}).empty(),"no_guessed_legacy_url")
    var image=Image.new();image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color(0.2,0.4,0.6))
    var png=image.save_png_to_buffer()
    check(policy.png_geometry(png)==Vector2(2,2),"bounded_png_geometry")
    png[16]=0;png[17]=0;png[18]=16;png[19]=0
    check(policy.png_geometry(png)==Vector2.ZERO,"oversize_geometry_rejected_before_decode")
    check(policy.png_geometry(PoolByteArray([60,115,118,103,62]))==Vector2.ZERO,"svg_not_decoded")
    var model=load("res://scripts/MAPresentationState.gd").new()
    var snapshot={"current_id":"fictional-item","current":"Example title","artist":"","album":"","active":true,"state":"playing","elapsed":20.0,"duration":180.0,"elapsed_updated":1700000010.0,"clock_valid":true,"server_time":1700000010,"clock_received_ms":1000,"clock_rtt_ms":50}
    var current=model.current(snapshot,1000,2000,true,1)
    check(current.timeline and current.advancing and current.position==21 and current.artist.empty() and current.album.empty(),"genuine_server_clock_progress")
    snapshot.state="paused"
    current=model.current(snapshot,1000,4000,true,1)
    check(current.timeline and not current.advancing and current.position==20,"paused_position_never_advances")
    snapshot.state="playing"
    current=model.current(snapshot,1000,2000,false,1)
    check(current.position==20 and not current.advancing,"no_live_pcm_uses_last_reported_position")
    snapshot.erase("duration")
    check(not model.current(snapshot,1000,2000,true,1).timeline,"radio_has_no_invented_duration")
    check(model.current(snapshot,1000,11001,true,1).empty(),"stale_metadata_expires")
    snapshot.current=""
    check(model.current(snapshot,1000,2000,true,1).empty(),"missing_current_item_revokes_old_metadata")
    print("ARTWORK_POLICY_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
