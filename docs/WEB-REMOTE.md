# Web remote and control API

Enable **Settings → Web remote (trusted LAN)**. On a phone or computer on the same trusted LAN, open the displayed address and enter its current 16-character key. Connect shows progress and an adjacent error if the key is rejected or the device is unreachable. A key changes when Kinegra Amp restarts; a key from an earlier session will not work. Explicit Connect works even if an embedded browser reports its document as hidden.

## Choose and queue music

After connecting, browse **Tracks**, **Albums** or **Playlists** and use Search. Open a collection to page/filter its returned tracks. **Play** explicitly starts selected music in Kinegra Amp; **Add to Queue** appends, and **Queue Page** adds available tracks on the displayed page. A collection's Add to Queue asks Music Assistant to expand that collection. **View Queue / Refresh Queue** shows up to ten upcoming items. Adding does not issue a Play command or select another player.

The library uses the Music Assistant connection already configured on the TV. Playback reconnects automatically to Kinegra Amp's own saved identity when needed; if initial pairing is required, approve it in Music Assistant. Catalog reads do not overwrite the TV's highlighted selection. Music Assistant owns the queue. Queue removal/reordering, offline-library control, settings parity are not exposed by this web version. The [Python CLI](CLI.md) uses the same API.

## Defaults and access

- Production/release: **off** on first run. The public builder's `shieldamp_production` tag wins over a debug template.
- Development/debug: **on** on first run. Each build type remembers a separate user choice.
- Turning the setting off closes the listener/connections and drops its in-memory jobs, library snapshots and access key. Unreadable settings fail closed.
- The random key stays in memory and rotates on restart/re-enable or **New remote access key**. The browser keeps it only in memory.
- IPv4 private/link-local/loopback HTTP on port **8765**. HTTP is unencrypted: use a trusted LAN. No discovery, router forwarding, external assets or analytics.
- **Require access key** is on by default. To opt out, enter trusted private IPv4 addresses, CIDR blocks or start-end ranges in Settings and choose **Apply Remote Access**. Separate up to eight ranges with commas. The initial ranges use the device’s private interfaces and loopback; review them for your network. All clients must match a trusted range, with or without a key. Disabling the key gives matching devices control. Applying access settings closes existing web sessions and rotates the key without stopping audio.
- Clients allowed by this policy can read playback/library/queue metadata or request actions. No Music Assistant credential, server URL, music bytes or camera feed is returned.

## API

When **Require access key** is enabled, send `Authorization: Bearer ACCESS_KEY` to every API endpoint and `Content-Type: application/json` for POST bodies. Use the device address shown in Settings. Credentials do not belong in query strings.

| Endpoint | Purpose / JSON body |
| --- | --- |
| `GET /api/access` | Whether a key is required; range-gated, no player metadata |
| `GET /api/diagnostics` | Playback connection, pending request and audio-buffer counters; no server address or credentials |
| `GET /api/status` | Current display title, source and playback state |
| `POST /api/control` | `{"action":"play"}`; also pause, previous, next, stop |
| `POST /api/library` | `{"kind":"albums","search":"","offset":0}`; tracks/albums/playlists, 25 rows |
| `POST /api/library/open` | `{"page_id":1,"item":0}` opens a collection from that page |
| `POST /api/library/page` | `{"page_id":2,"offset":25,"search":""}` pages/filters the open collection |
| `POST /api/library/play` | `{"page_id":2,"item":0,"request_id":"unique-action-001"}` |
| `POST /api/queue/add` | Same page/item/request_id fields; appends selected music |
| `POST /api/queue/add-page` | `{"page_id":2,"request_id":"unique-action-002"}` |
| `POST /api/queue/refresh` | `{}` reads up to ten upcoming items |
| `GET /api/operations/ID` | Polls the bounded library/queue job returned by a POST |

Library/queue POSTs return `202` with an operation ID. Poll for `state: done` or `state: error` and its message. Completed browse jobs contain a page with a `page_id` and row-local numeric `id` values; use those handles for subsequent actions. A changed page or connection invalidates older choices. The client cannot submit an arbitrary player, URI, endpoint or library credential.

Mutation request IDs are mandatory, unique 8–64-character letters/digits/underscore/hyphen values. The last 16 jobs deduplicate identical retried IDs. Never automatically resend an ambiguous mutation with a new ID: inspect Queue first. Jobs have a 35-second deadline; the page polls with a 42-second bound. Web catalog reads use a 12-second timeout and at most one read-only retry; other MA requests retain an eight-second timeout. Reply sizes remain bounded. Accepted requests are not proof of audible playback; asynchronous failures appear in the operation result. `401` means the current key is required; `409` means the page/connection is stale or another request is in progress.

The service verifies a fresh, complete route to this exact paired Sendspin client before a queue mutation. Competing TV mutations are blocked while a web queue write is in progress. Its snapshots and jobs are bounded; slow or malformed clients cannot hold the audio thread indefinitely. No CORS permissions are granted, and replies are not cached.


## Offline copies

The Queue panel also offers Save Queue Offline, Pause/Resume Saving, Discard Pending Copy and Play Saved Queue. Its optional source setup uses a separate scoped key for a manually started local-file host helper. [Setup, limits and recovery](OFFLINE-COPYING.md). Authenticated routes are `GET /api/offline-status`, `POST /api/offline-source` with `origin` and `key`, and `POST /api/offline-save` with action `save` (start or resume), `cancel` (pause), `discard` or `play`. These routes use the same web-remote access/range policy. Status never returns a source key or local file paths. Saving is one explicit operation; a repeated Save while active does not start a second copy. Check status after a lost reply.
