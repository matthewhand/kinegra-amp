extends SceneTree
var checks=0
var failures=[]
func ck(ok,label):
    checks+=1
    if not ok:
        failures.append(label)
        printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
    var motion=load("res://scripts/PlaybackNotice.gd").new()
    ck(motion.show("Synthetic track A"),"new track starts notice")
    ck(motion.step(.05)<.02,"notice enters gently")
    for _i in range(37):motion.step(.05)
    ck(motion.alpha>.9,"slow fade reaches readable opacity")
    var low=1.0
    var high=0.0
    for _i in range(90):
        var value=motion.step(.05)
        low=min(low,value)
        high=max(high,value)
        ck(not motion.show("Synthetic track A"),"repeated metadata does not restart notice")
    ck(low>=.919 and high<=1.001 and high-low>.04,"gentle bounded multi-second pulse")
    for _i in range(80):motion.step(.05)
    ck(not motion.active and motion.alpha==0.0,"notice fades away instead of lingering or flashing")
    ck(motion.show("Synthetic track B"),"actual new track can reveal again")
    for _i in range(40):motion.step(.05,true)
    ck(motion.alpha==1.0,"centered album art stays visible")
    for _i in range(250):motion.step(.05,true)
    ck(motion.alpha==1.0,"persistent artwork has no pulse or auto-dismiss")
    var before=motion.alpha
    motion.step(.016,false)
    ck(abs(motion.alpha-before)<.01,"leaving artwork mode has no sudden opacity jump")
    for _i in range(250):motion.step(.05,false,true)
    ck(motion.alpha==1.0,"reduced motion keeps unanimated readable metadata")
    motion.reveal()
    var age=motion.age
    motion.step(-1)
    ck(motion.age==age,"negative time is ignored")
    print("PLAYBACK_NOTICE_CHECKS=",checks," FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
