# Android secure storage plugin

Kinegra Amp includes this Godot 3.6 plugin as `ShieldAmpTokenStore`. It keeps Music Assistant library access and Sendspin pairing in separate Android Keystore-backed records. A production update must preserve the original signing identity and app data.

## Library credential lifecycle

Library settings offer **Connect library**, **Disconnect library**, and a confirmed **Forget saved access**. Typed access stays in memory unless the owner explicitly enables **Remember access securely on this device**. Remembering waits for a successful authenticated catalog response; failed/revoked requests and cancelled or changed-server sessions never commit the pending value.

Saved access and its normalized server origin share one authenticated encrypted record and one atomic file transaction. The library loader refuses a different origin. An older unbound encrypted/provisioned token can migrate only through its original saved connection; an unknown server requires explicit replacement access. Changing the server or connection trust cancels requests, clears in-memory access and invalidates pending saves. Pause/focus loss also clears unsent and pending credentials, cancels catalog requests and hides pairing-token/code dialogs.

Migration reads the secure replacement back and compares exact token bytes before deleting the legacy `music_assistant_token` file. A previously staged matching copy can now finish cleanup. Conflicting records fail closed without using either token; write/read failures preserve the original. `secure_no_legacy` and `migrated_no_legacy` explicitly identify a verified secure record with no legacy file. `legacy_conflict`, `secure_legacy_remains` and storage errors require an actionable retry/forget/replacement flow rather than a plaintext fallback.

Forget is local to this app's MA library access. It first persists a reuse-blocking marker, then destroys only the MA token key and removes its encrypted/backup/temporary records and legacy file. If the initial marker cannot be persisted, the forget operation fails before changing saved records. Once the marker exists, partial cleanup stays blocked and reports failure so the owner can retry. It does not touch Sendspin pairing identity, connection preferences, other apps, other players or server queues. It does not call a server-wide token-revocation API; use Music Assistant to revoke the credential on the server. The UI emits `credential_session_closed(reason)` after cancelling requests and clearing in-memory access, and `credential_forgotten` only after saved access is removed; the app may stop its own playback session for the `forget` reason while preserving pairing.

Legacy deletion makes a bounded best-effort overwrite before unlinking. Flash storage, filesystem journals and managed Java/Godot String copies prevent a promise of physical forensic erasure. Destroying the Keystore key makes the app's encrypted record unusable; the forget marker prevents automatic reimport after a partial failure.

## Offline source build

Supply the pinned Godot 3.6.3 release AAR, an Android platform jar and JDK 17:

```sh
python3 android_secure_storage/build_offline.py --godot-aar /path/to/godot-lib.3.6.3.stable.release.aar --android-jar /path/to/android.jar --javac /path/to/jdk/bin/javac --output build/ShieldAmpTokenStore.aar
```

