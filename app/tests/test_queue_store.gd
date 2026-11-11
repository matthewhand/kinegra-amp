extends SceneTree
var failures=[]
func check(ok,label):
    print("QSTORE_"+("PASS_" if ok else "FAIL_")+label)
    if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
    var Store=load("res://scripts/QueueStore.gd")
    var store=Store.new()
    var path="user://queue_test.cfg"
    var dir=Directory.new()
    if File.new().file_exists(path): dir.remove(path)
    check(store.read(path).ok and store.read(path).items.empty(),"missing_is_empty")
    check(store.write(path,[2,1,2]),"write_duplicates")
    check(store.read(path).items==[2,1,2],"read_order")
    check(not store.write(path,[store.MAX_INDEX_EXCLUSIVE]),"invalid_rejected")
    check(store.read(path).items==[2,1,2],"invalid_preserves_file")
    var long_queue=[]
    for i in range(store.MAX_QUEUE):long_queue.append(store.MAX_INDEX_EXCLUSIVE-1-i%2)
    check(store.write(path,long_queue) and store.read(path).items==long_queue,"large_queue_round_trips_order_and_repeats")
    long_queue.append(4)
    check(not store.write(path,long_queue),"queue_capacity_enforced")
    var bad=File.new()
    bad.open(path,File.WRITE)
    bad.store_string("not a valid queue")
    bad.close()
    check(not store.read(path).ok and not store.write(path,[1]),"corrupt_not_overwritten")
    dir.remove(path)
    var Player=load("res://scripts/OfflineMusic.gd")
    var one=Player.new()
    one.queue_path=path
    get_root().add_child(one)
    check(one.queue_track(3) and one.queue_track(1) and one.queue_save_ok,"player_saves")
    one.queue_free()
    yield(self,"idle_frame")
    var two=Player.new()
    two.queue_path=path
    get_root().add_child(two)
    check(two.upcoming_queue==[3,1] and not two.is_playing(),"restore_without_autoplay")
    var original_player=two.player
    two.player=null
    check(not two.next_track() and two.upcoming_queue==[3,1],"failure_keeps_queue")
    two.player=original_player
    dir.remove(path)
    var fake=load("res://tests/FakeQueuePlayer.gd").new()
    get_root().add_child(fake)
    fake.upcoming_queue=[2,3]
    fake.pretend_pending=true
    check(fake.next_track() and fake.upcoming_queue==[2,3] and fake.attempt_count==1,"pending_start_retains_queue")
    check(fake.next_track() and fake.attempt_count==1,"pending_start_not_repeated")
    fake._pending_play_until_ms=OS.get_ticks_msec()-1
    fake._process(0)
    check(fake.upcoming_queue==[2,3] and fake._pending_queue_index==-1,"timed_out_start_retains_queue")
    fake.next_track()
    fake.pretend_playing=true
    fake._process(0)
    check(fake.upcoming_queue==[3],"confirmed_start_consumes_one")
    fake.pretend_playing=false
    fake.next_track()
    fake.stop()
    check(fake.upcoming_queue==[3] and fake._pending_queue_index==-1,"cancelled_start_retains_queue")
    fake.next_track()
    fake.queue_track(1)
    fake.pretend_playing=true
    fake._process(0)
    check(fake.upcoming_queue==[3,1],"edit_during_pending_never_deletes_item")
    print("QSTORE_FAILURES=",failures.size())
    quit(0 if failures.empty() else 1)
