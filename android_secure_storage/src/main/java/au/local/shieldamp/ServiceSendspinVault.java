package au.local.shieldamp;

import android.content.Context;

/** Native playback worker access to the existing encrypted identity snapshot. */
final class ServiceSendspinVault {
    private final AndroidSendspinVault vault;

    ServiceSendspinVault(Context context) {
        vault = new AndroidSendspinVault(context.getApplicationContext());
    }

    /** Empty means missing. Null means unavailable, corrupt, or unreadable. */
    byte[] load() {
        try {
            return vault.exists() ? vault.read() : new byte[0];
        } catch (Exception failure) {
            return null;
        }
    }

    boolean replace(byte[] snapshot) {
        try {
            vault.replace(snapshot);
            return true;
        } catch (Exception failure) {
            return false;
        }
    }
}
