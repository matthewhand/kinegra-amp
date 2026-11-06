extends SceneTree
# No network, services, PCM speaker output or tones. Music files are only
# loaded by the existing offline app scene; this test never presses Play.
var checks = 0
var failures = []
class FictionalPcmSink:
    extends Reference
    var ready = false
    var seen = []
    var seen_generations = []
    func push_validated_pcm(data, generation = -1):
        if not ready:
            return false
        seen.append(PoolByteArray(data))
        seen_generations.append(generation)
        return true
func ck(ok, msg):
    checks += 1
    if not ok:
        failures.append(msg)
        printerr("FAIL ", msg)
func _init():
    call_deferred("run")
func run():
    var list = load("res://scripts/LocalPlaylists.gd").new()
    ck(list.playlist_name()=="ALL TRACKS" and list.indices()==[0,1,2,3], "default chronological playlist")
    ck(list.repeat_name()=="ALL", "default repeat all")
    ck(list.step_track(0, 1)==1 and list.step_track(0,-1)==3,"manual previous wraps")
    ck(list.step_track(3,1)==0,"manual next wraps")
    ck(list.choose_playlist(1,1)==0 and list.indices()==[0,2,3],"night flight tracks only")
    ck(list.step_track(0,1)==2 and list.step_track(2,1)==3,"night flight order")
    ck(list.choose_playlist(2,0)==1 and list.indices()==[1,3],"heavy rotation 2 tracks")
    ck(list.step_track(1,1)==3 and list.step_track(3,-1)==1,"heavy rotation navigation")
    ck(list.choose_playlist(3,0)==-1,"empty favourites rejected")
    ck(list.playlist_name()=="HEAVY ROTATION","bad collection does not change current")
    ck(not list.toggle_favorite(-1) and not list.toggle_favorite(4),"invalid favourites rejected")
    ck(list.toggle_favorite(0) and list.toggle_favorite(2),"favourites toggled on")
    ck(list.choose_playlist(3,2)==2 and list.indices()==[0,2],"favorites selection preserved")
    ck(list.step_track(2,1)==0 and list.step_track(0,-1)==2,"favorites wrap")
    ck(not list.toggle_favorite(2) and list.indices()==[0],"remove from favorites")
    ck(list.step_track(2,1)==0,"removed current track finds next valid")
    ck(list.cycle_repeat()=="ONE","repeat one")
    ck(list.step_track(0,1,true)==0,"automatic repeat one")
    ck(list.step_track(0,1,false)==0,"manual on singleton")
    ck(list.cycle_repeat()=="OFF","repeat off")
    ck(list.step_track(0,1,true)==-1,"automatic repeat off ends collection")
    ck(list.cycle_repeat()=="ALL","repeat all restoration")
    ck(list.choose_playlist(-1,0)==-1 and list.choose_playlist(99,0)==-1,"invalid playlist rejected")
    ck(list.step_track(0,0)==-1 and list.step_track(0,2)==-1,"invalid directions rejected")

    var env = load("res://scripts/FftEnvelope.gd").new()
    ck(env.bands.size()==16 and env.bands.max()==0.0,"16 silent bands")
    var raw = []
    for i in range(16):
        raw.append(0.0)
    raw[0]=1.0
    var attacked = env.apply(raw,0.016)
    ck(attacked[0]>0.20 and attacked[0]<1.0,"rapid bass attack")
    ck(attacked[1]==0.0,"independent bands stay silent")
    raw[0]=0.0
    var released = env.apply(raw,0.016)
    ck(released[0]>0.0 and released[0]<attacked[0],"slower decay")
    ck(env.apply([0.1],0.02)==env.bands,"bad spectral length no mutation")
    raw[1]=NAN
    ck(env.apply(raw,0.02)==env.bands,"NaN rejected atomically")
    raw[1]=INF
    ck(env.apply(raw,0.02)==env.bands,"infinity rejected atomically")
    raw[1]=-1.0
    ck(env.apply(raw,0.02)==env.bands,"negative magnitude rejected")
    raw[1]=0.0
    ck(env.apply(raw,NAN)==env.bands,"invalid delta rejected")
    ck(env.apply(raw,0.30)==env.bands,"oversized timestep rejected")
    env.reset()
    ck(env.bands.max()==0.0,"spectrum resets on Stop/discontinuity")
    raw[0]=0.005
    ck(env.apply(raw,0.1)[0]==0.0,"noise floor gates idle spectrum")

    var stage = load("res://scripts/OfflinePcmStaging.gd").new()
    var payload = PoolByteArray([0,0,0,0,255,127,0,128])
    ck(stage.enqueue(payload) and stage.buffered_bytes==8,"silent PCM bytes staged")
    ck(not stage.enqueue(PoolByteArray([0,0,0])),"unaligned frames rejected")
    ck(not stage.enqueue(PoolByteArray()),"empty frame rejected")
    var sink = FictionalPcmSink.new()
    ck(not stage.flush_to(sink) and stage.buffered_bytes==8,"pressure retains full block")
    sink.ready=true
    ck(stage.flush_to(sink) and sink.seen[0]==payload,"exact bytes committed")
    ck(stage.committed_frames==2 and stage.buffered_bytes==0,"frame counters accurate")
    ck(not stage.flush_to(sink),"no phantom output")
    var fill = PoolByteArray()
    for i in range(4096):
        fill.append(0)
    var filled = true
    for i in range(8):
        filled=filled and stage.enqueue(fill)
    ck(filled and stage.buffered_bytes==32768,"bounded backlog reaches exact cap")
    ck(not stage.enqueue(fill) and stage.buffered_bytes==32768,"backpressure never overwrites oldest")
    stage.reset()
    ck(stage.blocks.empty() and stage.buffered_bytes==0 and stage.committed_frames==0,"Stop empties backlog")
    var tv = load("res://Main.tscn").instance()
    get_root().add_child(tv)
    yield(create_timer(0.24),"timeout")
    ck(tv.music_ui!=null and tv.music_ui.play_button.has_focus(),"primary Play focus preserved")
    ck(not tv.offline_music.is_playing(),"no autoplay")
    ck(tv.music_ui.playlist_button!=null and tv.music_ui.playlist_button.focus_mode==Control.FOCUS_ALL,"playlist remote focus")
    ck(tv.music_ui.favorite_button.focus_mode==Control.FOCUS_ALL and tv.music_ui.repeat_button.focus_mode==Control.FOCUS_ALL,"favorites/repeat remote focus")
    ck(tv.music_ui.preset_button.focus_mode==Control.FOCUS_ALL,"visual preset remote focus")
    ck(tv.music_ui.playback_progress!=null and tv.music_ui.playback_progress.value==0,"no forged progress")
    ck(tv.music_ui.clock_label.text=="WAITING","MA startup waits without a fictional local timeline")
    ck(tv.preset_index==0,"original horizon visual default")
    ck(tv._cycle_visual_preset()=="NEBULA FLOW","second visual preset")
    ck(tv._cycle_visual_preset()=="STARFIELD","third visual preset")
    ck(tv._cycle_visual_preset()=="HORIZON GRID","visual presets wrap")
    ck(tv.offline_music.choose_playlist(1),"offline night flight chosen")
    ck(tv.offline_music.track_index==0 and not tv.offline_music.is_playing(),"playlist switch stays silent")
    ck(tv.offline_music.duration_seconds()>0.0,"real original Ogg metadata available")
    ck(tv.offline_music.progress_seconds()==0.0,"stopped progress zero")
    tv.music_ui._toggle_favorite()
    ck(tv.offline_music.playlists.is_favorite(0),"button toggles local favorites")
    tv.music_ui._cycle_repeat()
    ck(tv.offline_music.playlists.repeat_name()=="ONE","button sets repeat one")
    tv.music_ui._cycle_playlist()
    ck(not tv.offline_music.is_playing(),"cycling playlists never starts music")
    ck(tv.offline_music.player.bus=="Milkdrop","real FFT bus unmodified")
    ck(tv.ma_panel.catalog.token.empty(),"catalogue configuration untouched")
    tv.ma_panel._on_page({"kind":"tracks","offset":25,"items":[{"name":"Fictional Item"}],"may_have_more":true})
    ck("Page 2" in tv.ma_panel.results_label.text and not tv.ma_panel.next_button.disabled and not tv.ma_panel.previous_button.disabled,"MA page number and available paging actions")
    ck(tv.ma_panel.list.get_item_count()==1,"metadata-only fictional row")
    ck(not tv.ma_panel.preview_button.disabled == false,"fictional row never enables remote playback")
    tv.ma_panel._on_page({"kind":"playlist_items","offset":0,"items":[],"may_have_more":false})
    ck("0" in tv.ma_panel.results_label.text,"empty playlist has honest results count")
    ck(tv.ma_panel.catalog.token.empty(),"catalogue view never changes credentials")
    var dock = tv.music_ui.root.get_node("NowPlayingDock")
    ck(dock != null and dock.rect_size.y >= 260.0,"TV dock reserves two control rows and metadata")
    ck(tv.music_ui.playlist_button.rect_min_size.y >= 50,"remote playlist action TV target")
    ck(tv.music_ui.playback_progress.percent_visible == false,"progress never overlays tiny percentage text")
    ck(tv.music_ui.preset_button.text.begins_with("SCENE: "), "preset label visibly identifies mode")
    # Stress the PCM queue with fictional silent bytes, no speaker instance.
    var many = load("res://scripts/OfflinePcmStaging.gd").new()
    var fake = FictionalPcmSink.new()
    fake.ready = true
    var sequence_ok = true
    for _i in range(120):
        sequence_ok = sequence_ok and many.enqueue(payload)
        sequence_ok = sequence_ok and many.flush_to(fake)
    ck(sequence_ok and many.buffered_bytes==0 and many.committed_frames==240,"120 backpressure-free PCM cycles exact and leak-free")
    ck(fake.seen.size()==120,"120 PCM blocks preserved byte-for-byte")
    print("OFFLINE_TV_BATCH_CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures.empty() else 1)
