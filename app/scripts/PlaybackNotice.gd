extends Reference
# A finite, event-driven now-playing notice. Repeated metadata is not an event.
const FADE_IN=1.6
const HOLD=6.0
const FADE_OUT=2.4
const PULSE_SECONDS=4.5
var key=""
var age=0.0
var alpha=0.0
var from_alpha=0.0
var active=false
var was_persistent=false

func show(value):
    if str(value)==key:return false
    key=str(value)
    reveal()
    return true

func reveal():
    from_alpha=alpha
    age=0.0
    active=true

func _ease(value):
    var t=clamp(value,0.0,1.0)
    return t*t*(3.0-2.0*t)

func step(delta,persistent=false,comfort=false):
    if is_nan(float(delta)) or is_inf(float(delta)):return alpha
    var dt=clamp(float(delta),0.0,0.1)
    if persistent or comfort:
        # A centered artwork card and reduced-motion metadata remain readable.
        alpha=min(1.0,alpha+dt/FADE_IN)
        was_persistent=true
        return alpha
    if was_persistent:
        was_persistent=false
        reveal()
    if not active:
        alpha=max(0.0,alpha-dt/FADE_OUT)
        return alpha
    age+=dt
    var envelope=1.0
    if age<FADE_IN:
        envelope=lerp(from_alpha,1.0,_ease(age/FADE_IN))
    elif age>FADE_IN+HOLD:
        envelope=1.0-_ease((age-FADE_IN-HOLD)/FADE_OUT)
    if age>=FADE_IN+HOLD+FADE_OUT:
        active=false
        alpha=0.0
    else:
        var pulse=.96+.04*cos(age*TAU/PULSE_SECONDS)
        alpha=clamp(envelope*pulse,0.0,1.0)
    return alpha
