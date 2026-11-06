# Startup buffering and local audio occupancy

Kinegra Amp requests **3,000 ms minimum ongoing send-ahead** and **4,000 ms startup lead** from the Sendspin server. The server schedules the first timestamp accordingly; Kinegra Amp does not pause a running queue or sleep its output thread to simulate buffering. This follows the [Sendspin buffering contract](https://www.sendspin-audio.com/build/spec/): startup lead is separate from output delay, and natural track transitions keep the existing stream continuous. Manual skip/seek can clear and refill it.

The native adapter accepts only the existing PCM 48 kHz/stereo/16-bit format (192,000 bytes/s). Its 2 MiB SDK buffer budget has room for the 768,000 PCM payload bytes in four seconds plus chunk overhead; the pinned SDK advertises a smaller safe usable capacity. The 100 ms bridge, Godot staging and 384 ms mixer prefill remain bounded independently. A server must honor the advertised timing to provide this cushion; this is not a whole-song download or an offline-playback promise.

## Presentation

`Buffering audio…` is a detail of the existing paired/receiving lifecycle, preserving route ownership and control availability. An observer reads the first inbound PCM timestamp and bounded, filtered control JSON fields (`type`, player roles and codec, at most 4,096 bytes). It uses the SDK's existing optional message observer, which must be enabled in **both** the SDK and adapter builds (`SENDSPIN_ENABLE_MESSAGE_TRACE=ON`). No SDK patch changes are needed. Traces precede SDK admission, so these observations are candidates only: the admitted player callback confirms the matching active bridge generation before they can affect UI, and the current USER-trust status must also be true. A genuine start while the bridge is inactive replaces any pre-admission candidate; an in-place active start preserves its timeline. Deferred USER notification cannot discard the first authorized header. The observer logs no messages, retains no payload/credentials and ignores all outbound messages. SDK logging remains disabled.

The timestamp is mapped through the synchronized SDK clock. The buffering detail ends when that scheduled timestamp arrives, rather than when future audio is merely enqueued. A clear resets it; an in-place start or metadata-only natural transition does not reset the timeline. Actual local output underflow can also show buffering. This is not a measured DAC timestamp.

The muted secondary progress fill and `Buffered ~0.7s` readout show a **lower bound** from disjoint, generation-checked local PCM stages: native ring bytes, unsubmitted pump bytes and actual Godot generator occupancy. They exclude SDK encoded lookahead, hardware latency and server caches. The fill extends from played position toward the local buffer endpoint, clamped to the current track duration. Radio/unknown duration shows seconds only, never a fabricated percentage. Current playback-session metadata is required; selecting a catalogue item cannot populate it. Clears, accepted seek/skip, stale metadata, disconnect and credential/session invalidation remove old figures. A paused track may retain its figure while those actual queued frames remain.

## Focused verification

On Ubuntu, with the pinned reviewed SDK source and both existing patches unchanged:

- `native/tests/test_sendspin_startup_buffer.cpp`: bounded policy, malformed header rejection, first-timestamp-only retention, clear/end/restart and no reset for in-place start.
- `native/tests/test_sendspin_paired.py GODOT HOST_ADAPTER startup`: encrypted loopback with synthetic identities/audio, jittered cold start, manual clear/refill, reconnect and cancellation. The fixture requests a four-second lead and three-second minimum. It rejects loss of a complete 20 ms chunk while allowing sub-chunk synchronization adjustment.
- `... continuity-jitter` with `SHIELDAMP_CONTINUITY_SECONDS=30`: ongoing ramp continuity across repeated delivery jitter; no intentional boundary pause.
- `app/tests/test_playback_buffer_presentation.gd`, `test_local_audio_buffer.gd` and `test_buffered_playback_ui.gd`: stale/invalid values, generation/auth/command invalidation, paused occupancy, radio, layered fill and widget bounds at host 4:3, 16:9, 21:9 and portrait sizes.

The test output records actual waits, first ramp samples, continuity counts and local queue results. All fixture identities/audio are synthetic. Hardware listening and physical remote/display behavior require separate device checks.

## Startup workload and queue preparation

A temporary render cap begins with an explicit Play/skip preparation or a newly admitted audio generation, before the ordinary adaptive governor needs to detect pressure. It removes animated shaders, avatar rendering and unused FFT work while preserving the user's quality, visual and dancer choices. Static cover art remains event-driven, including fullscreen; absent art is labelled as brand artwork. The cap lifts after scheduled buffering has ended and local queued audio has remained at least 384 ms for two continuous seconds. A low buffer restarts that window. An unchanged generation does not re-arm it on ordinary metadata/track transitions. An unanswered preparation has a 20-second display bound; connection, pairing and request deadlines remain separate. Explicit webcam gestures may retain their existing limited tracking budget.

This changes the server's scheduling request and local readiness threshold. It does not sleep an already scheduled audio thread or pretend that elapsed wall time proves cached audio. The server must honor the advertised lead and capacity. The protected production builder still requires the exact-native optimized Android Noise proof.

The reviewed [Music Assistant stream feeder](https://github.com/music-assistant/server/blob/76ad754a68abdd0bfd179b13a2807d44771ddf90/music_assistant/controllers/player_queues/stream_feeder.py) prepares upcoming audio buffers internally. No public command for independently downloading the first queued song before Play was identified in that source. Kinegra Amp therefore uses protocol send-ahead and the server's normal preparation. It does not record Sendspin or turn a preview into a full-song cache, and makes no separate first-queued-track download claim.
