# Upgrading to Kinegra Amp

Kinegra Amp was previously named Kinegra ShieldAmp. Version 1.0.10 / code 86 changes the visible app name, launch/splash artwork, pairing labels, browser remote and release filenames.

Install the signed update over the existing app with `adb install -r KinegraAmp-1.0.10.apk`. Keep the original signing identity. Do not uninstall or clear app data to apply the new name.

The Android package remains `org.local.tegramilkdrop`. Existing settings and audio copies, Android Keystore aliases, plugin namespaces, Sendspin identity/snapshot storage and production feature flag retain their compatibility identifiers. The rename does not reset pairing or replace queues; a server may retain its previously customised player display name. The CLI accepts the previous entry point and key variable as compatibility aliases.

No media is bundled. Startup remains silent. The production web remote remains off until enabled. The optional bulk offline queue copier is still experimental; see [release scope](RELEASE.md).
