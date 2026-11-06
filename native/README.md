# Native audio

`tegra_codec.c` with minimp3/stb_vorbis decodes bounded MP3/Ogg chunks into PCM. `godot_codec.c` exposes the codec to Godot 3 GDNative. The codec itself has no file or network I/O.

`godot_sendspin.cpp` adapts the pinned Sendspin C++ SDK to the in-app player. Source builds keep the reviewed ordered sink-clear, flushed accounting, outbound-only and Noise object-bounds patches. SDK logging stays disabled; the timestamp observer retains bounded numeric state rather than control payloads or pairing material.

The [public Android builder](../packaging/build_public.py) compiles these sources and the SDK with the explicit dependency/toolchain configuration in [the build guide](../docs/BUILDING.md). It compiles the project libraries from source. Build-only source filename normalization prevents workstation paths entering native payloads. Original dependency checkouts remain clean.

[Startup buffering](STARTUP-BUFFERING.md), [Noise bounds](NOISE-PATTERN-BOUNDS.md) and [Godot audio cleanup](GODOT-AUDIO-CLEANUP.md) document the relevant mechanisms. Platform-specific runtime proofs bind exact binaries and are distinct from compilation or host tests. Broader hardware coverage remains limited; see [testing](../docs/VALIDATION.md).

Full engine, toolchain, native-component, font and actual Gradle runtime notices ship in the app and source. [Third-party notices](../docs/THIRD-PARTY-NOTICES.md).
