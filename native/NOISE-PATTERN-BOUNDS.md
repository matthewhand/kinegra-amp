# Noise pattern object bounds

Kinegra Amp applies `noise-pattern-bounds.patch` to Noise-C revision
`a1e08809a1b8f65cd91765ba7d68a6d00648ad61` (upstream v0.1.13).
The upstream MIT header is retained, with a dated local modification notice.

The original pattern expansion requested a 62-byte `memchr` scan from a static
pattern with only 10 bytes remaining. An optimized Android build can propagate
the actual object size into `__memchr_chk`, which correctly aborts that request.
The patch carries the actual `sizeof` of each of the 15 static pattern arrays to
the scan. Pattern tokens, flags, modifier semantics, public APIs, cryptographic
algorithms, random generation, authentication and pairing persistence are unchanged.
Optimization and Android FORTIFY remain enabled. Unknown patterns still return an
error; they do not fall back to a weaker handshake.

`prepare_noise_source.py` exports a clean pinned checkout into a new scratch
directory and applies the patch without changing the original checkout. Its
`--verify` mode compares the complete export with the exact pin plus patch.
`build_sendspin_android.sh` requires an explicit pinned Noise-C checkout in
`FETCHCONTENT_SOURCE_DIR_NOISE_C`, prepares a separate patched export, and records
both paths in the CMake cache. `build_sendspin_adapter.sh` refuses an adapter build
unless that export passes the same exact-source check. The preview packaging
builder already supplies the pinned dependency checkout through this path.

Run the host regression with:

```sh
bash native/test_noise_pattern_bounds.sh CLEAN_NOISE_CHECKOUT PATCHED_NOISE_SOURCE FIXED_LIBNOISE_A FRESH_OUTPUT_DIRECTORY
```

It reproduces the original optimized object-bound error with a synthetic checked
scan, then verifies the patched scan. It also compares error codes and the meaningful
successful pattern bytes against the pinned original for all 15 patterns and 5,985
modifier sequences, checks output guards, tests 30 base-pattern constructors plus the two application KKpsk2 roles,
checks strict PSK-length acceptance,
and rejects invalid pattern IDs/names. The patched pattern code and test run under
ASan/UBSan. There is no network, recording, credential, private fixture or device
interaction in this regression.

The same `native/tests/test_noise_pattern_bounds.c` can link the production
optimized Android Noise-C archive for an actual ARM/FORTIFY smoke test. Host tests
alone do not validate Android's fortified libc or prove live pairing succeeds.
