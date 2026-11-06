# Developing Kinegra Amp

Kinegra Amp uses Godot 3.6.3/GLES2, GDScript, native audio adapters and Android plugins. Start with [building](BUILDING.md), [validation](VALIDATION.md) and [privacy](PRIVACY.md).

| Path | Purpose |
| --- | --- |
| `app/` | Player, library/queue UI, shaders, avatars and focused GDScript fixtures |
| `native/` | MP3/Ogg codec, Sendspin adapter and reviewed source patches |
| `android_secure_storage/` | Keystore credentials, pairing identity, USB presence and file imports |
| `android_playback_capture/` | Separate optional capture prototype; current player UI does not enable it |
| `packaging/` | Explicit-input music-free build and Android package checks |
| `review/` | Source integrity, dependency pins and disposable synthetic-host tooling |
| `third_party/` | Exact dependency/notice provenance and Gradle runtime lock |

## Current limitations

The Music Assistant server owns its queue and playback position; current/next metadata snapshots can lag. Collection snapshots are bounded to 2,000 tracks and 2 MiB. Search applies to retrieved collection tracks, while library album/track searches use server pages. Queue reordering, paused-track seeking and radio seeking are not implemented.

Broader physical listening, remote/gamepad, webcam hotplug/gestures, regular-TV/portrait and sustained combined-load acceptance remain open. Earlier Shield builds exercised the same in-app streaming architecture; automated checks do not certify the new build's audible or hardware behavior. Optional gestures use approximate 2D body landmarks and are experimental. [Client comparison](CLIENT-COMPARISON.md).

Adaptive visuals use frame timing, buffer recovery, current-process CPU time and Android thermal status. They do not measure whole-device or GPU idle capacity. Explicit gestures may keep bounded pose polling active with decorative visuals off.

The optional [web remote](WEB-REMOTE.md) supplies authenticated LAN transport/status, searchable Music Assistant browsing, collection paging, Play/Add to Queue/Queue Page and an upcoming-queue view. Web queue removal/reordering, offline-library control, settings parity and a CLI remain future work. Development defaults on and production defaults off, with separate saved preferences.

## Tests

Use generated audio, synthetic landmarks and fresh XDG state. The [host builder](BUILDING.md#host-checks) compiles its codec and imports fixtures before selected tests. Relevant suites include offline accessibility, public music-free startup/migration, library/queue routing, modal focus, direct Play/resume and tracking policies. The public music-free fixture must run with the production empty `SOURCES` and cover arrays; its generated Ogg input remains test-only.

Native stream and bounds fixtures use pinned dependency sources and isolated loopback services. Historical Android proofs bind their exact binaries; a newly compiled native hash does not inherit a prior device receipt. Hardware acceptance is recorded separately from host/source tests.

When changing dependencies, review the pinned source/patches, native alignment, full linked notices and actual Gradle artifact/POM lock. The build fails on unreviewed runtime dependency or license changes. Source integrity uses a complete path/hash/mode manifest; regenerate it when preparing an intentional source snapshot.

## Contributing

Include the version, device, input method and reproduction steps. Add a focused regression for behavioral changes. Keep credentials, private library metadata, camera imagery and generated signing keys out of commits. Code, documentation, original artwork and hero media use MIT; retain upstream notices with third-party material.
