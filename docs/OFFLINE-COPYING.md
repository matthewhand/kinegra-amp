# Save Queue Offline

**Experimental.** Amp retries temporary errors twice per track. A track that still fails stays available for a later retry while the rest of the queue continues.

Open Queue and choose **Save Queue Offline**. Kinegra Amp saves a snapshot of the current track and upcoming tracks, up to 8,192 entries per copy, into its internal Offline Library. **Pause Saving** keeps completed files and download progress. Choose **Resume Saving** to continue after a pause, app restart, or a batch with failed tracks. **Discard Pending Copy** clears the pending snapshot and partial file while retaining completed tracks. **Play Saved So Far** can start completed copies while the rest downloads. **Play Saved Queue** starts the saved copies in the same order, including repeats, and replaces only Kinegra Amp’s local queue. Saving itself never changes playback or the Music Assistant queue. The saved order survives a restart. The web remote can save a smaller number from the same queue. The library supports up to 4,096 unique audio files, subject to available storage. Existing offline imports and USB originals are preserved.

This feature copies your own local files. It does not download subscription-provider streams, bypass DRM, or save Music Assistant preview clips. Unsupported tracks are counted and skipped. Each file is limited to 64 MiB; copying stops when less than 256 MiB of free storage would remain. Failed transfers never become library tracks. The app checks length and SHA-256 before committing an audio file and receipt. Downloads run one at a time and pause when the app goes into the background. Resume uses the original snapshot and requires the same Music Assistant and file-source origins. Identical audio shares one offline file, even when the saved queue intentionally repeats a track. Once the queue snapshot is captured, switching to local playback keeps copying. New arrivals remain in Offline Library; Play Saved Queue explicitly loads the latest saved order.

## Optional file-source helper

Run `clients/offline_source.py` on a host with read access to the same music tree used by Music Assistant’s Local Files provider. The helper is never started automatically by Kinegra Amp. Python 3.11+ is required. Install FFmpeg on that host for M4A/AAC/FLAC/WAV conversion. MP3 and Ogg files are copied directly; other supported files become 192 kb/s MP3. The Shield performs no conversion. FFmpeg is an external tool, distributed under its own license.

Create a private random key file outside your checkout, for example with `umask 077; python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > /path/to/private-source.key`. Run:

```sh
python3 clients/offline_source.py --root /path/to/music --cache /path/to/private-cache --key-file /path/to/private-source.key --bind 192.168.1.30 --allow 192.168.1.20
```

Replace addresses with your host and Shield. The root must match provider-relative file paths. Use a read-only mount when the library is remote. Keep the cache outside the repository and release assets. It contains your music. The helper binds to loopback unless an explicit private IPv4 bind is supplied. Exact allowed client addresses and a separate random bearer key are mandatory. It does not receive Music Assistant credentials, accept remote URLs or log file paths. Its HTTP connection requires a trusted private LAN; do not expose it to the internet.

In Kinegra Amp’s Settings, enter the source origin and its key, then Save Local-File Source. You can also use the corresponding setup fields in the web remote’s Queue panel. The scoped key is kept in app-private settings. To revoke access, stop the helper or rotate its key. The helper cache is retained for subsequent copies; manage that host directory yourself. The current helper supports byte-range downloads. Older helpers can resume the batch from the interrupted track by transferring that file again. The helper stays idle until Amp requests a copy, and its cache is managed on the host.

Normal Sendspin streaming keeps rolling buffers rather than whole-track files. Its ten-second seek still asks Music Assistant. Downloaded local files support seeking without a new network request.

## Streaming recovery

A starved local mixer pauses before running dry and resumes after 384 ms of output has refilled. The upstream Sendspin lead target remains 4 seconds, with a 3 second minimum. Visuals remain reduced during startup/refill. If a requested stream stalls, Kinegra Amp can reconnect its own paired output with up to 3 bounded attempts. It does not repeat Next/Add mutations, resume a fresh paused/stopped server queue, or autoplay on app entry. Pause, Stop, a changed connection and backgrounding cancel recovery. Recovery cannot repair an unavailable disk or music provider.
