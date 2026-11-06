# Source checks and host tools

- `check_source.py` checks the complete source manifest, file modes, syntax, resources and dependency licences.
- `build_preview.py` builds an isolated Linux preview and runs selected GDScript tests.
- `make_fixtures.py` generates synthetic music/artwork in a disposable copy.
- `capture_hero.py` creates the labelled README demo from fictional content.
- `test_*.py` contains Python unit tests for the tools and CLI.
- `check_web_*.py` runs Godot/browser integration checks with explicit `--godot` and `--project` inputs.

Run `python3 tools/check_source.py` from the repository root. See [building](../docs/BUILDING.md) for host dependencies and test commands. Fixtures keep generated audio, credentials, state and logs outside the source checkout.
