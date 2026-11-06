# Portable Music Assistant collection adapter

Implemented in `feat/roadmap-ma-catalog`, based on the streaming-reliability
candidate. The new adapter browses library tracks/playlists and lets a user
select metadata without creating queues, issuing playback, copying library
audio, refreshing metadata or inventing stream URLs.

## Source and live evidence

On 25 October 2026, public documentation from the running MA 2.10.7 instance
advertised these authenticated read commands:

- `players/all` (`players.read`), `player_queues/all` (`queues.read`).
- `music/tracks/library_items`, `music/playlists/library_items`,
  `music/tracks/get`, `music/playlists/get`, and
  `music/playlists/playlist_tracks` (`library.read`).

`bridge/contracts/ma-2.10.7-readonly.json` preserves only the public command and
model definitions relevant to this adapter, including source-document hashes.
It contains no credentials or private library metadata. The real endpoints were
`/api-docs/commands.json` and `/api-docs/schemas.json` on the existing MA server.
Track/playlist list responses are arrays; `limit`, `offset`, `search`, `order_by`
and `summary` are supported. The documentation advertises variadic `kwargs` as
required in one generated command definition; the adapter does not send arbitrary
kwargs or impersonation arguments. Authenticated live execution remains to be
verified with an owner-provisioned token.

Playlist contents expose no server-side limit/offset parameters in the current
command schema. The adapter caps the HTTP response at 2 MiB and its displayed
preview at 250 items, marks truncation, and does not pretend playlist contents
are paginated. Listing metadata can still perform provider work on MA; it is
read-only, not a promise of zero server CPU/cache activity.

No authorized MA token was supplied to this adapter, and no authenticated live
catalog or audio request was made. Missing authorization is represented as an
empty setup/auth-required state. Existing browser sessions are not credentials
for this client. No unrelated application's tokens were inspected.

## Python operator and portable contracts

`bridge/ma_catalog.py` uses only Python's standard library. Configuration v1 is
JSON, with `api_origin`, up to four `stream_origins`, and optional
`tailscale_node_id`. The shipped example has empty endpoints. HTTP bearer
transport is allowed only to a configured literal Tailscale IP after verifying
both the route through `tailscale0` and its stable node ID. Ordinary HTTPS uses
normal certificate validation. Proxy inheritance and redirects are unsupported.
Control characters, credentials/query/path in origins, malformed ports, unknown
config fields and unapproved write commands fail closed.

The HTTP client has a 2 MiB reply cap and an absolute eight-second deadline,
enforced by socket shutdown even if a server drip-feeds bytes. Cancellation
also interrupts blocked reads. Only one request per session runs at a time.
Status errors contain fixed codes, not response bodies, tokens or URLs. A 401
or 403 drops credential references. Python immutable strings cannot be
guaranteed zeroized.

Metadata pages use `shield.catalog.v1`: bounded item IDs/provider/name/type,
sequence/epoch, offset and explicit `may_have_more`. Provider mappings, raw
stream URLs, artwork and opaque metadata/details are excluded. Selections use
`shield.selection.v1`, expire after 60 monotonic seconds and on cancellation,
and never play automatically. No metadata/audio cache or permanent file copies
are created.

`CatalogSession.discover_players()` stores only the current session's bounded
authenticated player-media observations in memory. Only an explicitly selected
fresh player ID can be inspected by `existing_stream_candidate(player_id)`.
Library identifiers remain unresolved. An existing HTTP(S) URI must match a
configured origin, with no embedded credentials/query/traversal, and is still
labelled **unverified, not playable, requires format probe**. The adapter never
rewrites its host, fabricates an endpoint, GETs media or starts a queue.

```sh
python3 bridge/ma_catalog.py --config /path/to/owner-installation.json
python3 bridge/ma_catalog.py --config /path/to/owner-installation.json --live --kind playlists
```

