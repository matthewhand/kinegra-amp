# Command-line remote

Python 3.9+ and the standard library are enough. Run this from a source checkout, with Kinegra Amp 1.0.5 or newer open and Web remote enabled. Use the address and current key shown in the app’s Settings. The service remains off by default in production.

```sh
export KINEGRA_AMP_ACCESS_KEY='YOUR_CURRENT_ACCESS_KEY'
python3 clients/kinegra_amp_remote.py --url http://192.168.1.20:8765 status
python3 clients/kinegra_amp_remote.py --url http://192.168.1.20:8765 browse playlists --search 'My playlist'
python3 clients/kinegra_amp_remote.py --url http://192.168.1.20:8765 open --page-id 1 --item 0
python3 clients/kinegra_amp_remote.py --url http://192.168.1.20:8765 add --page-id 2 --item 0
python3 clients/kinegra_amp_remote.py --url http://192.168.1.20:8765 queue
python3 clients/kinegra_amp_remote.py --url http://192.168.1.20:8765 play
```

Replace the example address, key, page IDs and row IDs with your own current values. The tool prints JSON. Browse/open results provide page-local IDs: another browser/library request or a changed connection can invalidate them. Refresh after a stale-page error.

| Command | Purpose |
| --- | --- |
| status / diagnostics | Display state or connection/audio-buffer evidence |
| play / pause / previous / next / stop | Existing app transport controls |
| browse tracks/albums/playlists | Search and page the library; --search and --offset |
| open --page-id N --item N | Open a current album/playlist row |
| page --page-id N --offset N | Page/filter an opened collection |
| play-item --page-id N --item N | Explicitly play a current row in Kinegra Amp |
| add --page-id N --item N | Append a current row |
| add-page --page-id N | Append the displayed page’s available tracks |
| queue | Read up to ten upcoming queue items |

If you deliberately disable Require access key in the app, clients in your trusted ranges can use --no-key. It cannot bypass a key-required session. The CLI accepts private IPv4 HTTP addresses only, never forwards through an environment proxy or HTTP redirect, and does not save a key or music metadata. Keep credentials out of shell history; use a session environment or your shell’s protected input mechanism.

Operations have a bounded polling deadline (--wait-seconds, default 42, maximum 60). A mutation is sent once; a timeout or lost reply may mean it completed. Inspect Queue before repeating it. Add/play-item actions print their request ID to stderr and accept --request-id for identifying the exact same action; the server deduplicates only while its bounded job remains available. Never use an old request ID for a different action. An accepted transport request is not proof that audio arrived; inspect diagnostics or listen on the device. Exit 0 means a completed read/operation or an accepted transport; exit 2 reports a client/remote error.

The tool uses the app’s verified own-output routing. It cannot target another Music Assistant player or change server credentials. Offline-library control, queue editing/reordering, settings and full web/TV UI parity remain outside this CLI’s scope.

Run the loopback checks with python3 tools/test_remote_cli.py. These use fictional metadata and disposable credentials, not a live library or Shield.
