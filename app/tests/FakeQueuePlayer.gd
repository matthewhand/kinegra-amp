extends "res://scripts/OfflineMusic.gd"
var pretend_pending=false
var attempt_count=0
var pretend_playing=false
func is_playing():
    return pretend_playing
func select_track(index):
    attempt_count+=1
    if pretend_pending:
        track_index=index
        _pending_play_until_ms=OS.get_ticks_msec()+700
    return false
