# Library access and privacy

Library access is separate from Sendspin playback pairing. Typed access is kept in memory unless **Remember access securely on this device** is explicitly selected and authentication succeeds. Closing the library keeps an authorized playback session available; disconnecting, forgetting access, changing the server or losing authorization ends that credential session.

Saved access is encrypted by Android Keystore and bound to its normalized server origin. Migration verifies the replacement before deleting the matching legacy plaintext file. Conflicting or failed migrations fail closed. **Forget saved access** removes local library access without deleting playback pairing, preferences, music or server queues. Revoke the token in Music Assistant to revoke it on the server.

Trusted private HTTP still sends credentials over an unencrypted connection. Device administrators can inspect live process memory; encrypted storage cannot protect against a fully controlled device. The release pipeline checks that backups and debugging are disabled.

An isolated Android proof on the target Shield passed 34 checks using synthetic credentials: encrypted origin-bound storage, verified legacy cleanup, wrong-origin rejection, conflict handling, local forget, idempotence and preservation of a separate pairing record. Its temporary package was removed afterward. It exercised the production Java storage code with proof-only host stubs; it does not replace Godot JNI or production-upgrade checks. See [implementation and host tests](../android_secure_storage/README.md) and [portable platform proof](../android_secure_storage/proof/security_lifecycle/README.md).
