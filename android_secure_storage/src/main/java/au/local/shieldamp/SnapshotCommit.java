package au.local.shieldamp;

/** A staged write is synced before the atomic publish operation. */
final class SnapshotCommit {
    interface Operations {
        void stage(byte[] encrypted) throws Exception;
        void sync() throws Exception;
        void publish() throws Exception;
        void cleanup();
    }
    static void replace(Operations operations, byte[] encrypted) throws Exception {
        try { operations.stage(encrypted); operations.sync(); operations.publish(); }
        finally { operations.cleanup(); }
    }
}
