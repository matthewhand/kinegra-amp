# ShieldAmp 1.0.6

*Historical release notes from before the Kinegra Amp rebrand.*

The fullscreen now-playing card fades in over 1.6 seconds, uses a gentle 4.5-second opacity pulse and fades out over 2.4 seconds after its hold. Repeated identical metadata does not restart it. New tracks and user interaction reveal it again. Centered album art stays visible with visuals off; Reduced motion keeps metadata steady. Ordinary status and error text remain readable.

A Python CLI now supports status, diagnostics, transport, library search/paging and Play/Add/Queue Page using the same guarded LAN API. See [CLI usage](CLI.md). It does not save credentials, use ambient proxies, follow redirects or automatically retry mutations.

Focused host coverage passes 101 notice checks, 6 full-UI checks, 17 full-app web checks and 10 real-loopback CLI tests. The notice was visually inspected using fictional metadata and original artwork. Matthew has since confirmed testing every version through 1.0.10. Audio transport/native payloads and third-party dependencies are unchanged. The package remains music-free.
