# Testing and compatibility

## Run checks

```sh
python3 tools/check_source.py
python3 -m unittest discover -s tools
python3 -m unittest discover -s packaging
```

[Host checks](BUILDING.md#host-checks) run selected Godot regressions with generated music/artwork, fictional metadata, isolated state and Dummy audio. They cover library/queue actions, direct Play and pairing/reconnect, buffering/recovery, local imports, offline copying, artwork and layout. Browser and loopback CLI checks cover authentication, origin restrictions, bounded requests and ambiguous responses.

The Android builder verifies pinned source/dependency inputs, package/version, release settings, licences, native hashes and 16 KiB alignment. Signing is separate. Published binaries and source archives are bound to their release tag; later main-branch changes are not a replacement for those files.

## Device coverage

Tested on an original NVIDIA SHIELD with SHIELD Experience 9.x (Android 11), a 3440 × 1440 display and one Razer USB webcam, including in-app Music Assistant playback with webcam tracking. Other cameras, controllers, firmware, physical standard-TV/portrait layouts and sustained combined-load sessions have limited coverage. Contributions and reproducible reports are welcome.

Webcam avatars consume external body landmarks; no inference model is bundled. Head pose is approximate, tracking can jitter or lose a body, and gestures remain experimental.

Bulk offline queue copying is experimental. Temporary errors retry with a limit per track. Interrupted copies retain a checkpoint and verified byte ranges when using the current file-source helper. [Offline copying](OFFLINE-COPYING.md).

Reports should include app/server versions, device, input method, layout, duration and reproduction steps. Remove credentials, private addresses, access URLs, personalized library data and camera imagery.
