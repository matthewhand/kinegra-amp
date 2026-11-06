# Demonstration media

The README animation is a silent staged desktop capture of Kinegra Amp 1.0.10, rendered from this source with Godot on Linux. It shows local playback, the current branding, queue controls, visualisers and fullscreen artwork. It is not an Android-device capture or a streaming, camera or performance benchmark.

The preview fixture generates its own tones and geometric cover art and uses fictional track labels. Dancer animation is procedural; no camera, account, household, Music Assistant server or private music library is accessed. The fixture uses isolated user data and a Dummy audio driver. Its temporary samples are not part of the Android release.

Original hero media and artwork use the project MIT licence. [Artwork provenance](branding/README.md).

## Reproduce the animation

With the documented Linux host dependencies, run:

```sh
python3 tools/capture_hero.py --godot /opt/godot/Godot_v3.6.3-stable_x11.64 --output build/hero-capture
```

The command creates a new isolated fixture and user-data directory, captures 96 frames at six frames per second, and adds a visible synthetic-preview caption. It does not overwrite the README asset automatically.
