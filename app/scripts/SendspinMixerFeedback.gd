extends Reference
# Estimates frames consumed by Godot's mixer from generator free-space changes.
# This is NOT a hardware callback or measured DAC time; driver latency is an
# estimate and must be validated per device before multi-room synchronization.
var generation=-1
var capacity=0
var queued=0
const RATE=48000
const CLOCK_WINDOW=32
const CLOCK_MAX_SLEW=0.0005 # 500 ppm; track slow clock drift, not driver timestamp quantization.
var last_finish_us=0
var clock_frames=0
var clock_offset_us=0.0
var clock_offsets=[]
var clock_offset_sum=0.0
func reset():
    generation=-1
    capacity=0
    queued=0
    last_finish_us=0
    reanchor_clock()
func reanchor_clock():
    clock_frames=0
    clock_offset_us=0.0
    clock_offsets=[]
    clock_offset_sum=0.0
func begin(gen,free_frames):
    reset()
    if typeof(gen)!=TYPE_INT or gen<0 or typeof(free_frames)!=TYPE_INT or free_frames<1 or free_frames>96000:
        return false
    generation=gen
    capacity=free_frames
    return true
func pushed(gen,frames):
    if generation!=gen or typeof(frames)!=TYPE_INT or frames<1 or frames>capacity or queued+frames>96000:
        return false
    queued+=frames
    return true
func sample(gen,free_frames,now_us,since_mix_us,driver_latency_us):
    if generation!=gen or typeof(free_frames)!=TYPE_INT or free_frames<0 or free_frames>capacity:
        return {}
    for value in [now_us,since_mix_us,driver_latency_us]:
        if typeof(value)!=TYPE_INT or value<0: return {}
    if since_mix_us>1000000 or driver_latency_us>2000000 or now_us<since_mix_us:
        return {}
    var occupied=capacity-free_frames
    if occupied>queued: return {} # Counter drift: do not invent consumption.
    var consumed=queued-occupied
    if consumed==0: return {"frames":0}
    var raw_finish=now_us-since_mix_us+driver_latency_us
    var next_frames=clock_frames+consumed if not clock_offsets.empty() else 0
    var raw_offset=float(raw_finish)-float(next_frames)*1000000.0/float(RATE)
    var next_sum=clock_offset_sum+raw_offset
    if clock_offsets.size()==CLOCK_WINDOW:next_sum-=clock_offsets[0]
    var target_offset=next_sum/float(min(CLOCK_WINDOW,clock_offsets.size()+1))
    # Driver mix timestamps move in blocks; frame consumption advances smoothly.
    # Acquire the clock at a new stream/real underflow, then track only slow
    # drift. Counts always come from observed generator free-space changes.
    var next_offset=target_offset
    if clock_offsets.size()>=CLOCK_WINDOW:
        var max_slew=float(consumed)*1000000.0/float(RATE)*CLOCK_MAX_SLEW
        next_offset=clock_offset_us+clamp(target_offset-clock_offset_us,-max_slew,max_slew)
    var finish=max(int(next_offset+float(next_frames)*1000000.0/float(RATE)),last_finish_us)
    if finish<now_us-250000 or finish>now_us+2000000:return {}
    return {"frames":consumed,"finish_us":finish,"remaining":occupied,"clock_frames":next_frames,"clock_offset":next_offset,"raw_offset":raw_offset}
func committed(gen,report):
    # Call only after the SDK accepts the report. Failed reports are retried.
    if generation!=gen or typeof(report)!=TYPE_DICTIONARY or not report.has("frames") or not report.has("remaining") or not report.has("finish_us"):
        return false
    if report["frames"]<=0 or report["frames"]+report["remaining"]!=queued or report["finish_us"]<last_finish_us:
        return false
    for key in ["clock_frames","clock_offset","raw_offset"]:
        if not report.has(key):return false
    if typeof(report["clock_frames"])!=TYPE_INT or report["clock_frames"]<0:return false
    for key in ["clock_offset","raw_offset"]:
        if typeof(report[key])!=TYPE_REAL or is_nan(report[key]) or is_inf(report[key]):return false
    var expected_frames=clock_frames+report["frames"] if not clock_offsets.empty() else 0
    if report["clock_frames"]!=expected_frames:return false
    queued=report["remaining"]
    clock_frames=report["clock_frames"]
    clock_offset_us=report["clock_offset"]
    if clock_offsets.size()==CLOCK_WINDOW:clock_offset_sum-=clock_offsets.pop_front()
    clock_offsets.append(report["raw_offset"])
    clock_offset_sum+=report["raw_offset"]
    last_finish_us=report["finish_us"]
    return true
