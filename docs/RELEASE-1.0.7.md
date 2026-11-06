# ShieldAmp 1.0.7

*Historical release notes from before the Kinegra Amp rebrand.*

Save Queue Offline copies a bounded snapshot of local-file tracks into internal storage, preserves order/repeats and offers Play Saved Queue. It includes progress, cancellation, integrity checks, durable receipts/order and matching web controls. An optional, manually started host helper reads the owner’s local library and converts supported formats outside the Shield. See [setup and limits](OFFLINE-COPYING.md).

Streaming now records receipt of digital silence separately from audible signal, pauses at low water and refills before resuming. Bounded own-output recovery respects explicit and external pause/stop; it does not retry queue mutations or autoplay on launch. Native dependencies and music-free packaging are unchanged. Device acceptance is recorded separately after installation.
