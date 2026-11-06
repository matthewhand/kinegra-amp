# Sendspin output timing, boundaries and backpressure

The integration uses the pinned SDK plus `sendspin-ordered-clear.patch` and `sendspin-outbound-only.patch`. Builds apply them to a disposable source export; the upstream checkout stays unchanged. Each modified SDK file retains its upstream licence header and carries a dated Kinegra Amp modification notice.

## Ordered clear

The SDK invokes `on_stream_clear()` at its synchronized boundary. Kinegra Amp's PCM bridge empties the native queue, advances generation and waits for the Godot consumer to acknowledge that its generator and staged PCM have also been discarded. Missing acknowledgement fails closed after 500 ms. Old-generation writes and reports are rejected. A missed clear acknowledgement latches a fatal session failure: retries remain bounded while Main is blocked, and the next adapter tick closes the client and reports failure. Stream boundaries cannot release the latch; an explicit reconnect after the worker stops starts cleanly.

The bridge declares `flushes_audio_on_stream_clear() = true`. After that callback returns, the SDK drops pending old playback progress, resets its buffered-frame count and predicted output endpoint, and re-enters the normal priming path. This prevents a flushed tail from remaining on the SDK's timeline: otherwise it can continuously discard post-clear audio as late while the app plays silence. The LOAD_CHUNK guard also covers a clear marker decoded before the outer command flag is observed.

The capability defaults to false, so SDK sinks which keep draining their old output retain upstream accounting behaviour. Discarded frames are never reported as played.

## Backpressure

A full native ring honours the SDK's write timeout using a condition variable. The SDK's TRANSFER_AUDIO loop retries immediately after a zero write, so returning immediately on a full queue spins its sync thread. Reads wake a blocked writer; stop, restart and clear also wake it and reject the old write. The caller's timeout bounds the wait, and only the SDK background thread waits.

## Mixer clock continuity

Godot generator free-space changes are the source of consumed-frame counts. Driver `time_since_last_mix` timestamps move in blocks and are not precise timestamps for those particular frames. Re-anchoring every progress report to that raw timestamp produced ±25 ms phase jumps in a synthetic host trace. The SDK's unchanged 5 ms hard-sync threshold then repeatedly inserted zeros or dropped prefixes, even while the generator underrun count stayed zero.

Mixer feedback now anchors the finish clock to measured cumulative consumption. It acquires phase over the first 32 accepted reports, averages a bounded 32-report window of raw clock offsets, and then slews offset at no more than 500 ppm of consumed audio duration. This tracks slow drift without turning driver timestamp quantization into repeated hard corrections. Generation changes reset the clock; a real generator underrun explicitly re-anchors it. No consumption means no progress report, and existing timestamp bounds still fail closed. State advances only after the SDK accepts the report.

The continuity regression uses generated opposite-channel ramps to distinguish zero insertion, large frame jumps and channel errors from ordinary one-frame SDK soft correction. After one second of startup acquisition, an eight-second host run before the fix contained 31,189 zero frames in 94 runs and four large jumps; both steady and bounded-jitter runs after the fix contained zero zero-filled frames and zero large jumps. These are samples accepted by the generator, not captured HDMI audio.

## Strict stream format

The bridge verifies each accepted `stream/start` header before enabling writes: PCM, 48 kHz, stereo, 16-bit, with all fields present. Advertising that one format does not by itself validate the server's chosen header. Unsupported formats latch a fatal session failure and cannot be revived by another stream boundary; only closing the SDK worker and explicitly reconnecting clears it. Numeric-only native tests exercise missing fields, wrong codec/rate/channels/depth, write/ack rejection and explicit recovery.

## Synthetic coverage

`native/tests/test_sendspin_backpressure.cpp` covers timeout, consumer wake, stop/restart cancellation, clear cancellation, and fatal-clear timeout/latch/reset; the existing bridge test covers frame alignment, wraparound, generations and the ordered-clear acknowledgement. Both run with ASan/UBSan. The patched SDK's PlayerInboundHandOff tests cover clear ordering, buffer/progress reset and preserving non-flushing sink behaviour.

The encrypted loopback fixture supports these modes:

```sh
python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" continuity
python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" continuity-jitter
SHIELDAMP_CONTINUITY_SECONDS=30 python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" continuity-jitter
python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" main-timeout
python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" buffer
python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" sustained
SHIELDAMP_STRESS_SECONDS=60 python3 native/tests/test_sendspin_paired.py "$GODOT_BIN" "$HOST_ADAPTER" sustained
```

The continuity modes live in `native/tests/test_sendspin_continuity_network.gd`; duration is bounded to 8–120 seconds. The jitter mode varies delivery deadlines by up to 25 ms without changing the producer clock.

The `main-timeout` scenario stalls output acknowledgement beyond the clear deadline, requires the client and sink to close, then explicitly reconnects and requires fresh nonzero PCM through Main.

The sustained scenario runs at 50 Godot frames per second, introduces 100 ms main-loop stalls, forces a one-second underflow, varies network delivery timing with a 350 ms gap, and clears a mature stream. It requires playback to recover, real nonzero replacement PCM to arrive, and zero stale pre-clear frames. Its duration is bounded to 16–120 seconds. All identities/audio are synthetic, the bus is muted, and it never contacts Music Assistant or a device.

Mixer feedback remains an estimate rather than a hardware/DAC timestamp. Host fixtures do not establish audible HDMI quality or multi-room synchronization.
