# Kinegra Amp 1.0.16 public beta

Play Music Assistant streams and local MP3/Ogg files inside Amp, build a queue, and choose artwork, animated scenes or optional webcam avatars. The opt-in web remote and CLI provide playback and library controls.

This beta fixes slow Pause Saving during a stalled offline download. Amp closes the active request and keeps completed chunks. On SHIELD, a live test resumed a deliberately stalled track at 1 MiB and finished the transfer. The offline copy limit is 8,192 queue entries, and the Offline Library supports up to 4,096 unique files, subject to storage.

Download `KinegraAmp-1.0.16.apk` from [Releases](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.16). It supports ARM64 and Android 8.0+. Production starts with the web remote disabled, access-key authentication enabled and no autoplay. No music is bundled.

Compatibility testing has used an original NVIDIA SHIELD with SHIELD Experience 9.x (Android 11), an ultrawide display and one Razer USB webcam. Other hardware and long-session coverage is limited. Webcam tracking requires a separately configured Kinegra Cam pose feed; tracking and gestures remain experimental.

**Bulk offline queue copying is experimental.** Older file-source helpers restart the interrupted track. Completed copies remain available. [Offline copying](OFFLINE-COPYING.md).

The release includes its signed APK, exact source archive, licence bundle, component inventory, metadata and checksums. Those files remain tied to the release tag; the current source and README demo can contain later changes. Original code, documentation, artwork and hero media use MIT; dependencies retain their terms.

[Updates](UPGRADING.md) · [Build](BUILDING.md) · [Testing](VALIDATION.md)
