# Install or update Kinegra Amp

[Download the signed 1.0.19 beta APK](https://github.com/matthewhand/kinegra-amp/releases/download/v1.0.19/KinegraAmp-1.0.19.apk) for Android 8.0+ on ARM64. The [release page](https://github.com/matthewhand/kinegra-amp/releases/tag/v1.0.19) includes the SHA-256 checksum.

## Install on the SHIELD

**From the TV** — Copy the APK to USB or internal storage, open it on the SHIELD with a file manager or sideloading app that can install APKs, and follow Android’s install prompt. Android may ask you to allow installs from that app.

**From a computer with ADB** — Install [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools), enable debugging on the SHIELD, and connect and authorize the computer. For network debugging, use the address and port shown by your device or configured in your SHIELD’s debugging settings. For a USB connection, skip `adb connect`. [ADB connection guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi)

```sh
adb connect DEVICE_IP:ADB_PORT
adb devices
adb -s DEVICE_SERIAL install -r KinegraAmp-1.0.19.apk
```

Use the SHIELD’s entry from `adb devices` for `DEVICE_SERIAL`. Open **Kinegra Amp** from the SHIELD’s apps list after installation.

## Keep your library and settings when updating

Install over your existing Amp with the same signing identity and leave its app data intact to retain imported music, settings and pairing. If Android reports a signing conflict, keep the existing installation and use an APK signed with the same key.

The package ID is `org.local.tegramilkdrop`. For self-built APKs, see [Build from source](BUILDING.md).
