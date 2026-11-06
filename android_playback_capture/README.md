# Android playback capture feasibility prototype

This isolated Godot Android plugin prototype is not wired into Kinegra Amp, its APK, UI or export pipeline. It never prompts for permission or accesses a device when built or tested. The capture component performs no network, file output, audio playback, raw PCM export or logging. Host-side tests use synthetic samples only.

After a future host app explicitly obtains RECORD_AUDIO permission and a MediaProjection consent token, `PlaybackCaptureSession` can request Android 10+ playback capture of permitted media, game and unknown usages, excluding the caller's UID. It reports a transient RMS level and state. Closing or revocation stops capture; stale levels expire after 500 ms. It is a single amplitude envelope, not a spectrum/FFT and not proof of an audio-reactive visualization. A silent or empty capture cannot distinguish silence from a protected or unsupported source.

Build and test on Ubuntu-Max with `sh build_offline.sh`. It verifies the pinned Godot 3.6.3 engine AAR, compiles against Android 34, runs synthetic host JVM calculations, and stages a plugin AAR in `~/.cache/shieldamp-playback-capture-build`. It does not exercise Android APIs at runtime. The adjacent `.gdap` describes the plugin, but neither file is installed or enabled in the application.

The singleton exposes `startCapture()`, `stopCapture()`, `captureStatus()` and `captureLevel()`. Only an explicit start requests RECORD_AUDIO and then MediaProjection consent. If granted, a private foreground service exposes a persistent notification with a Stop action and never restarts itself. Denial, cancellation, errors and revocation stop capture. The level reports a stale-safe RMS value, with no PCM access. The separately tested `app/scripts/PlaybackCaptureClient.gd` is an optional adapter; the current UI never calls it. Service, consent and revocation handling are compiled prototypes and still require Android instrumentation and physical acceptance before use.

Before integration, verify the consent flow and denial/revocation behavior, permission, activity and service lifecycle, foreground-service requirements for the actual target SDK, Godot plugin registration, source labelling, performance, and secure isolation on Android. The current Godot prebuilt-template export does not contain an Android plugin build. Physical Shield validation requires explicit coordination and must check that playback continues and capture stops correctly. Verify Cast and specific third-party apps separately; their policies may prevent capture. Do not claim that all system audio, Cast or protected content is capturable.

Runtime/security acceptance still required:

- Verify the final merged manifest has exactly the intended permissions and a non-exported projection service; install only a separately identified, signed test build preserving application data.
- Test no automatic prompts, explicit start, microphone-permission denial, projection denial, cancellation while a dialog is open, repeated requests, process/activity recreation, and each corresponding status in the real Godot singleton.
- Test foreground notification and Stop action on Android 11 and the eventual release target, including notification-permission behavior, service start restrictions and Android 14+ single-use consent rules.
- Test projection revocation, app/service stop and process death; verify the audio recorder, notification and captured levels stop, no restart occurs, and no raw audio, token or consent data is persisted, logged or transmitted.
- With separate, specific user authorization, compare synthetic test audio, silent input and a permitted Cast stream, then protected/denied sources where appropriate; absence of captured sound must never be labelled proof of silence or policy denial. Check capture performance and whether the visualizer can coexist with playback on the Shield.

## Read-only Cast receiver check

On the project's Android 11 Shield, Android reported the active Cast receiver package `com.google.android.apps.mediashell` as version `3.72.446070`, target SDK 34, with the package flag `ALLOW_AUDIO_PLAYBACK_CAPTURE`. This is encouraging package-level evidence, not a successful capture: individual player attributes and policies, usage category, protected content, consent, and runtime behavior may still prevent it. No Cast audio was captured, no consent was requested, and no device settings were changed. Android's reported package flag does not expose the receiver's per-player capture policy.

References: [Android playback capture requirements](https://developer.android.com/media/platform/av-capture), [MediaProjection and consent](https://developer.android.com/media/grow/media-projection), [foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types), [Godot 3.6 Android plugin build](https://docs.godotengine.org/en/3.6/tutorials/platform/android/android_plugin.html).
