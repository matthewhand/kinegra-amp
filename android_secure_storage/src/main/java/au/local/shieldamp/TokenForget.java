package au.local.shieldamp;

/** Forget is local only: block reuse before destructive work, then attempt all cleanup. */
final class TokenForget {
    interface Store {
        void blockReuse() throws Exception;
        void destroyKey() throws Exception;
        boolean deleteLegacy() throws Exception;
        boolean deleteEncrypted() throws Exception;
    }
    static boolean forget(Store store)throws Exception {
        store.blockReuse(); // If this fails, preserve the prior state and report failure.
        boolean key=false,legacy=false,encrypted=false;
        try{store.destroyKey();key=true;}catch(Exception failure){/* Continue local cleanup. */}
        try{legacy=store.deleteLegacy();}catch(Exception failure){/* Reuse remains blocked. */}
        try{encrypted=store.deleteEncrypted();}catch(Exception failure){/* Reuse remains blocked. */}
        return key&&legacy&&encrypted;
    }
}
