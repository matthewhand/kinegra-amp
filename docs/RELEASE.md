# Kinegra Amp 1.0.19 public beta

**[Download the signed 1.0.19 beta APK](https://github.com/matthewhand/kinegra-amp/releases/download/v1.0.19/KinegraAmp-1.0.19.apk)** · Android 8.0+ · ARM64 · build 100

[Install or update](UPGRADING.md) · [Release assets and checksums](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.19)

## What changed since 1.0.17

- **App Volume** is selected when you open **Settings**. Press Left or Right to change Amp’s level. Amp saves it. In Split View, the TV volume changes the combined output from both panes.
- Local files can keep playing in the background, like Music Assistant streams. [Local-file background playback](https://github.com/matthewhand/kinegra-amp/pull/4)
- Offline queue saving skips entries with missing track metadata so the rest of the queue can continue. This release also improves recovery after an incomplete offline catalog write. [Offline queue saving](OFFLINE-COPYING.md)
- A connected browser can request Music Assistant playback after the web remote’s access checks. The web remote is off by default and requires its access key by default when enabled. [Web remote setup](WEB-REMOTE.md)

## Beta coverage

The 1.0.19 source passed host tests for remote volume adjustment and persistence. The SHIELD playback check used the preceding 1.0.18 patch with the same App Volume change. Device testing has used an original SHIELD, SHIELD Experience 9.x (Android 11), an ultrawide display and one Razer USB webcam. Other hardware and long sessions have limited coverage. [Testing and compatibility](VALIDATION.md)

Webcam tracking, gestures and bulk offline queue copying are experimental. Webcam tracking needs a Kinegra Cam pose feed. Older file-source helpers restart the interrupted track when resuming and retain completed copies. [Webcam setup](WEBCAM-GESTURES.md) · [Offline copying](OFFLINE-COPYING.md)

The release includes its signed APK, exact source archive, licence bundle, component inventory, metadata and checksums. Those files remain tied to the release tag; the current source and README demo can contain later changes. Original code, documentation, artwork and hero media use MIT; dependencies retain their terms.

[Updates](UPGRADING.md) · [Build](BUILDING.md) · [Testing](VALIDATION.md)
