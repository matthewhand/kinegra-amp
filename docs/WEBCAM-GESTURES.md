# Experimental webcam controls

Webcam gestures are optional and off by default. In Settings, choose **Webcam gestures**, then a control mode. Enabling gestures also enables Webcam if a camera is connected. It never starts music. **Save Setup** remembers the choice. **Try Gestures / Return to Player** leaves Settings and opens fullscreen without starting music.

## Crossed-arms 3D controls

This mode opens an original lightweight 3D panel with Previous, Play/Pause, Next, Stop and Close. It uses shoulder-relative 2D wrist positions. Reaching across the camera image moves the cursors; forward punch depth is not measured.

1. Face the camera with both shoulders and wrists visible. Lower both hands for half a second.
2. Cross wrists near the opposite shoulders and hold for about two-thirds of a second. This opens controls without issuing a music command.
3. Lower hands briefly to arm the targets. Move a hand deliberately into a button and hold for two fresh samples, at least 0.2 seconds.
4. Lower hands again between actions. A 1.2-second cooldown and rearming prevent repeated skips from a held pose.

The panel closes on tracking loss, after 12 seconds idle, or with Close/Back. The remote remains usable: Left/Right selects a button, OK activates, Back closes. Controls can operate in a visible split pane after explicit opt-in, even when the other app has input focus. Pausing/hiding the app or opening a menu blocks recognition. Head and hip tracking are not prerequisites for arm controls.

## Direct gestures

Choose a unique preset for Previous, Play/Pause and Next. Right/left refer to the tracked person's anatomical side. Start with both wrists below their shoulders and shoulders level for one second, then perform the assigned action:

- Arm hold: raise a wrist above its shoulder and hold for 1.2 seconds.
- Both-arms hold: raise both wrists and hold for 1.7 seconds.
- Slow wave: raise the selected wrist, then move left → right → left → right across its shoulder over roughly 2–4 seconds. Three direction changes are required; the attempt resets after five seconds.
- Slow head shake: keep arms down and the body still; turn left → right → left → right slowly. This uses a 2D nose/eye-line signal, not measured 3D rotation.

After an action, a 2.5-second cooldown and a new neutral hold are required. Select the Kinegra Amp pane for direct gestures. Reminders appear on assigned transport controls and fullscreen. Arm controls check shoulders and wrists independently of low-confidence resting hips; active wrists must pass a higher confidence threshold than resting wrists.

## Tracking presentation and limits

The first valid face calibrates the avatar's neutral angle. Look forward and choose **Recenter Head / Look Forward** to calibrate again. This is an approximate visual rotation, not a face-capture model. Head placement remains attached to the torso rig.

After a frontal pose calibrates body proportions, narrow sideways poses can retain their scale when body anchors remain confident. Occluded joints still cannot be recovered reliably. Visual tracking loss freezes the last rendered avatar for 0.35 seconds, fades it out over 1.5 seconds, and fades it back over 0.2 seconds on return. This retained image never qualifies for a command. Status presentation waits for stable messages; safety gates act immediately.

Only fresh, distinct, identified Kinegra Cam frames qualify. Replayed frames, future/nonmonotonic capture times, stale data, source changes, tracking loss and low confidence cancel recognition. Inferred joints, demonstration poses and frozen frames never drive controls. Menus, pairing/confirmation popups and text editing block commands.

Actions use the existing enabled transport callbacks and this app's verified Music Assistant route or offline player. They cannot select an unrelated server output. An explicitly rearmed Play/Pause gesture can resume music; enabling the feature cannot.

The existing loopback feed is polled at a bounded 4 Hz, including with Visuals Off when gestures are explicitly enabled. Decorative rendering stays off. The 3D control panel only renders while open, at up to 10 Hz; the lowest audio-first budget uses event-driven frames. No new model, camera capture, recording or image retention is introduced.

Camera angle, crop, occlusion and inference rate affect accuracy. Similar dance movements can resemble a gesture. This is experimental: synthetic checks establish control guards and rendering, not reliable physical recognition. Tested camera hardware is limited to one Razer USB webcam; community testing and fixes are welcome.

## Verification

`test_tracking_panel_0846.gd` checks frozen pixels/fade, calibrated head/profile, status stability, cross/open/rearm/action flow, stale/replayed/weak observations and the actual 3D panel. Existing direct-gesture, raw-sample and UI integration tests cover command routing, neutral/cooldown, modal gates, saved setup and multiple viewports. Fixtures use synthetic landmarks and generated silent audio; they contain no camera or account data.
