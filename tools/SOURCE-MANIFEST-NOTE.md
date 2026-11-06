# Source manifest

`SOURCE-MANIFEST.json` records every tracked source file by mode and SHA-256, excluding itself. `python3 tools/check_source.py` verifies it together with source/resource boundaries and pinned dependency notices.

The manifest describes the current source tree. Released APKs and their source archives remain tied to their release tag; later source cleanup does not replace a published artifact. Generated fixtures, build output, personal media and signing material are excluded.
