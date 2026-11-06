# Source integrity and synthetic fixtures

`python3 review/check_source.py` verifies the complete selected source path/hash/mode manifest, credential/private-installation pattern checks, source syntax, literal resource closure and pinned dependency notices. The manifest describes this clean source distribution, not the original development history or device data.

The host preview helper creates generated tones/covers in a disposable copy, compiles the codec and waits for complete Godot imports. It uses isolated user/config/cache directories and the Dummy audio driver. `--music-free` retains the production empty song/cover arrays while generated files remain test inputs for user-import acceptance. The source is never rewritten. [Build and test instructions](../docs/BUILDING.md).

The Android builder uses public pinned inputs, the same intended app package and an empty music library. It produces an unsigned release; production signing, installation and physical acceptance are separate. No original soundtrack, private settings, canonical Git history or signing material is included.
