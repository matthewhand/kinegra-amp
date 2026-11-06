# Developing Kinegra Amp

Kinegra Amp uses Godot 3.6.3/GLES2, GDScript, native audio adapters and an Android plugin. Start with [building](BUILDING.md), [validation](VALIDATION.md) and [privacy](PRIVACY.md).

| Path | Purpose |
| --- | --- |
| `app/` | Player, library/queue UI, shaders, avatars and GDScript tests |
| `native/` | MP3/Ogg codec, Sendspin adapter, dependency patches and native tests |
| `android_secure_storage/` | Android Keystore credentials, pairing identity, USB detection and file imports |
| `clients/` | Python web-remote CLI and optional offline file-source helper |
| `packaging/` | Android build, preview isolation and package checks |
| `tools/` | Source integrity, dependency pins and synthetic host fixtures |
| `third_party/` | Dependency notices, provenance and Gradle runtime lock |

## Playback and visuals

Music Assistant streaming uses the native Sendspin adapter and the in-app output. Local MP3/Ogg files use the native decoder. Neither needs a separate Python codec bridge. The server owns its streaming queue and playback position. Collection snapshots are bounded to 2,000 tracks and 2 MiB; queue reordering and paused/radio seeking are not implemented.

Visuals use frame timing, buffer health, current-process CPU time and Android thermal state. Optional webcam avatars consume Kinegra Cam landmarks. Tracking and gestures remain experimental; see [webcam setup](WEBCAM-GESTURES.md).

The opt-in [web remote](WEB-REMOTE.md) provides playback, library and queue controls. The [CLI](CLI.md) uses the same API. Development and production builds keep separate remote preferences; production starts with the service disabled.

## Tests

Use generated audio, synthetic landmarks and isolated state. The [host builder](BUILDING.md#host-checks) compiles its codec and imports fixtures before selected GDScript tests. Native stream and bounds tests use pinned dependency sources and local synthetic services. Credential/plugin tests use disposable credentials, never live accounts.

Run source checks with `python3 tools/check_source.py`. Run Python unit tests with `python3 -m unittest discover -s tools` and `python3 -m unittest discover -s packaging`. Browser integration scripts use `tools/check_web_*.py --godot PATH --project HOST_PREVIEW_APP`. Python tests live beside their tools and under `packaging/`; GDScript tests are in `app/tests/`, native tests in `native/tests/`, and Android plugin tests in `android_secure_storage/tests/`. The Android security harnesses are regression tools for the active plugin, not app features.

When changing dependencies, update the pinned revisions, patch hashes, native alignment, licence texts and Gradle artifact/POM lock. Regenerate `tools/SOURCE-MANIFEST.json` for intentional source changes. Automated checks complement physical playback/controller/webcam testing; see [test scope](VALIDATION.md).

## Contributing

Include the version, device, input method and reproduction steps. Add a focused regression for behavioral fixes. Keep credentials, personal media and generated signing keys out of commits. Original code and artwork use MIT; retain upstream notices with dependencies.
