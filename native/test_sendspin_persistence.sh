#!/usr/bin/env bash
# Offline synthetic identities only. No Music Assistant or device access.
# Usage: test_sendspin_persistence.sh <patched-sdk-source> <host-sdk-build>
set -euo pipefail
[ "$#" = 2 ] || { echo "usage: $0 <patched-sdk-source> <host-sdk-build>" >&2; exit 2; }
source_dir="$(realpath "$1")"; build_dir="$(realpath "$2")"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
flags=(-std=c++20 -Wall -Wextra -Werror -pthread -I"$root/native" -I"$source_dir/include")
for role in PLAYER CONTROLLER METADATA ARTWORK COLOR VISUALIZER SOURCE; do flags+=("-DSENDSPIN_ENABLE_$role"); done
libs=("$build_dir/libsendspin.a" "$build_dir/libnoise_c.a" "$build_dir/_deps/ixwebsocket-build/libixwebsocket.a" "$build_dir/_deps/micro_flac-build/libmicro_flac.a" "$build_dir/_deps/micro_flac-build/micro-ogg-demuxer/libmicro_ogg_demuxer.a")
for lib in "${libs[@]}"; do [ -f "$lib" ]; done
g++ "${flags[@]}" -fsanitize=address,undefined -fno-omit-frame-pointer -O1 -g "$root/native/tests/test_sendspin_secure_persistence.cpp" -o "$work/fault-test"
g++ "${flags[@]}" -fsanitize=address,undefined -fno-omit-frame-pointer -O1 -g "$root/native/tests/test_sendspin_vault_codec.cpp" -o "$work/codec-test"
"$work/codec-test"
"$work/fault-test"
g++ "${flags[@]}" "$root/native/tests/test_sendspin_sdk_persistence.cpp" -Wl,--start-group "${libs[@]}" -Wl,--end-group -lz -o "$work/sdk-test"
"$work/sdk-test"
if [ -n "${ANDROID_NDK_ROOT:-}" ]; then
 compiler="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++"
 "$compiler" "${flags[@]}" -c "$root/native/tests/test_sendspin_secure_persistence.cpp" -o "$work/arm64.o"
 file "$work/arm64.o" | grep -q "ARM aarch64"
 echo "ANDROID_ARM64_PERSISTENCE_OBJECT_PASS"
fi
