extends SceneTree
class Pcm:
    extends "res://scripts/LocalPcmPlayer.gd"
    var stops=0
    func stop():stops+=1
class Decoder:
    extends "res://scripts/NativeDecoderPlayer.gd"
    var stops=0
    func stop():stops+=1
class Transport:
    extends "res://scripts/NativeHTTPTransport.gd"
    var stops=0
    func stop():stops+=1
class Stream:
    extends "res://scripts/StreamPlayer.gd"
    var stops=0
    func stop():stops+=1
func _init():call_deferred("run")
func run():
    var ok=true
    for script in [Pcm,Decoder,Transport,Stream]:
        var owner=script.new()
        owner._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
        ok=ok and owner.stops==0
        owner._notification(MainLoop.NOTIFICATION_APP_PAUSED)
        ok=ok and owner.stops==1
        owner.free()
    print("AUDIO_FOCUS_POLICY_PASS=",ok)
    quit(0 if ok else 1)
