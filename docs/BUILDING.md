# Build Kinegra Amp

The public build produces the music-free `org.local.tegramilkdrop` ARM64 app. It uses the normal Music Assistant and user-import playback paths, starts with an empty local library, and preserves the legacy index range used by existing imported tracks and queues. It does not require the original soundtrack, private Git history or production signer.

## Inputs

Prepare these public inputs on Linux before an offline build:

- Godot **3.6.3** Linux editor, official Android release/debug AARs, export templates and matching Android custom-build source.
- JDK **17**, Android platform **36** / build tools **36.1.0**, Android NDK **26.3.11579264 (r26d)**, Gradle **8.11.1**, CMake, Git, a C/C++ compiler, Python 3.12 with Pillow, FFmpeg, Xvfb and **SCons 4.8.1**.
- Clean checkouts of the exact revisions in [the dependency lock](../review/dependencies.lock.json): Sendspin, ArduinoJson, IXWebSocket, micro-flac with its micro-ogg-demuxer submodule, and Noise-C.
- A Gradle cache populated for the matching Android template. The build resolves its runtime artifacts offline and compares all 33 module artifacts/POMs and license metadata with [the runtime lock](../third_party/gradle-runtime.lock.json).

The build validates explicit paths rather than using another developer's home directory. It does not download missing toolchains or dependencies. Prepare caches from their upstream distributions before building. The original AAR hashes, dependency revisions, source archive and patch hashes are checked by the tools.

## Build the Android audio runtime

Use the official Godot 3.6.3-stable source archive matching `archive_sha256` in [the runtime manifest](../native/godot-opensl-runtime.json). The helper applies the included OpenSL shutdown/16 KiB patch and builds its ARM64 release library:

```sh
python3 packaging/build_audio_engine.py \
  --archive /opt/source/godot-3.6.3-stable.tar.gz \
  --ndk /opt/android-ndk-r26d \
  --sdk /opt/android-sdk \
  --scons /opt/scons/bin/scons \
  --output build/audio-engine --jobs 4
```

The recorded source build reproduces library SHA-256 `6a80758e52d6c0c74f2f7677724aec4c87a8e9224e9872978071b15930d6f2a6`. The builder replaces only that entry in a staged release AAR. Its original 16 KiB-aligned C++ runtime remains unchanged, with the matching NDK r28 notices retained. [Audio cleanup details](../native/GODOT-AUDIO-CLEANUP.md).

## Build an unsigned APK

Copy [the example configuration](../packaging/public-build.example.json) to a local file outside the checkout and set your input paths, including the source-built `godot_engine_library`. Use a fresh output directory:

```sh
python3 packaging/build_public.py \
  --config /opt/build-inputs/shieldamp.json \
  --output build/android-release
```

This compiles the codec, patched Sendspin SDK/adapter and Android secure-storage/import plugin from source, imports the cleared artwork and exports version 1.0.10/code 86. Native source paths are remapped, including compiler-generated lambda metadata; the final owned native payloads are checked before acceptance. [Portable source names](../native/SOURCE-PATHS.md). CMake is disconnected and Gradle runs offline. A build-only ADB stub prevents Godot's editor polling from accessing a device.

Godot requires a debug-keystore setting even when exporting unsigned. The helper generates a disposable configuration-only key under the output directory; `package/signed=false` and a final signature check enforce unsigned output. No production signing settings or keys are read. The final APK, exact native hashes, runtime notices, source revision and build metadata remain under the output directory. Keep the generated validation key and build logs out of source commits.

The public builder adds the `shieldamp_production` feature tag so the optional web remote defaults off, even if tested with a debug template. Editor/debug development without that tag defaults on. Both remember separate user choices.

The APK uses the existing package ID, non-debuggable release settings, disabled backup, single-task launch and 16 KiB native/package alignment. Signing is separate. Preserve the original certificate when updating an existing installation; do not uninstall or clear data to force an update. This builder does not sign, install or launch the app.

## Host checks

```sh
python3 review/check_source.py
python3 review/build_preview.py --godot /opt/godot/Godot_v3.6.3-stable_x11.64 \
  --output build/host-preview --test tests/test_offline_tv_accessibility.gd
```

The host helper creates disposable generated tones/covers and isolated state, uses the Dummy audio driver, and leaves the source unchanged. Generated sample paths exist only in that fixture; the production runtime contains no bundled song or cover paths. See [validation](VALIDATION.md) for music-free migration, playback and license-reader checks. Independently signed APKs and arbitrary compiler environments are not claimed byte-identical.
