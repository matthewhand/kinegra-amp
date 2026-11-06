# Isolated Android credential lifecycle proof

This developer fixture exercises the production credential Java implementation against real Android Keystore and app-private files using only fixed synthetic values. Its fixed application ID is `local.shieldamp.securityproof20261103`; it must never run as the production app or share its UID.

The standalone activity compiles the unchanged production `ShieldAmpTokenStore`, token migration/record/forget classes and Sendspin vault. Tiny proof-only Godot host stubs provide the Activity context; they are outside production source paths and are never included in the plugin AAR. This proves Java/platform behavior, not Godot JNI dispatch or audible playback. A fresh plugin/vault object is reopened within the same process; cold process restart remains a separate acceptance check.

## Build offline

Use an Android SDK platform jar, matching build-tools and JDK 17 already available locally:

```sh
python3 android_secure_storage/proof/security_lifecycle/build.py --build-tools /path/to/sdk/build-tools/36.1.0 --android-jar /path/to/sdk/platforms/android-36/android.jar --jdk /path/to/jdk17 --output /path/to/new-proof-output
```

The output must be new. The builder compiles Java/Dex, generates an independent development signing key and verifies the resulting APK identity, certificate, permissions, backup/debug flags, launcher absence and recents exclusion. It records source hashes and build logs. It neither installs, launches nor removes an app, and does not need the production keystore or credential.

The manifest requests no permissions, has no shared UID or MAIN/LAUNCHER/LEANBACK entry, excludes the activity from Recents and disables backup/debugging. The generic test window is protected from screenshots and finishes itself. No network, camera or media operation is performed.

## Platform checks and evidence

An authorized operator must first verify the expected device and system media mute, and confirm this exact temporary package is absent. Install only this proof package, explicitly launch `au.local.shieldamp.SecurityLifecycleProofActivity`, then read the `ShieldAmpSecurityProof` log tag. Remove only the temporary proof package after collecting the numeric result. Production app data and signing identity are outside this flow.

The activity refuses to mutate anything if its package/UID boundary is wrong or known credential files/Keystore aliases already exist. The current fixture emits 34 numbered checks covering:

- Fresh package/UID and empty credential state before any write.
- Staged synthetic legacy migration, verified matching cleanup and atomic encrypted server binding.
- No plaintext token sequence in the encrypted file; re-read through a new plugin object.
- Wrong-origin refusal without changing the saved record.
- Conflicting legacy access failing closed and preserving both records for an explicit decision.
- A synthetic Sendspin snapshot/key surviving local MA forget unchanged.
- MA key/file deletion, reuse-blocking marker and idempotent forget.
- Explicit replacement after forget, new origin binding and final MA cleanup with the SDK snapshot/key still preserved.

Success is `SECURITY_PROOF_RESULT=PASS CHECKS=34`. Failure prints only a numeric step; provider/runtime exceptions use `1000 + completed-check-count`. Tokens, ciphertext, origins, keys and exception messages are never logged. The remaining synthetic SDK record deliberately stays available for the preservation checks and disappears when the operator uninstalls this temporary package.

A successful build alone is not a platform-test pass. `proof-build.json` starts with platform execution marked pending. Record the actual device result separately; keep cold restart, production JNI and production release-manifest acceptance distinct.
