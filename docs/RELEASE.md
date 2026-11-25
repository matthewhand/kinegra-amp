# Kinegra Amp 1.0.19 public beta

Play Music Assistant streams and local MP3/Ogg files inside Amp, build a queue, and choose artwork, animated scenes or optional webcam avatars. The opt-in web remote and CLI provide playback and library controls.

This beta (build 100) opens **Settings** with **App Volume** selected. Press Left or Right on the remote to adjust Amp independently of the TV volume. Amp saves the level for your next session.

Since the 1.0.17 beta, background playback now covers local files as well as Music Assistant. This release also carries forward fixes for queue entries with missing metadata, offline catalog recovery, and authorized playback from the web remote.

Download `KinegraAmp-1.0.19.apk` from [Releases](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.19). It supports ARM64 and Android 8.0+. Production starts with the web remote disabled and access-key authentication enabled. Playback starts on request. No music is bundled.

Compatibility testing has used an original NVIDIA SHIELD with SHIELD Experience 9.x (Android 11), an ultrawide display and one Razer USB webcam. Other hardware and long-session coverage is limited. Webcam tracking requires a separately configured Kinegra Cam pose feed; tracking and gestures remain experimental.

**Bulk offline queue copying is experimental.** Older file-source helpers restart the interrupted track. Completed copies remain available. [Offline copying](OFFLINE-COPYING.md).

The release includes its signed APK, exact source archive, licence bundle, component inventory, metadata and checksums. Those files remain tied to the release tag; the current source and README demo can contain later changes. Original code, documentation, artwork and hero media use MIT; dependencies retain their terms.

[Updates](UPGRADING.md) · [Build](BUILDING.md) · [Testing](VALIDATION.md)
