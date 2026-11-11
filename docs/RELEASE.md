# Kinegra Amp 1.0.13 public beta

Play Music Assistant streams and local MP3/Ogg files inside Amp, build a queue, and choose artwork, animated scenes or optional webcam avatars. The opt-in web remote and CLI provide playback and library controls.

Music Assistant playback shows a waiting status until audio reaches the mixer. This beta improves saved-queue resume, playback errors and recovery when the connection drops. On the Shield, playback resumed automatically on the first retry after an interruption to the active playback connection.

Download `KinegraAmp-1.0.13.apk` from [Releases](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.13). It supports ARM64 and Android 8.0+. Production starts with the web remote disabled, access-key authentication enabled and no autoplay. No music is bundled.

Compatibility testing has used an original NVIDIA SHIELD with SHIELD Experience 9.x (Android 11), an ultrawide display and one Razer USB webcam. Other hardware and long-session coverage is limited. Webcam tracking requires a separately configured Kinegra Cam pose feed; tracking and gestures remain experimental.

**Bulk offline queue copying is experimental.** Metadata failures can stop a batch; completed copies remain playable, but automatic retry and durable resume are not implemented. [Offline copying](OFFLINE-COPYING.md).

The release includes its signed APK, exact source archive, licence bundle, component inventory, metadata and checksums. Those files remain tied to the release tag; the current source and README demo can contain later changes. Original code, documentation, artwork and hero media use MIT; dependencies retain their terms.

[Updates](UPGRADING.md) · [Build](BUILDING.md) · [Testing](VALIDATION.md)
