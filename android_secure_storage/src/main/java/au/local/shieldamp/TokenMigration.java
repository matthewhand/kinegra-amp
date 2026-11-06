package au.local.shieldamp;

import java.security.MessageDigest;
import java.util.Arrays;

/** Transaction ordering is independent of Android for fault-injection tests. */
final class TokenMigration {
    interface Vault { boolean exists(); byte[] read() throws Exception; void write(byte[] value) throws Exception; }
    interface Legacy { boolean exists(); byte[] read() throws Exception; boolean delete() throws Exception; }
    static final class Result { final byte[] token; final String status; Result(byte[] t,String s){token=t;status=s;} }
    /** Stage and verify an existing legacy token, retaining plaintext for recovery. */
    static Result stage(Vault vault, Legacy legacy) throws Exception {
        if(vault.exists()) return new Result(vault.read(),legacy.exists()?"secure_legacy_remains":"secure");
        if(!legacy.exists()) return new Result(new byte[0],"not_configured");
        byte[] original=legacy.read();
        try {
            if(original.length==0 || original.length>8192) throw new IllegalArgumentException("invalid token size");
            vault.write(original);
            byte[] verified=vault.read();
            if(!MessageDigest.isEqual(original,verified)){Arrays.fill(verified,(byte)0);throw new IllegalStateException("readback failed");}
            return new Result(verified,"secure_legacy_remains");
        } finally { Arrays.fill(original,(byte)0); }
    }
    static final class LegacyConflictException extends Exception {}
    static Result load(Vault vault, Legacy legacy) throws Exception {
        if(vault.exists()){
            byte[] verified=vault.read();
            try{
                if(verified.length<1||verified.length>8192)throw new IllegalArgumentException("invalid token size");
                if(!legacy.exists())return new Result(verified,"secure_no_legacy");
                byte[] original=legacy.read();
                try{
                    if(!MessageDigest.isEqual(original,verified))throw new LegacyConflictException();
                    boolean removed=legacy.delete();
                    return new Result(verified,removed?"migrated_no_legacy":"secure_legacy_remains");
                }finally{Arrays.fill(original,(byte)0);}
            }catch(Exception failure){Arrays.fill(verified,(byte)0);throw failure;}
        }
        if(!legacy.exists()) return new Result(new byte[0],"not_configured");
        byte[] original=legacy.read();
        try {
            if(original.length==0 || original.length>8192) throw new IllegalArgumentException("invalid token size");
            vault.write(original);
            byte[] verified=vault.read();
            if(!MessageDigest.isEqual(original,verified)){Arrays.fill(verified,(byte)0);throw new IllegalStateException("readback failed");}
            boolean removed=legacy.delete();
            return new Result(verified,removed?"migrated_no_legacy":"secure_legacy_remains");
        } finally { Arrays.fill(original,(byte)0); }
    }
}
