# Kinegra Amp 1.0.10 public beta

Kinegra Amp plays Music Assistant streams and local files in its own Android TV window, with queues, artwork, optional visuals and webcam avatars. Formerly Kinegra ShieldAmp, this release updates the product name, banner, splash, app labels, web remote and CLI. The Android package and original signing identity remain compatible with existing installations. [Upgrade details](UPGRADING.md).

Production starts with the optional LAN remote off and its access key required. Startup never autoplays. No music, private cover artwork or inference model is bundled. Webcam tracking needs a separately configured Kinegra Cam pose feed; gestures remain experimental.

## Validation and limits

The signed 1.0.10 / code 86 APK was installed in place and its original certificate, APK hash and retained installation identity were verified. Matthew confirms hands-on testing of every version through this release. The clean offline Android build and focused host, browser, CLI, source, package and signing checks passed. These checks do not establish universal camera, controller, display or server compatibility. Development uses an original NVIDIA SHIELD on Android 11, an ultrawide display and one Razer webcam. Wider hardware and long-session coverage remains limited; tracking and layout can have beta rough edges. [Validation](VALIDATION.md).

The final source includes documentation, provenance and a test-only RFC 5737 example-address correction after the reviewed APK build. Application/runtime inputs are unchanged; the already reviewed signed APK is retained without rebuilding. The release metadata records the exact final source and artifact hashes.

## Experimental offline queue copying

A Music Assistant metadata-read failure can stop a bulk-copy batch. Completed copies remain playable; automatic retry and durable resume are not implemented. Bulk queue copying remains experimental. [Known limitation](https://github.com/matthewhand/kinegra-amp/issues/1) · [Offline copying](OFFLINE-COPYING.md).

## Distribution

The release includes the music-free signed APK, exact clean source archive, licence bundle, component inventory, metadata and SHA-256 checksums. Original code, documentation, artwork and hero media use MIT; dependencies retain their own terms. The hero is a staged desktop preview with fictional metadata, generated audio/artwork and procedural dancers, not a Shield streaming or performance benchmark.
