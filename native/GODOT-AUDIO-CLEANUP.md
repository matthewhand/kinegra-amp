# Godot Android audio cleanup

Use the official Godot 3.6.3-stable source archive; verify the SHA-256 in
`godot-opensl-runtime.json`. Apply `patches/godot-3.6.3-opensl-shutdown.patch`
from the source root with `patch -p1`. This also selects the reviewed NDK r26d.
Point `ANDROID_SDK_ROOT` at an SDK containing `ndk/26.3.11579264`, then run
SCons 4.8.1 with the flags in the manifest. The build produces
`platform/android/java/lib/libs/release/arm64-v8a/libgodot_android.so`.

Replace only `jni/arm64-v8a/libgodot_android.so` in the original release AAR;
retain its Java classes and other entries. The public builder verifies the
engine hash. Preserve the upstream MIT license and notices.

Stop and destroy the player and recorder before the output mix and engine.
On the tested Shield, engine destruction with active children was refused,
leaving callbacks alive beyond the driver mutex lifetime. The change does not
alter Sendspin security or the audio transport.
