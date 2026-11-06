# Validation and support scope

The released build is Kinegra Amp **1.0.10 / code 86**, package `org.local.tegramilkdrop`. It was installed in place with the original signing identity, saved data and pairing storage retained. Matthew confirms that he has tested every version through 1.0.10. This is a public beta, with limited hardware and endurance coverage.

## Release evidence

The clean Linux offline build compiles the codec, patched Sendspin adapter and Android secure-storage/import plugin from pinned public inputs. The Godot audio-runtime recipe reproduces its recorded native-library hash. Package checks cover version, original-certificate verification, non-debuggable and backup-disabled settings, single-task launch, launcher artwork, 16 KiB native/package alignment, retained licence texts and absence of bundled music or private runtime state.

Host fixtures use generated audio, fictional library metadata, isolated state and Dummy audio. Focused checks cover direct Play and pairing/reconnect, queue paging/editing, buffering/recovery, local import identities, bounded offline copying, single-cover presentation and narrow/wide layout policies. Browser and real-loopback CLI checks cover keyed and trusted-range access, origin restrictions, bounded requests, browse/queue controls and ambiguous-response handling. Automated results are evidence for those cases, not a claim that every physical layout or gesture works perfectly.

The final source manifest binds the exact published files and modes. Source/history and uncompressed APK scans, dependency notice verification and release checksums are checked independently during publication. The release retains the reviewed APK: subsequent source changes concern documentation, provenance and an origin-rejection test fixture only. No application/runtime input is changed by that publication overlay.

## Physical scope

Development uses an original NVIDIA SHIELD on Android 11, a 3440 × 1440 display and one Razer USB webcam. Owner listening has confirmed working in-app Music Assistant playback, including a webcam session. Other cameras, firmware, physical standard-TV/portrait layouts and sustained combined-load sessions have limited coverage. Contributions and reproducible reports for other hardware are welcome.

Webcam avatars consume external body landmarks; no inference model is bundled. Head pose is approximate, tracking can jitter or lose a body, and optional gestures remain experimental. Broader real-person gesture reliability and UI/framing polish remain beta limitations.

## Offline copying

Bulk Music Assistant queue saving is experimental. Metadata failures can stop a batch; completed copies remain playable. Automatic retry and durable resume are not implemented. Ordinary streaming and existing local-file playback are separate workflows. See [offline copying](OFFLINE-COPYING.md).

## Reports

Include app/server versions, device, input method, display/layout, duration and reproduction steps. Remove credentials, private addresses, opaque access URLs, personalized library data and camera imagery from reports. A version number is not an independent quality score.
