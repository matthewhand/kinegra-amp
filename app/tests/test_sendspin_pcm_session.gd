extends SceneTree
# No networking, real device, decoder output or audio playback. Entirely
# fictional timestamps and ZERO-VALUED silent PCM bytes, NEVER test tones.
var checks = 0
var errors = []
var route = null
func test(result, name):
    checks += 1
    if not result:
        errors.append(name)
        printerr("FAIL ", name)
func make_packet(time_us, size=16, role=4, ahead=100000):
    var bytes = PoolByteArray()
    bytes.append(role)
    for i in range(7, -1, -1):
        bytes.append(int((time_us >> (i * 8)) & 255))
    for i in range(3, -1, -1):
        bytes.append(int((ahead >> (i * 8)) & 255))
    for _i in range(size):
        bytes.append(0)
    return bytes
func valid_format():
    return {"codec":"pcm", "channels":2,"sample_rate":48000,"bit_depth":16}
func admit():
    return route.begin_authenticated_playback(true,true,true,true,true)
func _init():
    call_deferred("run")
func run():
    route = load("res://scripts/SendspinPcmSession.gd").new()
    var output = load("res://scripts/SendspinPcmOutput.gd").new()
    # Check pure conversion only; NEVER start or play its AudioStream.
    test(output._signed16(PoolByteArray([0,0]),0) == 0,"zero silence PCM")
    test(output._signed16(PoolByteArray([255,127]),0) == 32767,"signed high bound")
    test(output._signed16(PoolByteArray([0,128]),0) == -32768,"signed low bound")
    test(not output.push_validated_pcm(PoolByteArray([0,0,0,0])), "sink inert without authenticated session")
    test(route.advertised_player_support()["supported_formats"].size() == 1,"one honest format")
    test(route.advertised_player_support()["buffer_capacity"] == route.BUFFER_CAPACITY,"bounded advertised buffer")
    for denied in [
        [false,true,true,true,true],
        [true,false,true,true,true],
        [true,true,false,true,true],
        [true,true,true,false,true],
        [true,true,true,true,false]
    ]:
        test(not route.begin_authenticated_playback(denied[0],denied[1],denied[2],denied[3],denied[4]),
            "cryptographic/role/time prerequisite cannot be omitted")
        test(not route.active and not route.streaming and route.queued.empty(),"failed admit resets session")
    test(admit(),"only explicitly asserted authenticated paired session activates pure engine")
    var format = valid_format()
    for key in ["codec","channels","sample_rate","bit_depth"]:
        var broken = format.duplicate()
        broken[key] = "opus" if key == "codec" else 1
        test(not route.on_stream_start(broken),"reject unsupported " + key)
        test(not route.active,"incompatible codec ends session")
        test(admit(),"new session after unsupported format")
    var wrong = format.duplicate()
    wrong["codec_header"] = "fake"
    test(not route.on_stream_start(wrong),"PCM codec header forbidden")
    test(admit(),"new session after unexpected header")
    test(route.on_stream_start(format),"fixed 48k stereo PCM stream starts")
    test(route.on_stream_start(format),"in-place unchanged format refresh permitted")
    test(route.active and route.streaming,"no state reset on idempotent format refresh")
    test(route.on_authenticated_audio(make_packet(1000000),1000000),"first silent sample framed")
    test(route.queued_bytes == 16 and route.queued.size()==1,"acceptance accounted")
    test(route.dequeue_due(999999).empty(),"future frame not due")
    var out = route.dequeue_due(1000000,2)
    test(out.size()==8 and route.queued_bytes==8,"partial due dequeue counted")
    out = route.dequeue_due(1001000,2)
    test(out.size()==8 and route.queued_bytes==0 and route.queued.empty(),"remaining bytes consumed")
    test(route.on_stream_clear(),"clear flushes player role queue")
    test(route.queued_bytes==0 and route.last_timestamp==-1,"stream clear discards previous frames")
    test(route.on_authenticated_audio(make_packet(1000000),1000000),"new song timestamp restarts on clear")
    test(not route.on_authenticated_audio(make_packet(999999),1000000),"regressing timestamps fail closed")
    test(admit() and route.on_stream_start(format),"reset after unordered")
    test(not route.on_authenticated_audio(make_packet(1200000,12,5),1000000),"unknown binary role rejected")
    test(admit() and route.on_stream_start(format),"reset after role mismatch")
    test(not route.on_authenticated_audio(make_packet(1200000,3),1000000),"malformed PCM frame rejected")
    test(admit() and route.on_stream_start(format),"reset after bad frame")
    test(not route.on_authenticated_audio(make_packet(4000001),1000000),"far future rejected")
    test(admit() and route.on_stream_start(format),"reset after far future")
    test(not route.on_authenticated_audio(make_packet(700000),1000000),"too late rejected")
    test(admit() and route.on_stream_start(format),"reset after lateness")
    test(not route.on_authenticated_audio(make_packet(1000000),-1),"untrusted clock refused")
    test(admit() and route.on_stream_start(format),"reset after bad clock")
    test(not route.on_authenticated_audio(make_packet(1000000,16388),1000000),"oversized single chunk")
    test(admit() and route.on_stream_start(format),"reset after huge chunk")
    test(not route.on_authenticated_audio(make_packet(1000000),1000000.0),"float clock rejected")
    test(admit() and route.on_stream_start(format),"reset after float clock")
    test(route.on_authenticated_audio(make_packet(1000000,16,4,0),1000000),"zero send ahead accepted as unknown")
    test(not route.queued[0]["send_ahead_valid"],"zero send ahead not delay measurement")
    test(route.on_stream_clear(),"clear after zero lead")
    test(route.on_authenticated_audio(make_packet(1000000,16,4,4294967295),1000000),"saturated send ahead accepted")
    test(not route.queued[0]["send_ahead_valid"],"saturated lead excluded")
    test(route.on_stream_end() and route.queued.empty(),"stream/end discards buffered audio")
    test(not route.on_authenticated_audio(make_packet(1000000),1000000),"binary outside active stream refused")
    test(admit() and route.on_stream_start(format),"reset for capacity test")
    var capacity_ok = true
    var start=1000000
    for i in range(15):
        capacity_ok = capacity_ok and route.on_authenticated_audio(make_packet(start+85334*i,16384),start)
    test(capacity_ok and route.queued_bytes==15*16384 and route.accounted_bytes==15*(16384+13),"full wire header plus PCM capacity accounted")
    test(not route.on_authenticated_audio(make_packet(start+85334*15,16384),start),"sixteenth packet exceeds wire-byte cap and fails closed")
    test(not route.active and route.queued.empty() and route.queued_bytes==0,"capacity breach discards all queued bytes")
    test(admit() and route.on_stream_start(format),"reset on capacity failure")
    test(route.on_authenticated_audio(make_packet(1000000),1000000),"valid packet before reset")
    test(route.accounted_bytes==29,"13 byte framing included in wire accounting")
    test(route.dequeue_due(1000000,4).size()==16,"real samples may leave staging buffer")
    test(route.accounted_bytes==29,"dequeued bytes remain accounted until scheduled completion")
    route._release_completed(1001000)
    test(route.accounted_bytes==0,"completed chunk releases wire accounting")
    route.reset()
    test(not route.active and route.queued.empty() and route.queued_bytes==0,"disconnect clears state")
    test(not route.on_authenticated_audio(make_packet(1000000),1000000),"stale packet cannot replay")
    output.free()
    route = null
    print("SENDSPIN_PCM_SESSION_CHECKS=", checks, " FAILURES=", errors)
    quit(0 if errors.empty() else 1)
