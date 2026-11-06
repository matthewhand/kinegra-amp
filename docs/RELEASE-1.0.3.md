# ShieldAmp 1.0.3

*Historical release notes from before the Kinegra Amp rebrand.*

Music Assistant catalog requests use unique per-request identifiers across clients. The web catalog has a 12-second read timeout and at most one retry for a failed read; playback and queue mutations retain the existing timeout and are never automatically retried. Numeric result/HTTP categories are logged without credentials, server addresses or library names.

Includes the web connection feedback, searchable Tracks/Albums/Playlists, Play/Add to Queue/Queue Page and upcoming-queue view. Tracks is the first category, queue reads wait for the verified own-output connection, and empty queues are handled without invalid offsets. Original signing identity and app data are retained; Android code 79. Production web remote defaults off, development on. [Remote usage/API](WEB-REMOTE.md).
