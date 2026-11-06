#!/usr/bin/env bash
# Synthetic host bounds/protocol-equivalence regression; no network or device.
set -euo pipefail
[ "$#" -eq 4 ] || { echo "usage: $0 <clean-noise-checkout> <patched-noise-source> <fixed-libnoise.a> <fresh-output-dir>" >&2; exit 2; }
checkout="$(realpath "$1")"; source_dir="$(realpath "$2")"; archive="$(realpath "$3")"; output="$(realpath -m "$4")"
root="$(cd "$(dirname "$0")" && pwd)"
[ ! -e "$output" ] || { echo "use a fresh output directory" >&2; exit 1; }
python3 "$root/prepare_noise_source.py" --verify "$checkout" "$source_dir"
mkdir -p "$output"
flags=(-std=c99 -O3 -D_FORTIFY_SOURCE=2 -I"$source_dir/include" -I"$source_dir/src")
rename=()
for name in lookup reverse_flags expand expand_fallback expand_hfs expand_psk; do rename+=("-Dnoise_pattern_$name=baseline_noise_pattern_$name"); done
cc "${flags[@]}" "${rename[@]}" -c "$checkout/src/protocol/patterns.c" -o "$output/baseline.o"
cc "${flags[@]}" -DNOISE_COMPARE_BASELINE "$root/tests/test_noise_pattern_bounds.c" "$output/baseline.o" "$archive" -o "$output/equivalence"
"$output/equivalence"
for variant in original fixed; do
    pattern="$checkout/src/protocol/patterns.c"
    [ "$variant" != fixed ] || pattern="$source_dir/src/protocol/patterns.c"
    cc "${flags[@]}" -DNOISE_PATTERN_SOURCE="\"$pattern\"" -c "$root/tests/noise_pattern_checked.c" -o "$output/$variant.o"
    cc "${flags[@]}" "$root/tests/test_noise_pattern_bounds.c" "$output/$variant.o" "$archive" -o "$output/$variant-checked"
done
# The original must reproduce the precise object-bound violation, not an unrelated failure.
set +e
(ulimit -c 0; "$output/original-checked") >"$output/original.log" 2>&1
result=$?
set -e
[ "$result" -ne 0 ] && grep -q '^NOISE_SCAN_OVERRUN requested=62 available=' "$output/original.log"
"$output/fixed-checked"
cc "${flags[@]}" -g -fsanitize=address,undefined -fno-omit-frame-pointer -c "$source_dir/src/protocol/patterns.c" -o "$output/asan-patterns.o"
cc "${flags[@]}" -g -fsanitize=address,undefined -fno-omit-frame-pointer "$root/tests/test_noise_pattern_bounds.c" "$output/asan-patterns.o" "$archive" -o "$output/sanitized"
ASAN_OPTIONS=detect_leaks=1 "$output/sanitized"
echo NOISE_PATTERN_BOUNDS_HOST_PASS
