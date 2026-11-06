#!/usr/bin/env bash
# Build isolated experimental Godot adapter; never installs or changes an app.
# Usage: build_sendspin_adapter.sh <host|android> <pinned-sdk-checkout> <patched-sdk-source> <sdk-build> <new-output.so>
set -euo pipefail
[ "$#" -eq 5 ] || { echo "invalid arguments" >&2; exit 2; }
mode="$1"; sdk="$(realpath "$2")"; source_dir="$(realpath "$3")"; build_dir="$(realpath "$4")"; out="$5"
[ "$(git -C "$sdk" rev-parse HEAD)" = 985fba57afb0462b520ab9ce974d1860858ed685 ]
[ -z "$(git -C "$sdk" status --porcelain)" ]
[ ! -e "$out" ] || { echo "refusing to overwrite output" >&2; exit 1; }
# Only accept the exact pinned SDK plus our reviewed ordered-clear patch.
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
git -C "$sdk" archive HEAD | tar -xf - -C "$work"
git -C "$work" apply "$(realpath "$(dirname "$0")/sendspin-ordered-clear.patch")"
git -C "$work" apply "$(realpath "$(dirname "$0")/sendspin-outbound-only.patch")"
git -C "$work" apply "$(realpath "$(dirname "$0")/sendspin-source-path.patch")"
diff -qr "$work" "$source_dir" >/dev/null || { echo "patched source differs from pin" >&2; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd)"
case "$mode" in
 host) compiler=g++; extra=(-lpthread) ;;
 android) compiler="${ANDROID_NDK_ROOT:?set ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++"; extra=(-static-libstdc++ -llog -landroid -Wl,-z,max-page-size=16384) ;;
 *) echo "unsupported platform" >&2; exit 2 ;;
esac
flags=(-std=c++20 -fPIC -Wall -Wextra -Werror -I"$root/native" -I"$root/native/vendor/godot-headers" -I"$source_dir/include")
if [ "${KINEGRA_PORTABLE_BUILD:-0}" = 1 ]; then
    flags+=("-ffile-prefix-map=$root=/src/shieldamp" "-ffile-prefix-map=$source_dir=/src/sendspin" "-ffile-prefix-map=$build_dir=/build/sendspin" "-ffile-prefix-map=${ANDROID_NDK_ROOT:?}=/toolchain/android-ndk")
fi
grep -Eq '^SENDSPIN_ENABLE_MESSAGE_TRACE(:BOOL|:UNINITIALIZED)=ON$' "$build_dir/CMakeCache.txt" || { echo "SDK timestamp observer feature must be enabled" >&2; exit 1; }
noise_checkout=$(sed -n 's/^KINEGRA_NOISE_PINNED_CHECKOUT:PATH=//p' "$build_dir/CMakeCache.txt" | head -n1)
noise_source=$(sed -n 's/^FETCHCONTENT_SOURCE_DIR_NOISE_C:\(PATH\|STRING\|UNINITIALIZED\)=//p' "$build_dir/CMakeCache.txt" | head -n1)
[ -n "$noise_checkout" ] && [ -n "$noise_source" ] || { echo "Pinned bounds-fixed Noise-C configuration is required" >&2; exit 1; }
python3 "$(dirname "$0")/prepare_noise_source.py" --verify "$noise_checkout" "$noise_source"
arduino_json=$(sed -n 's/^FETCHCONTENT_SOURCE_DIR_ARDUINOJSON:PATH=//p' "$build_dir/CMakeCache.txt" | head -n1)
[ -n "$arduino_json" ] && [ -f "$arduino_json/src/ArduinoJson.h" ] || { echo "Explicit ArduinoJson source is required" >&2; exit 1; }
flags+=("-DSENDSPIN_ENABLE_MESSAGE_TRACE" "-I$arduino_json/src")
for role in PLAYER CONTROLLER METADATA ARTWORK COLOR VISUALIZER SOURCE; do flags+=("-DSENDSPIN_ENABLE_$role"); done
"$compiler" "${flags[@]}" -c "$root/native/godot_sendspin.cpp" -o "$work/adapter.o"
libs=("$build_dir/libsendspin.a" "$build_dir/libnoise_c.a" "$build_dir/_deps/ixwebsocket-build/libixwebsocket.a" "$build_dir/_deps/micro_flac-build/libmicro_flac.a" "$build_dir/_deps/micro_flac-build/micro-ogg-demuxer/libmicro_ogg_demuxer.a")
for lib in "${libs[@]}"; do [ -f "$lib" ]; done
"$compiler" -shared -Wl,--no-undefined -o "$out" "$work/adapter.o" -Wl,--start-group "${libs[@]}" -Wl,--end-group -lz "${extra[@]}"
file "$out"
