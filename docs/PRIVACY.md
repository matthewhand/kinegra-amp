# Privacy and local data

Kinegra Amp connects to the Music Assistant server you configure and plays its verified app-owned Sendspin output. Optional advanced Home Assistant controls use a separately configured server. Private HTTP sends credentials without transport encryption and requires a deliberate trust choice; use a trusted network and encrypted endpoints where supported.

Library credentials stay in memory unless Remember access is selected and authentication succeeds. Saved credentials and pairing identity use Android Keystore-backed app-private storage. Forget saved access removes local library credentials; revoke the access token in Music Assistant to revoke server access. Server queues and pairing are separate from library browsing credentials. [Credential lifecycle](SECURE-TOKEN-LIFECYCLE.md).

The music-free distribution has no bundled songs or private covers. Streaming buffers are temporary playback data, not downloaded full-song files. Import copies selected MP3/Ogg files into app storage. Delete Copy removes that copy after confirmation and leaves USB/source files unchanged. Legacy slots remain reserved so existing user imports and queue indices are stable across updates; unavailable old songs are skipped when explicitly playing a queue.

Webcam features are optional and start disabled. Kinegra Amp reads USB presence metadata and consumes Kinegra Cam's local pose status while enabled. It does not capture or retain camera images through that feed. Turning Webcam off cancels pose work; explicitly enabled gestures may retain limited tracking when only decorative visuals are off. Kinegra Cam controls its own camera, inference and network choices.

The UI can show private track names, server addresses and pairing information during normal use. Review diagnostics and screenshots before sharing them. Source demos use generated media and synthetic landmarks. Production release settings disable Android debugging and backup; these settings do not protect data from an administrator controlling the device.


## Optional web remote

Production builds open no remote-control port by default. Development/debug builds enable the remote by default; each build type has a separate remembered toggle. Settings shows the service address and a freshly generated access key. Disabling it closes the listener and all connections immediately. It runs only with the app and does not install a background service, enable router forwarding or advertise itself.

The IPv4 LAN HTTP service on port 8765 requires the access key for playback metadata and commands. The public landing page contains no track information. Once authenticated, the remote can browse bounded Music Assistant library metadata, read the upcoming queue and request music on this app’s verified output. Its library snapshots and at most 16 jobs remain in memory; turning the remote off drops them. The key remains in memory, rotates on restart/re-enable or New remote access key, and is never a Music Assistant credential. The page holds it only in memory. HTTP does not encrypt the key or track metadata: enable this only on a trusted LAN. No camera images, music bytes, server URLs, library tokens or system-volume controls are exposed. Source/Origin and numeric local Host checks reject cross-site requests; request sizes, connection lifetimes and work per frame are bounded.
