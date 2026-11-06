# ShieldAmp 1.0.9

*Historical release notes from before the Kinegra Amp rebrand.*

Android offline copying now reads available bytes from the app-private filesystem through the platform plugin; Godot’s desktop-only free-space result is not treated as a full disk. The 256 MiB reserve and atomic/hash-verified imports remain enforced. Play Saved So Far starts completed tracks while the rest of the captured queue continues copying. Later copies remain in Offline Library; Play Saved Queue explicitly loads the latest saved order. No Music Assistant playback queue is changed by copying.

The patch retains the1,024-entry bound, paged local queue and bounded streaming recovery. Native audio libraries and third-party dependencies are unchanged. Device copying and silent playback proof are recorded separately from listening acceptance.
