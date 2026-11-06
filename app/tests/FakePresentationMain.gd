extends "res://scripts/Main.gd"
# UI fixture only: no network requests or playback commands leave this process.
var fixture_fresh=false
var fixture_commands=[]
func _sendspin_fresh():return fixture_fresh
func _sendspin_command(command, _argument=null):
    fixture_commands.append(command)
    return true
func _queue_controls_available():return true
func _sendspin_controls():return {"paired":true,"can_play":true,"can_pause":true,"can_next":true,"can_previous":true}
func _tv_seek_available():return false
