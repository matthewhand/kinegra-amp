# Demonstration media

The [silent demo](readme/kinegra-amp-hero.gif) was rendered in Godot on Linux from 1.0.10-era source and published in [commit `5e45a0d`](https://github.com/matthewhand/kinegra-amp/commit/5e45a0d2dca16d716f67b37ba7ebcb82d405403e). The README still is frame 8 of that animation. For Android-device and streaming coverage, see [Testing and compatibility](VALIDATION.md).

The animation starts on the local player with playback controls and procedural dancers. It opens the three-track queue, switches to fullscreen artwork with remote shortcuts, then shows artwork without the animated scene.

The preview fixture generates its own tones and geometric cover art and uses fictional track labels. Dancer animation is procedural; no camera, account, household, Music Assistant server or private music library is accessed. The fixture uses isolated user data and a Dummy audio driver. Its temporary samples are not part of the Android release.

Original hero media and artwork use the project MIT licence. [Kinegra Amp branding artwork](branding/kinegra-amp-banner.png) · [Artwork provenance](branding/README.md)

## Reproduce the animation

With the documented Linux host dependencies, run:

```sh
python3 tools/capture_hero.py --godot /opt/godot/Godot_v3.6.3-stable_x11.64 --output build/hero-capture
```

The command creates a new isolated fixture and user-data directory, captures 96 frames at six frames per second, and adds a visible synthetic-preview caption. It does not overwrite the README asset automatically.
