# Kinegra Amp 1.0.14 public beta

Play Music Assistant streams and local MP3/Ogg files inside Amp, build a queue, and choose artwork, animated scenes or optional webcam avatars. The opt-in web remote and CLI provide playback and library controls.

This beta adds offline queue retries, checkpoints that survive an app restart, and byte-range resume with the updated file-source helper. Audio deduplication preserves intentional repeats in the saved queue. An isolated Shield test using the same compiled copying code resumed at 1 MiB and saved three entries as two files.

Download `KinegraAmp-1.0.14.apk` from [Releases](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.14). It supports ARM64 and Android 8.0+. Production starts with the web remote disabled, access-key authentication enabled and no autoplay. No music is bundled.

Compatibility testing has used an original NVIDIA SHIELD with SHIELD Experience 9.x (Android 11), an ultrawide display and one Razer USB webcam. Other hardware and long-session coverage is limited. Webcam tracking requires a separately configured Kinegra Cam pose feed; tracking and gestures remain experimental.

**Bulk offline queue copying is experimental.** Older file-source helpers restart the interrupted track. Completed copies remain available. [Offline copying](OFFLINE-COPYING.md).

The release includes its signed APK, exact source archive, licence bundle, component inventory, metadata and checksums. Those files remain tied to the release tag; the current source and README demo can contain later changes. Original code, documentation, artwork and hero media use MIT; dependencies retain their terms.

[Updates](UPGRADING.md) · [Build](BUILDING.md) · [Testing](VALIDATION.md)
