extends Reference
# Hold the last rendered puppet, then fade it; never use this for recognition.
const HOLD_SECONDS=0.35
const FADE_SECONDS=1.5
const RETURN_SECONDS=0.20
var alpha=0.0
var loss_age=0.0
var loss_alpha=0.0
var was_live=false
func reset():
    alpha=0.0;loss_age=0.0;loss_alpha=0.0;was_live=false
func step(delta,live):
    var dt=clamp(float(delta),0.0,0.25)
    if live:
        was_live=true;loss_age=0.0
        alpha=min(1.0,alpha+dt/RETURN_SECONDS)
    else:
        if was_live:
            loss_age=0.0
            loss_alpha=alpha
            was_live=false
        loss_age+=dt
        alpha=loss_alpha*clamp(1.0-max(0.0,loss_age-HOLD_SECONDS)/FADE_SECONDS,0.0,1.0)
    return alpha
