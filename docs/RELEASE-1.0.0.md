# ShieldAmp 1.0.0

*Historical release notes from before the Kinegra Amp rebrand.*

ShieldAmp's first 1.0 release brings the existing music-free player into a versioned release: Music Assistant playback in the app, user imports, queues, fullscreen artwork and visuals, optional Cam-powered webcam avatars and experimental gestures.

- Android package: `org.local.tegramilkdrop`; version name `1.0.0`; code `76`.
- Existing original signing identity retained for in-place updates.
- No bundled soundtrack recordings, private covers, credentials or signing keys.
- MIT for original code, documentation and original artwork/media; complete third-party notices and component inventory accompany the APK.
- The hero remains an honestly labelled synthetic 0.8.41 demonstration.
- Visuals-off artwork is centered around the controls, with a larger centered fullscreen card. Each layout shows one playback cover, using a small dock thumbnail only when no larger cover is present.

This release keeps the playback/visual/gesture algorithms from 0.8.47 and adds an optional authenticated LAN web remote for basic transport/status. Production defaults off; development defaults on, with separate saved preferences. [Web remote](WEB-REMOTE.md). Optional gestures remain experimental. Device/display coverage, queue/seek limits and outstanding endurance checks remain documented in [validation](VALIDATION.md) and [development](DEVELOPMENT.md).

Install a signed release with an Android TV sideloading tool or build and sign your own APK. Updates to an existing installation must retain its signing key and app data. See [build and signing instructions](BUILDING.md).
