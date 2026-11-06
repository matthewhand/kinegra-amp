#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p native/build
# Isolated host proof; no writes to Android SDK or existing application.
cc -std=c11 -O2 -fPIC -Wall -Wextra -Wno-unused-function -Werror -shared -o native/build/libtegra_codec_host.so native/tegra_codec.c native/minimp3_impl.c native/stb_vorbis_impl.c -lm
NDK="${ANDROID_NDK_ROOT:?Set ANDROID_NDK_ROOT}"
test -f "$NDK/source.properties"
test -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android23-clang"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android23-clang" -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -std=c11 -O2 -fPIC -Wall -Wextra -Wno-unused-function -Werror -shared -o native/build/libtegra_codec_arm64.so native/tegra_codec.c native/minimp3_impl.c native/stb_vorbis_impl.c -lm
echo "ARM64 HEADER"
readelf -h native/build/libtegra_codec_arm64.so | grep -E "Class:|Machine:|Type:"
sha256sum native/build/libtegra_codec_{host,arm64}.so