The default command validates setup only. `--live` requires an interactive TTY
and takes an owner-provisioned token through hidden `getpass`, never argv/env,
files or logs. Use the owner's supported MA token workflow with `library.read`
and `players.read` for the needed operations. Do not paste tokens into chat.

## Standalone Godot integration

New files `app/scripts/MACatalog.gd` and `MASetupPanel.gd` deliberately leave
the owning app's Main script untouched. Add `MASetupPanel.gd` to a ScrollContainer
with horizontal expand/fill and focus following. Connect:

- `media_selected(item)`: metadata selection only. The caller must obtain a
  legitimate playable URL separately before invoking its explicit player.
- `close_requested`: hide the optional panel and restore the previous focus.

`MACatalog.configure(api_origin, token, stream_origins=[])` validates an HTTPS
origin and keeps token references only in memory. Ordinary private HTTP is
refused because the Shield has no verified Tailscale channel. The panel masks
token input, clears the field after a connection attempt and on disconnect,
and closes the session on application suspend. HTTPRequest has an eight-second
timeout, 2 MiB body cap, 16 KiB chunks, zero redirects and cancellation epochs.
It offers bounded tracks/playlists/search pages, playlist preview, explicit
selection and useful disconnected/auth-expired/permission-denied states.
`discover_players()` and `player_stream_candidate(player_id)` retain the same
provenance/freshness distinction as the Python client; they do not fetch audio.

## Development bridge configuration amendment

The optional FFmpeg bridge no longer embeds an installation-specific upstream
address. It remains disabled by default and loopback-only. Explicit operation:

```sh
python3 bridge/codec_bridge.py --allow-ma --upstream-origin https://your-authorized-stream-origin
```

An explicitly configured literal private HTTP upstream additionally requires
`--allow-insecure-private-http`. The bridge accepts only URLs at that origin,
refuses recognizable credential query fields, retains no redirects/proxies,
and never acquires or generates a stream URL. Existing pinned
`discover_ma.py`/`real_stream_probe.py` are preserved historical operator tools;
new integration should use the portable adapter. Their installation assumptions
have not been silently generalized.

## Validation and roadmap amendment

- **58 Python tests pass** across the full existing bridge/discovery suite plus
  the new catalog tests. They cover config/transport identity, allowlisted
  arguments, read-only bounds, privacy, selection expiry, metadata-refresh
  suppression, playlist truncation, provenance, malformed/error/stale replies,
  HTTP auth, no redirects, oversized responses, drip-feed timeout and active
  cancellation. All network fixtures are synthetic loopback servers.
- **20 real Godot checks pass** for optional empty setup, HTTPS-only credential
  transport, page processing, privacy, no-play selection, stale callback/selection
  expiry, authenticated-observation provenance, auth expiry and masked token UI.
- Existing synthetic MP3/OGG → FFmpeg → HTTP PCM → Godot FFT tests still pass.

Amend MILK-06/07/08 and RACE-17 into two evidence stages: portable read-only
catalog implementation (implemented/tested here), then owner-authenticated
installation acceptance (still unverified). MILK-09 is provenance validation
only until a legitimate server-generated stream and actual format are observed.
No claim is made that this is a general MA renderer or that unauthenticated
HTTP 401 is a successful integration. Original collection files and sync remain
untouched. Native decoder and on-device acceptance are independent workstreams.


## Watchdog follow-up audit

Independent real-HTTP fixtures exposed a buffered-reader cleanup deadlock that
the original cooperative in-memory source test did not cover. The bridge now
captures the upstream HTTP socket before starting its input worker, shuts it
down on watchdog/cancellation before buffered close/join, and applies an absolute
header deadline before decoding starts. Actual drip-fed header/body cancellation
regressions assert bounded return, closed source, process reap and no retained
input worker. Successful direct-source and refused-redirect cases are covered.
Synthetic FFmpeg roundtrips now include actual FLAC and AAC/ADTS in addition to
MP3, Ogg Vorbis and WAV; this adds no native Android AAC/FLAC claim.