`GODOT_AAR`, `ANDROID_JAR`, `JAVAC` or `JAVA_HOME` can supply the corresponding tool inputs. The output must be new. The builder validates the engine hash, compiles against its real plugin API and runs migration, credential-record, forget-ordering, snapshot and task-policy host tests. The [Android preview builder](../docs/BUILDING.md#android-development-preview) invokes this stage in a separate development package. Production validation checks plugin registration, required APIs and JNI return descriptors in exported DEX. Compilation alone does not establish Godot JNI or device Keystore behavior.

## Godot interface

- `loadTokenForEndpoint(String)`, `storeTokenForEndpoint(String, String)` and `tokenEndpoint()` are the library's origin-bound access APIs. `forgetToken()` removes local saved access; `storageStatus()` reports the result without revealing a token.
- `loadToken()`, `loadTokenStaged()` and `storeToken(String)` remain compatibility/proof APIs. The app's library flow uses the endpoint-bound APIs and completed verified migration.
- `loadSendspinSnapshotBase64()`, `replaceSendspinSnapshotBase64(String)` and `sendspinSnapshotStatus()` bridge a bounded opaque pairing snapshot. Failed writes preserve its committed record; forgetting library access never calls these methods.
- `processCpuTimeMs()` returns current-process accumulated CPU milliseconds as a decimal String for Godot 3 JNI. It is not total-device idle percentage. `thermalStatus()` returns Android's thermal severity on API 29+, or `-1` when unavailable.
- `hasUsbWebcam()` reads USB video-device metadata only; it does not open a camera or request camera permission.
- `staleTaskPrunedCount()` reports only tasks removed by this process's resume hook. The verified `onMainResume()` hook inspects this app's tasks, keeps the current task and removes only other tasks whose base component matches this exact package and `com.godot.game.GodotApp`. It never performs a global recents cleanup or clears app data.

## Acceptance boundaries

Synthetic tests cover matching/conflicting upgrades, failed migration read/write/delete, record bounds and origin binding, forget ordering/failures, explicit remember consent, authenticated-save timing, invalid/revoked access, disconnect, server/trust change, stale replies and preservation of pairing/settings. The task policy rejects current, unknown and other-app components. No real token appears in those fixtures.

Actual Android Keystore invalidation, filesystem failures, cold restart/upgrade/logout on the signed target, JNI dispatch and stale-task removal still require native acceptance. No owner credential is forgotten by a host test. Trusted private HTTP remains unencrypted despite origin binding. Debuggable builds and privileged device access can inspect live process data; Keystore storage is not a defense against a fully controlled device. Production manifest backup/debug flags must be verified on the final release APK, independently of these library sources.


### User-selected offline audio

The plugin also exposes `beginOfflineImport(String directory): boolean`, `offlineImportStatus(): String` and `cancelOfflineImport(): boolean`. Godot passes its globalized `user://offline_music` directory. Java verifies it is an app-private descendant named `offline_music`, with no symlink parents below the private root. This uses the Storage Access Framework's explicit document picker; it adds no broad storage, media, camera or network permission, retains no URI grant and never modifies or deletes the selected source document.

One selection is limited to 32 content documents. Copies accept MP3/Ogg container signatures, at most 64 MiB each, preserving a 128 MiB free-space reserve from the initial free-space measurement. The player still validates whether a copied stream can decode. SHA-256 filenames deduplicate exact bytes; a corrupt existing hash file fails without overwrite. Copies stage in a private `.part` file and sync before publication. Each audio file has exactly `<audio filename>.meta.json` atomic metadata with version, filename, local title, byte count and hash. Source URIs, local titles, payloads and errors containing private paths are never logged or included in status.

The JSON status contains `state`, `reason`, `imported`, `skipped` and `errors`. States are `idle`, `choosing`, `copying`, `complete`, `cancelled`, `cancelling`, `timed_out`, `error` and `picker_unavailable`. Successful files completed before cancellation remain in the library. New file/metadata work checks cancellation at transaction boundaries; partial files and an uncommitted newly copied audio file are removed. Metadata failure on an existing duplicate preserves its original audio.

Picker callbacks use distinct request IDs, so an old cancelled result cannot import into a newer selection. Each file has a 60-second deadline covering provider query, open and copy; an unattended picker expires after five minutes. Cancellation stops further copies, cancels the provider query and closes an active stream. **A provider can ignore cancellation or block while opening a document.** In that case status stays `cancelling` with its reason and another worker cannot start until the old one exits. This deliberately bounds the app to one copy worker and one watchdog rather than accumulating stalled jobs. No timeout can promise to forcibly terminate arbitrary provider code.

The offline builder runs synthetic file, cancellation and epoch-ordering tests alongside the existing credential tests. Its `@Override` callback compiles against the pinned actual Godot 3.6.3 AAR. Production packaging also verifies the three exact JNI method descriptors in DEX. These checks do not prove a physical USB provider/picker workflow; that remains a separate device acceptance step. Token/Keystore and Sendspin identity code are unchanged by this importer.


Admission also enforces the Godot library's 1,024 **stable identities**, including deleted slots. Before publishing a new hash and again before its receipt, Java reads the bounded version-1 catalog and unions it with pending hash audio/receipt/delete files. Known hashes can restore their original slots at the limit; an unknown 1,025th identity fails before publication. This reserves consecutive batch imports even before Godot adopts their receipts. Catalog reads never write, repair, compact or renumber it. A missing catalog with the stable-slot marker or an interrupted catalog file, malformed/future catalog, duplicate identity, unsafe path or oversized directory fails closed. Strict JSON/UTF-8 validation precedes Android's otherwise lenient platform parser.

`OfflineCatalogSyntaxTest` and `OfflineLibraryAdmissionTest` run in the ordinary offline builder without new dependencies. `OfflineCatalogJsonTest` additionally exercises the platform-adapter schema using an operator-supplied host implementation of `org.json`; the recorded local run used JSON-java 20240303 solely as a test tool (SHA-256 `3cf6cd6892e32e2b4c1c39e0f52f5248a2f5b37646fdfbb79a66b46b618414ed`). That jar is not included in the AAR, APK or source export; production uses Android's built-in `org.json`. Wider physical SAF/provider coverage remains limited.
