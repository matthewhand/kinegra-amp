extends Reference
# Bounded onset-tempo estimate from real normalized FFT only. Not a universal
# musical beat detector; ambiguous rhythms intentionally return no estimate.
const MIN_INTERVAL_MS=300
const MAX_INTERVAL_MS=1334
const MAX_INTERVALS=8
const MIN_INTERVALS=5
const MIN_CONFIDENCE=0.72
var epoch=-1
var previous=[]
var intervals=[]
var last_sample=-1
var last_onset=-1
var last_energy=-1
var flux_average=0.0
var bpm=0.0
var confidence=0.0
var family="gentle"
var pending_family=""
var pending_count=0
var source_live=false
func reset():
    previous=[];intervals=[];last_sample=-1;last_onset=-1;last_energy=-1
    flux_average=0.0;bpm=0.0;confidence=0.0;family="gentle";pending_family="";pending_count=0;source_live=false
func _number(value,low,high):
    return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and value>=low and value<=high
func observe(now,bands,live,source_epoch):
    if typeof(now)!=TYPE_INT or now<0 or typeof(source_epoch)!=TYPE_INT or source_epoch<0 or not live:
        reset()
        return false
    if source_epoch!=epoch:
        reset();epoch=source_epoch
    if last_sample>=0 and (now<=last_sample or now-last_sample>500):
        if now==last_sample:return false
        reset();epoch=source_epoch
    if typeof(bands)!=TYPE_ARRAY or bands.size()!=16:
        reset();return false
    for value in bands:
        if not _number(value,0.0,1.0):
            reset()
            return false
    source_live=true
    var energy=0.0
    var flux=0.0
    for index in range(16):
        var weight=1.5 if index<8 else 0.5
        energy+=float(bands[index])*weight/16.0
        if previous.size()==16:flux+=max(0.0,float(bands[index])-float(previous[index]))*weight/16.0
    if energy>0.0001:last_energy=now
    var elapsed=float(now-last_sample)/1000.0 if last_sample>=0 else 0.02
    var onset=previous.size()==16 and flux>max(0.004,flux_average*2.5) and (last_onset<0 or now-last_onset>=240)
    flux_average=lerp(flux_average,flux,clamp(elapsed/0.6,0.0,1.0))
    previous=bands.duplicate()
    last_sample=now
    if onset:
        if last_onset>=0:
            var interval=now-last_onset
            if interval>=MIN_INTERVAL_MS and interval<=MAX_INTERVAL_MS:
                intervals.append(float(interval))
                if intervals.size()>MAX_INTERVALS:intervals.pop_front()
                _estimate()
            else:
                intervals.clear();confidence=0.0;bpm=0.0;family="gentle";pending_family="";pending_count=0
        last_onset=now
    return onset
func _estimate():
    if intervals.size()<MIN_INTERVALS:
        confidence=0.0
        return
    var sorted=intervals.duplicate();sorted.sort()
    var median=float(sorted[int(sorted.size()/2)])
    var inliers=[]
    for interval in intervals:
        if abs(interval-median)<=median*0.14:inliers.append(interval)
    if inliers.size()<MIN_INTERVALS or float(inliers.size())/intervals.size()<0.75:
        confidence=0.0;pending_family="";pending_count=0
        return
    var mean=0.0
    for interval in inliers:mean+=interval/float(inliers.size())
    var deviation=0.0
    for interval in inliers:deviation+=abs(interval-mean)/float(inliers.size())
    confidence=clamp((1.0-deviation/mean*4.0)*float(inliers.size())/intervals.size(),0.0,1.0)
    if confidence<MIN_CONFIDENCE:return
    var candidate=60000.0/mean
    bpm=candidate if bpm<=0.0 else lerp(bpm,candidate,0.35)
    var target="slow" if bpm<90.0 else ("medium" if bpm<140.0 else "fast")
    if family=="slow" and bpm<96.0:target="slow"
    elif family=="medium" and bpm>=84.0 and bpm<146.0:target="medium"
    elif family=="fast" and bpm>=134.0:target="fast"
    if family=="gentle":
        family=target;pending_family="";pending_count=0
    elif target==family:
        pending_family="";pending_count=0
    else:
        pending_count=pending_count+1 if pending_family==target else 1
        pending_family=target
        if pending_count>=3:
            family=target;pending_family="";pending_count=0
func snapshot(now):
    var result={"kind":"none","bpm":0.0,"phase":0.0,"confidence":0.0,"family":"gentle","signal":false}
    if typeof(now)!=TYPE_INT or not source_live or last_sample<0 or now<last_sample or now-last_sample>500:return result
    var period=60000.0/bpm if bpm>0.0 else 1000.0
    var signal_fresh=last_energy>=0 and now-last_energy<=max(1500.0,period*2.5)
    result["signal"]=signal_fresh
    if not signal_fresh or last_onset<0 or now-last_onset>max(1800.0,period*3.0) or confidence<MIN_CONFIDENCE:return result
    result["kind"]="estimated_onsets"
    result["bpm"]=bpm
    result["phase"]=fposmod(float(now-last_onset)/period,1.0)
    result["confidence"]=confidence
    result["family"]=family
    return result
