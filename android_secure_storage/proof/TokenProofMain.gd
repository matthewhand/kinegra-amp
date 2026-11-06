extends Node
# Synthetic proof package only. No credentials are read or written.
func _ready():
    var ok = OS.get_name() == "Android" and Engine.has_singleton("ShieldAmpTokenStore")
    var result = File.new()
    if result.open("user://synthetic-plugin-registration.txt", File.WRITE) == OK:
        result.store_string("registered\n" if ok else "unavailable\n")
        result.close()
    get_tree().quit(0 if ok else 1)
