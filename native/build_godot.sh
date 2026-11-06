#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p native/build app/native/bin
COMMON=(-std=c11 -O2 -fPIC -fvisibility=hidden -Wall -Wextra -Werror -Wno-unused-function -Inative -Inative/vendor/godot-headers -shared)
SOURCES=(native/godot_codec.c native/tegra_codec.c native/minimp3_impl.c native/stb_vorbis_impl.c)
cc "${COMMON[@]}" -o app/native/bin/libtegra_godot_x11.so "${SOURCES[@]}" -lm
NDK="${ANDROID_NDK_ROOT:?Set ANDROID_NDK_ROOT}"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android23-clang" "${COMMON[@]}" -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -o app/native/bin/libtegra_godot_arm64.so "${SOURCES[@]}" -lm
readelf -h app/native/bin/libtegra_godot_arm64.so | grep -E 'Class:|Machine:'
readelf -l app/native/bin/libtegra_godot_arm64.so | grep -A1 LOAD
sha256sum app/native/bin/libtegra_godot_*.so
