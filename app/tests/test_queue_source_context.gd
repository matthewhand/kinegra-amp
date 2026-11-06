extends SceneTree
var checks=0
func check(value):
    checks+=1
    if not value:push_error("Queue context check failed")
func _init():
    var ui=load("res://scripts/MusicFirstUI.gd").new()
    var owner=Node.new()
    ui.app=owner
    ui.source_label=Label.new()
    check(ui.set_playback_context("ma"))
    ui.source_label.text="Different translated label"
    check(ui._tv_mode())
    check(ui.set_playback_context("offline"))
    ui.source_label.text="MUSIC ASSISTANT  •  PLAYING HERE"
    check(not ui._tv_mode())
    check(ui.set_playback_context("catalog"))
    check(ui._tv_mode())
    check(not ui.set_playback_context("other_player"))
    check(ui.playback_context=="catalog")
    check(ui.set_playback_context("preview"))
    check(not ui._tv_mode())
    ui.source_label.free()
    ui.free()
    owner.free()
    print("QUEUE_CONTEXT checks=%d" % checks)
    quit()
