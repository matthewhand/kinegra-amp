extends SceneTree
class Stub:
    extends Reference
    var starts=0
    var stops=0
    var value=0.4
    func startCapture(): starts+=1
    func stopCapture(): stops+=1
    func captureStatus(): return "capturing"
    func captureLevel(): return value
func _init():
    var script=load("res://scripts/PlaybackCaptureClient.gd")
    var missing=script.new()
    assert(missing.status()=="unavailable" and missing.level()==0.0 and not missing.request_start())
    var stub=Stub.new()
    var client=script.new(stub)
    assert(stub.starts==0 and stub.stops==0)
    assert(client.request_start() and stub.starts==1 and client.status()=="capturing")
    assert(abs(client.level()-0.4)<0.00001)
    stub.value=2.0
    assert(client.level()==1.0)
    stub.value=NAN
    assert(client.level()==0.0)
    assert(client.request_stop() and stub.stops==1)
    print("CAPTURE_CLIENT_SYNTHETIC_CHECKS_PASS")
    quit(0)
