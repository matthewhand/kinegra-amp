# Backup dancers and tracked-avatar proportions

Backup casting excludes the active lead style and the other backup. Valid existing backup choices are retained; a conflicting slot is filled deterministically. If fewer distinct styles are available than slots, the extra slot stays empty.

Backup choreography follows a bounded estimate of repeated onsets in real PCM-derived FFT bands. After at least five consistent intervals, slow, medium and fast tempo ranges select different original movement families, playback speed and phase offsets. Confidence, robust interval filtering and family hysteresis limit abrupt changes. This is an onset-tempo estimate, not a guarantee of musical beat or downbeat recognition: syncopation, half/double tempo and sparse or irregular music can be ambiguous. An unreliable estimate uses gentle motion without claiming a BPM. The existing explicitly configured metronome takes priority and remains identified as configured. Demo data never trains the estimator.

Silence or source loss revokes the estimate. Source stop clears backup poses. Reduced motion freezes their pose; visual-off and zero render budget keep the renderers idle and preserve style preferences. No music, camera images or external assets are retained by these helpers.

The original procedural 3D avatar uses a shared shoulder-width unit for head, neck, torso, joints and camera framing. The head is constrained to a fixed shoulder-relative height, with bounded lateral smoothing and an explicit neck joining it to the shoulders. Looking up/down changes bounded, smoothed approximate pitch from the nose-to-eye-line ratio instead of lifting the head off the neck. Small near-neutral variation calibrates slowly; large tilts cannot calibrate themselves as neutral. This remains a 2D approximation, not 3D head tracking. This preserves screen-plane pose motion without inventing tracking depth. Full-body and seated poses use the same framing proportions as synthetic backups. Weak required shoulder/hip anchors supplied to the renderer hide the rig rather than displaying an invented torso; weak or implausible nose evidence hides the head and neck. The existing upstream portrait visualizer can reconstruct one missing shoulder/hip and missing limbs; that path remains explicitly labelled DEMO LIMBS and is separate from the raw samples used by gesture recognition. Tight crops can therefore temporarily hide the 3D rig while the independent 2D tracking remains available.

All cast members share the lead's body/portrait/face view mode. Each camera still centers its own pose and scales distance and portrait offset by its own shoulder unit, so a seated lead and full-body backups use the same normalized zoom without overlapping stage positions. Existing preferences remain the source of the single view choice.

Five original shader finishes distinguish the existing styles: circuit routes, brushed chevrons, triangular facets, cross-star weave and recessed panels. These use bounded GLES2 arithmetic with no textures, files, loops, extra rendering passes or external artwork. Surface motifs are static; reduced motion freezes the existing time-driven scene effect and a zero budget disables rendering.

## Verification

- `app/tests/test_backup_tempo.gd`: synthetic 60/110/170 BPM onsets, jitter, silent gaps, silence, constant energy, irregular rhythms, confidence and family hysteresis, distinct casting and speed, manual tempo, reduced motion and source cleanup.
- `app/tests/test_backup_stage.gd`: integrated cast changes, actual-source gating, move families, preference preservation and render-off behavior.
- `app/tests/test_avatar_anatomy.gd`: generic full-body, seated, partial, jitter and weak-confidence landmarks; head/neck endpoints, shared proportions and render-off behavior.
- `app/tests/test_avatar_surface_framing.gd`: matching normalized camera distance/crop with distinct pose origins, rendered style differences, static reduced-motion images and zero-budget behavior.
- `app/tests/test_avatar_anatomy_visual.gd`: optional generic renders outside the repository; contains no person or camera capture.

Host fixtures verify these invariants, not real-camera tracking quality or beat alignment for every track. Physical controller, camera and listening acceptance remains a separate device check.
