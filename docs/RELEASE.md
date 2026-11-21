# Kinegra Amp 1.0.17 public beta

Play Music Assistant streams and local MP3/Ogg files inside Amp, build a queue, and choose artwork, animated scenes or optional webcam avatars. The opt-in web remote and CLI provide playback and library controls.

This beta (build 96) adds Music Assistant background playback. **Keep Music Assistant playing in the background** is on by default in Settings. Music continues through Android Home and return. Turn it off to pause playback when you leave; it stays paused when you return until you press Play. Use **Save Setup** to remember this choice after restarting Amp. Amp does not start playback automatically on a cold start.

It also includes the earlier offline-copy improvements: Pause Saving closes a stalled request and keeps completed chunks, and Resume Saving continues from the saved range with the current file-source helper. The offline copy limit is 8,192 queue entries, and the Offline Library supports up to 4,096 unique files, subject to storage.

Download `KinegraAmp-1.0.17.apk` from [Releases](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.17). It supports ARM64 and Android 8.0+. Production starts with the web remote disabled, access-key authentication enabled and no autoplay. No music is bundled.

Local-file background playback was added in [later source changes](https://github.com/matthewhand/kinegra-amp/pull/4). The 1.0.17 APK does not contain that change; source on `main` can be newer than the published download.

Compatibility testing has used an original NVIDIA SHIELD with SHIELD Experience 9.x (Android 11), an ultrawide display and one Razer USB webcam. Other hardware and long-session coverage is limited. Webcam tracking requires a separately configured Kinegra Cam pose feed; tracking and gestures remain experimental.

**Bulk offline queue copying is experimental.** Older file-source helpers restart the interrupted track. Completed copies remain available. [Offline copying](OFFLINE-COPYING.md).

The release includes its signed APK, exact source archive, licence bundle, component inventory, metadata and checksums. Those files remain tied to the release tag; the current source and README demo can contain later changes. Original code, documentation, artwork and hero media use MIT; dependencies retain their terms.

[Updates](UPGRADING.md) · [Build](BUILDING.md) · [Testing](VALIDATION.md)
