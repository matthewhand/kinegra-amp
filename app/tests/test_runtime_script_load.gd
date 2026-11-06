extends SceneTree
var failed=[]
func _init():call_deferred("run")
func run():
    var directory=Directory.new();directory.open("res://scripts");directory.list_dir_begin(true,true)
    var name=directory.get_next();var checks=0
    while name!="":
        if name.ends_with(".gd"):
            var script=load("res://scripts/"+name)
            checks+=1
            if script==null or not script.can_instance():failed.append(name)
        name=directory.get_next()
    directory.list_dir_end()
    print("RUNTIME_SCRIPT_CHECKS=",checks," FAILURES=",failed)
    quit(0 if failed.empty() else 1)
