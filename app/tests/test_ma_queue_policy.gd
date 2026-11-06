extends SceneTree
var failures=[]
var last_snapshot={}
func remember_snapshot(value):last_snapshot=value
func check(ok,label):
    print("QUEUE_POLICY_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
    var p=load("res://scripts/MAQueuePolicy.gd").new()
    var s={"active":true,"state":"playing","current_id":"current","duration":100,"elapsed":20,"elapsed_updated":1000,"current_index":0,"index_in_buffer":1}
    check(p.seek_target(s,10,1001)==31 and p.seek_target(s,-10,1001)==11,"fresh_server_time_drives_bounded_seek")
    s.elapsed=95;check(p.seek_target(s,10,1001)==100,"seek_clamps_to_duration")
    s.elapsed=2;check(p.seek_target(s,-10,1001)==0,"seek_clamps_to_zero")
    s.elapsed=20;s.state="paused";check(p.seek_target(s,10,1001)==-1,"paused_seek_cannot_silently_start_playback")
    s.state="idle";check(p.seek_target(s,10,1001)==-1,"idle_seek_rejected")
    s.state="playing";check(p.seek_target(s,10,1011)==-1 and p.seek_target(s,10,997)==-1,"stale_or_clock_skewed_timing_rejected")
    s.duration=0;check(p.seek_target(s,10,1001)==-1,"untimed_media_rejected")
    s.duration=100;s.elapsed=NAN;check(p.seek_target(s,10,1001)==-1,"nonfinite_timing_rejected")
    s.elapsed=20;s.active=false;check(p.seek_target(s,10,1001)==-1,"inactive_queue_rejected")
    s.active=true;check(p.seek_target(s,5,1001)==-1,"only_bounded_offsets_allowed")
    check(p.upcoming_offset(s)==2,"preview_starts_after_buffer_boundary")
    s.current_index=3.0;s.index_in_buffer=4.0;check(p.upcoming_offset(s)==5,"integer_json_float_indices_supported")
    s.index_in_buffer=4.5;check(p.upcoming_offset(s)==-1,"fractional_indices_rejected")
    s.current_index=0;s.index_in_buffer=1
    var rows=[{"item_id":"future","index":2}]
    check(p.removable(s,rows,"future"),"upcoming_id_removable")
    check(not p.removable(s,[{"item_id":"current","index":2}],"current"),"current_id_protected")
    check(not p.removable(s,[{"item_id":"buffered","index":1}],"buffered"),"buffered_index_protected")
    check(not p.removable(s,rows,"missing") and not p.removable(s,rows+rows,"future"),"missing_or_duplicate_id_rejected")
    check(not p.item_id("http://bad") and not p.item_id(2) and not p.item_id("bad\n"),"ids_are_opaque_bounded_strings")
    var header="Date: Fri, 01 Jan 2021 00:00:10 GMT"
    var clock=p.http_clock([header],5000,50)
    check(clock.get("server_time")==1609459210 and clock.get("clock_valid")==true,"response_date_parsed_as_numeric_utc")
    var skewed={"active":true,"state":"playing","current_id":"current","duration":120,"elapsed":20.25,"elapsed_updated":1609459209.813}
    check(p.seek_target(skewed,10,1609459206.5,5250)==-1,"unanchored_device_clock_behind_server_remains_rejected")
    for key in clock:skewed[key]=clock[key]
    check(p.seek_target(skewed,10,1609459206.5,5250)==30,"http_date_and_monotonic_ticks_handle_device_behind_3_5_seconds")
    check(p.seek_target(skewed,10,1609459250,5250)==30,"device_wall_clock_jump_does_not_change_server_seek")
    check(p.seek_target(skewed,10,1609459206.5,10001)==-1 and p.seek_target(skewed,10,1609459206.5,4999)==-1,"monotonic_anchor_age_and_reversal_guarded")
    skewed.elapsed_updated=1609459179.0
    check(p.seek_target(skewed,10,1609459206.5,5250)==-1,"real_stale_queue_rejected_despite_device_clock_skew")
    skewed.elapsed_updated=1609459200.5
    check(p.seek_target(skewed,10,1609459206.5,5250)==-1,"freshness_uses_conservative_date_rounding_and_transit_upper_bound")
    for invalid_headers in [[header,header],["Date: not a date"],["Date: Fri, 31 Feb 2021 00:00:10 GMT"],["Date: Sat, 01 Jan 2021 00:00:10 GMT"]]:
        check(p.http_clock(invalid_headers,5000,50).get("clock_valid")==false,"ambiguous_or_invalid_server_date_rejected")
    check(p.http_clock([header],5000,2001).get("clock_valid")==false,"slow_response_cannot_create_fresh_clock_anchor")
    check(p.http_clock([],5000,50).empty(),"absent_date_keeps_existing_strict_clock_policy")
    skewed.elapsed_updated=1609459209.813;skewed.clock_valid=false
    check(p.seek_target(skewed,10,1609459210,5250)==-1,"bad_response_clock_cannot_fall_back_to_unguarded_seek")
    var adapter=load("res://scripts/MACatalog.gd").new();get_root().add_child(adapter)
    adapter.connect("local_queue_snapshot",self,"remember_snapshot")
    adapter.request_node=HTTPRequest.new();adapter.add_child(adapter.request_node)
    adapter.request_context={"kind":"local_queue_read","queue_id":"own-wrapper"}
    var long_id="opaque-".repeat(25)
    var body={"queue_id":"own-wrapper","state":"playing","current_item":{"name":"Synthetic","queue_item_id":long_id}}
    adapter._complete(HTTPRequest.RESULT_SUCCESS,200,[],to_json(body).to_utf8(),adapter.epoch)
    check(last_snapshot.get("current_id")==long_id,"metadata_preserves_exact_opaque_identity_for_protection")
    adapter.queue_free()
    print("QUEUE_POLICY_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
