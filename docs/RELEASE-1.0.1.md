# ShieldAmp 1.0.1

*Historical release notes from before the Kinegra Amp rebrand.*

The web remote now gives explicit connection progress, wrong-key and network errors. An embedded browser reporting a hidden document no longer suppresses an explicit Connect attempt.

Music Assistant browsing includes searchable Tracks/Albums/Playlists, collection paging, Play, Add to Queue, Queue Page and a view of up to ten upcoming items. Queue additions use the app's verified output and do not issue Play. Stale page handles, changed playback routes, competing writes and duplicated/ambiguous requests have explicit guards.

Android package and original signing identity are retained; version code is 77. Production still defaults to web remote off, development to on, with separate remembered preferences. Existing original artwork, music-free packaging and MIT/upstream licensing are unchanged. See [remote usage/API](WEB-REMOTE.md) and [validation](VALIDATION.md).
