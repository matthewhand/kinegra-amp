# Kinegra Amp

![Original Kinegra Amp banner](docs/branding/kinegra-amp-banner.png)

**Music, visualisers and webcam avatars for NVIDIA Shield.**

A music player and audio-reactive visualizer for NVIDIA SHIELD. Play from Music Assistant or your own local files, build a queue with a TV remote, and switch to fullscreen artwork, neon scenes and procedural dancers.

![Kinegra Amp playback, queues and fullscreen visuals](docs/readme/kinegra-amp-hero-1.0.10.gif)

*Staged desktop preview of the 1.0.10 interface using generated audio, fictional library entries and procedural dancers. [Demo details](docs/DEMO.md).*

## Install

**1.0.10 public beta · Android 8.0+ · ARM64**

Installation uses a signed APK from [Releases](https://github.com/matthewhand/kinegra-amp/releases) or a build you sign yourself. Install with an Android TV sideloading tool or ADB:

```sh
adb connect DEVICE_IP:ADB_PORT
adb install -r KinegraAmp-1.0.10.apk
```

Previously released as Kinegra ShieldAmp. This rename keeps the Android package, signing identity, saved settings, imported files and pairing storage compatible. Existing installations need the same signing identity to keep their data. The source builder produces an **unsigned** APK and never deploys it. [Build instructions](docs/BUILDING.md) · [Upgrade compatibility](docs/UPGRADING.md).

This distribution contains **no bundled music or private cover artwork**. Connect Music Assistant or import your own MP3/Ogg files. It starts silently and never replaces your queue with demonstration music.

## Play music

1. Open **Music Assistant → Settings** and enter your server address and library access token. Choose **Connect library**. **Remember access** stores accepted credentials using Android Keystore; leaving it off keeps access session-only.
2. Browse **Albums**, **Tracks** or **Playlists**, using **Search** and page controls to find music. Select a collection to browse its tracks.
3. Select a track or choose **Play** for a collection. Playback connects automatically; approve pairing on Music Assistant when requested. Your selected music starts after pairing.
4. **Add to Queue** appends without interrupting playback. **Queue Page** adds the displayed tracks. **View Queue** opens upcoming items; Back returns to the same library selection.

Playback uses Kinegra Amp's own Sendspin output in this app window. The main **Play** resumes its queue. **Pause**, **Previous**, **Next**, **Stop** and timed-track **−10 s / +10 s** have separate controls. The app remembers the server/player identity and library position; Music Assistant owns its queue and playback state. Startup never autoplays.

Use the remote D-pad and OK or the controller D-pad and A. Right moves from the selected library row to Play and then Add to Queue; Left returns to that row. Back/B closes the current dialog before leaving the library. [Navigation and queue details](docs/MA-LIBRARY-REMOTE.md).

## Music on the device

Choose **Offline Library → Import from USB / Internal Storage**. The Android picker copies selected MP3/Ogg files into app storage; it leaves originals unchanged. An empty library focuses Import. **Delete Copy** removes the app's copy after confirmation. Imports are bounded to 32 files per operation and 64 MiB per file. Music Assistant streaming is not an offline-download service. [Offline library](docs/OFFLINE-LIBRARY.md).

**Experimental:** save a local Music Assistant queue using **Queue → Save Queue Offline**, then **Play Saved Queue**. Complete copies support local seeking and playback without the server. This optional feature needs the included file-source helper on your music host; subscription streams are unsupported. A metadata-read failure can stop a batch; completed files remain playable, and automatic resume is still [being tracked](https://github.com/matthewhand/kinegra-amp/issues/1). See [offline copying](docs/OFFLINE-COPYING.md).

## Artwork, dancers and webcam

Artwork appears during buffering and the first two healthy seconds of playback, then chosen visuals return. With visuals off, one cover is centered in the available canvas. A large cover replaces the small playback thumbnail; fullscreen enlarges the same artwork and keeps its text together. **Visuals On / Off**, **Scene** and **Fullscreen** control the presentation. Back/B exits fullscreen. With visuals on, the fullscreen now-playing card fades in slowly, pulses gently and fades away; a new track or remote interaction reveals it again. Centered artwork stays visible when visuals are off, and Reduced motion disables the pulse. Adaptive quality reduces decorative work under load and restores it gradually; Audio first keeps artwork visible.

Optional webcam avatars use Kinegra Cam's local pose feed. Backing dancers keep distinct appearances and adapt to a conservative tempo estimate. Optional direct gestures and crossed-arms controls start disabled and remain experimental. [Webcam setup and limits](docs/WEBCAM-GESTURES.md).

Kinegra Amp consumes body landmarks; it does not bundle an inference model. The visuals and beat analysis use procedural animation and signal processing. App volume is in Settings and shows a persistent indicator when below 100%.

## Web remote

Open **Settings → Web remote (trusted LAN)** to enable browser controls. Visit the address shown there and enter its access key. **Require access key** can be turned off for your configured trusted private IP ranges; it is on by default. The remote offers playback status and transport controls, searchable Music Assistant Tracks/Albums/Playlists, collection paging, Play, Add to Queue, Queue Page and an upcoming-queue view. Adding appends without issuing Play; it uses only Kinegra Amp’s verified output. Production builds start with the service **off**. Development builds start **on**. Each build type remembers its own choice. [Remote setup and API](docs/WEB-REMOTE.md) · [Python command-line remote](docs/CLI.md).

## Compatibility and limits

Development hardware is an original NVIDIA SHIELD on Android 11 with a 3440 × 1440 display and one Razer USB webcam. Matthew has tested every version through 1.0.10. Standard TV/portrait layouts have automated coverage; broader hardware, camera and sustained combined-load coverage remains limited. [Validation and remaining work](docs/VALIDATION.md).

Collection browsing uses bounded snapshots: 25-row local pages, at most 2,000 returned tracks and a 2 MiB response cap. Queue reordering, paused-track seeking and radio seeking are not supported. [Development](docs/DEVELOPMENT.md) · [Privacy](docs/PRIVACY.md).

[Current release scope and validation](docs/RELEASE.md).

## License

Project code, documentation, original artwork and hero media use the [MIT License](LICENSE). Dependencies retain their own terms. Read **Settings → Licenses & notices** in the app or the [third-party notices](docs/THIRD-PARTY-NOTICES.md). No music, private covers, signing keys or runtime credentials are included.
