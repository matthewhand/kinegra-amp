extends Reference
# Presentation only; recognition and safety state never wait for this label.
const STABLE_MS=500
const MIN_VISIBLE_MS=1800
var shown=""
var changed_at=-1
var candidate=""
var candidate_at=-1
func reset():
    shown="";changed_at=-1;candidate="";candidate_at=-1
func update(value,now,urgent=false):
    var text=str(value)
    if shown.empty() or urgent:
        if shown!=text:
            shown=text
            changed_at=now
        candidate="";candidate_at=-1
        return shown
    if text==shown:
        candidate="";candidate_at=-1
        return shown
    if candidate!=text:
        candidate=text
        candidate_at=now
    if now-candidate_at>=STABLE_MS and now-changed_at>=MIN_VISIBLE_MS:
        shown=text;changed_at=now;candidate="";candidate_at=-1
    return shown
