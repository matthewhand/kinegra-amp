#!/usr/bin/env bash
# Compile the pinned upstream Sendspin SDK for Android arm64; research only.
# Usage: build_sendspin_android.sh <clean-sdk-checkout> <android-ndk> <build-dir>
# CMake downloads upstream dependencies on first configure. Never writes SDK sources.
set -euo pipefail
if [ "$#" -lt 3 ]; then echo "usage: $0 <sdk-checkout> <android-ndk> <build-dir> [CMake options...]" >&2; exit 2; fi
sdk="$(realpath "$1")"; ndk="$(realpath "$2")"; build="$(realpath -m "$3")"
extra_cmake_args=("${@:4}")
pin=985fba57afb0462b520ab9ce974d1860858ed685
[ "$(git -C "$sdk" rev-parse HEAD)" = "$pin" ] || { echo "SDK revision does not match pin" >&2; exit 1; }
[ -z "$(git -C "$sdk" status --porcelain)" ] || { echo "SDK checkout is not clean" >&2; exit 1; }
test -f "$ndk/build/cmake/android.toolchain.cmake"
case "$build/" in "$sdk/"*) echo "Build directory must be outside SDK source" >&2; exit 1;; esac
# Export the pinned revision without touching the SDK checkout. Refuse to
# overwrite an existing export or CMake cache; use a fresh build directory.
[ ! -e "$build/sdk-patched" ] && [ ! -e "$build/CMakeCache.txt" ] || { echo "Use a fresh build directory" >&2; exit 1; }
mkdir -p "$build/sdk-patched"
git -C "$sdk" archive HEAD | tar -xf - -C "$build/sdk-patched"
patch_file="$(realpath "$(dirname "$0")/sendspin-ordered-clear.patch")"
git -C "$build/sdk-patched" apply --check "$patch_file"
git -C "$build/sdk-patched" apply "$patch_file"
outbound_patch="$(realpath "$(dirname "$0")/sendspin-outbound-only.patch")"
git -C "$build/sdk-patched" apply --check "$outbound_patch"
git -C "$build/sdk-patched" apply "$outbound_patch"
source_path_patch="$(realpath "$(dirname "$0")/sendspin-source-path.patch")"
git -C "$build/sdk-patched" apply --check "$source_path_patch"
git -C "$build/sdk-patched" apply "$source_path_patch"
# Noise-C's static pattern scan needs its reviewed object-bounds fix, including
# optimized Android/FORTIFY builds. Export it separately; never edit dependency caches.
noise_checkout=""
filtered_cmake_args=()
for arg in "${extra_cmake_args[@]}"; do
    case "$arg" in
        -DFETCHCONTENT_SOURCE_DIR_NOISE_C=*) noise_checkout="${arg#*=}" ;;
        -DFETCHCONTENT_SOURCE_DIR_NOISE_C:PATH=*) noise_checkout="${arg#*=}" ;;
        *) filtered_cmake_args+=("$arg") ;;
    esac
done
[ -n "$noise_checkout" ] || { echo "Explicit pinned Noise-C checkout is required" >&2; exit 1; }
noise_checkout="$(realpath "$noise_checkout")"
python3 "$(dirname "$0")/prepare_noise_source.py" "$noise_checkout" "$build/noise-patched"
extra_cmake_args=("${filtered_cmake_args[@]}" "-DFETCHCONTENT_SOURCE_DIR_NOISE_C=$build/noise-patched" "-DKINEGRA_NOISE_PINNED_CHECKOUT:PATH=$noise_checkout")
cmake -S "$build/sdk-patched" -B "$build" -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 -DSENDSPIN_ENABLE_OPUS=OFF -DBUILD_TESTING=OFF -DSENDSPIN_ENABLE_MESSAGE_TRACE=ON "${extra_cmake_args[@]}"
cmake --build "$build" --target sendspin -j4
archive="$build/libsendspin.a"
test -s "$archive"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ar p "$archive" constants.cpp.o > "$tmp/constants.o"
file "$tmp/constants.o" | grep -q "ARM aarch64" || { echo "Unexpected object architecture" >&2; exit 1; }
printf "ANDROID_ARM64_SENDSPIN_STATIC_LIBRARY=%s\n" "$archive"
