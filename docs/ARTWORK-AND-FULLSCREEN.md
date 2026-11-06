# Artwork and fullscreen presentation

Fullscreen shows the current item reported by the verified Kinegra Amp queue, including title, artist, album and track timing when provided. Library selection remains separate while actual music is playing. Missing credits, empty queues, disconnected sessions and metadata older than ten seconds revoke the old display. Radio or other unknown-duration sources never acquire an invented timeline.

Elapsed time advances only when recent local PCM and a fresh playing queue snapshot support it, using the existing same-origin HTTP Date and monotonic clock policy. Paused/idle or temporarily silent sources show the last reported position explicitly. This is server metadata, not a measured hardware playback timestamp.

Fullscreen remote controls are **OK/A: Play or Pause**, **Left/Right: Previous or Next**, and **Back/B: controls**. Entry and interaction reveal the help; Back preserves the existing popup/return-focus path. These handlers leave the existing mouse, cursor and system-volume path intact. Human remote/controller acceptance is still required.

## Supported artwork source

The implementation follows Music Assistant **2.10.7**, source revision `76ad754a68abdd0bfd179b13a2807d44771ddf90`:

- [Canonical image-proxy handler and generated URLs](https://github.com/music-assistant/server/blob/76ad754a68abdd0bfd179b13a2807d44771ddf90/music_assistant/controllers/metadata/images.py): `/imageproxy/<proxy_id>?size=256&fmt=png`.
- [Allowed image sizes](https://github.com/music-assistant/server/blob/76ad754a68abdd0bfd179b13a2807d44771ddf90/music_assistant/controllers/metadata/constants.py), including 256 pixels.
- [Opaque SHA-256 image identity](https://github.com/music-assistant/server/blob/76ad754a68abdd0bfd179b13a2807d44771ddf90/music_assistant/helpers/images.py).

`MAArtworkPolicy.sanitize(media)` keeps only a server-provided 64-character lowercase hexadecimal `proxy_id` from a thumbnail/image descriptor. It can inspect a queue item's media item and album fallback. Provider paths, remote URLs and other payload fields are discarded. Servers or media without this supported ID use the original logo labelled **BRAND ART**. No legacy path URL is guessed.

`MAArtworkController` fetches only this constructed route on the configured MA API origin. Bearer credentials stay in headers, never URLs. Redirects are disabled. Each controller permits one request, a five-second timeout, at most 512 KiB response bytes, PNG-only decoding, and an IHDR geometry check before decoding (at most 512 × 512 pixels). Textures are reduced to at most 256 × 256 and retained in a four-entry session-only RAM cache. No download file or image disk cache is used.

New view/generation changes cancel old requests and discard late callbacks. Session/credential closure, authentication failure and backgrounding clear requests, textures and in-memory credentials. Ordinary drawer closure may recover authorized origin-bound playback access from the RAM-only session, or saved access through the reviewed vault getter, while the library is not explicitly disconnected, this exact local player remains paired and active, and a genuine current image ID exists. Forget, changed origin, explicit disconnect and credential-generation signals cannot revive a prior artwork session. An artwork HTTP 401/403 clears the image session immediately and blocks automatic retries within that same catalog/player binding; new catalog authorization is required. The vault is read once per such session, not on each frame.

Covers are shared across the player, TrackHero and fullscreen. Adaptive budget zero retains the static cover and metadata while stopping TrackHero's animation callback; identical metadata does not request another repaint.

## Synthetic checks

```sh
xvfb-run -a "$GODOT_BIN" --path app --no-window --script res://tests/test_ma_artwork_policy.gd
python3 native/tests/test_ma_artwork_http.py "$GODOT_BIN"
python3 native/tests/test_presentation_ui.py "$GODOT_BIN"
```

Set `SHIELDAMP_TEST_TMPDIR` to a suitable scratch directory if required. The UI harness copies the app with generated silent audio and solid artwork, isolates user data, builds the host codec from checked source, and mutes output. Optional `SHIELDAMP_PRESENTATION_IMAGES` captures only these generic fixture screens outside the repository.

Coverage includes actual current/selection transitions; missing/stale metadata; server-clock, paused and radio timing; Play/Pause/Previous/Next/Back routing; return focus; long names and large text at 4:3, 16:9, ultrawide and portrait sizes; all help lines visible; and static-cover behavior at adaptive budget zero. Loopback HTTP cases cover valid generated PNG, same-session cache, cross-origin redirects, byte limits, oversized decoded geometry, SVG refusal, cancellation races, bounded cache/texture sizes, generation changes and background cleanup. Credential-contract fixtures check one vault read per session, immediate Forget cleanup and refusal to reuse a token after an origin change.

These tests establish implementation behavior using generated media. They do not establish real-provider artwork availability, physical controller behavior or audible playback acceptance.


With decorative visuals off (including stream warmup/audio-first mode), the cover is centered in the free canvas: between header and transport in landscape, below the controls in portrait. A small viewport without room keeps its dock thumbnail. The larger cover and track hero both suppress the dock thumbnail so playback artwork appears once. Fullscreen centers the combined cover/text card; on wide artwork-only screens, the temporary help sits beside it instead of reducing or displacing the cover. These layout changes do not alter playback or avatar/gesture geometry.
