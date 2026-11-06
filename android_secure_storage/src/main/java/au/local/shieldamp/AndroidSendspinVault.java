package au.local.shieldamp;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.system.Os;
import android.system.ErrnoException;
import android.system.OsConstants;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Dedicated Sendspin identity snapshot; no shared token alias, file or AAD. */
final class AndroidSendspinVault {
    private static final String ALIAS="shieldamp.sendspin.snapshot.v1";
    private static final byte[] PURPOSE="shieldamp/sendspin/snapshot/v1".getBytes(StandardCharsets.US_ASCII);
    private static final int MAX=4096, MAGIC=0x53535631;
    private final File directory, record;
    AndroidSendspinVault(Context context){directory=context.getFilesDir();record=new File(directory,"sendspin-snapshot-v1.enc");}
    boolean exists()throws Exception{
        try{Os.stat(record.getAbsolutePath());return true;}
        catch(ErrnoException failure){if(failure.errno==OsConstants.ENOENT)return false;throw failure;}
    }
    private SecretKey key(boolean mayCreate)throws Exception {
        KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
        if(store.containsAlias(ALIAS)){
            java.security.Key value=store.getKey(ALIAS,null);
            if(!(value instanceof SecretKey))throw new GeneralSecurityException("Invalid snapshot key");
            return (SecretKey)value;
        }
        if(!mayCreate)throw new GeneralSecurityException("Snapshot key unavailable");
        KeyGenerator generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build());
        return generator.generateKey();
    }
    byte[] read()throws Exception {
        if(!exists())throw new FileNotFoundException();
        try(DataInputStream in=new DataInputStream(new FileInputStream(record))){
            if(in.readInt()!=MAGIC)throw new IOException("Invalid snapshot format");
            int nonceSize=in.readUnsignedByte();if(nonceSize!=12)throw new IOException("Invalid nonce");
            byte[] nonce=new byte[nonceSize];in.readFully(nonce);
            int length=in.readInt();if(length<17||length>MAX+16)throw new IOException("Invalid snapshot size");
            byte[] ciphertext=new byte[length];in.readFully(ciphertext);if(in.read()!=-1)throw new IOException("Trailing snapshot data");
            try{return decrypt(key(false),nonce,ciphertext);}finally{Arrays.fill(ciphertext,(byte)0);}
        }
    }
    private static byte[] decrypt(SecretKey key,byte[] nonce,byte[] ciphertext)throws Exception {
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key,new GCMParameterSpec(128,nonce));cipher.updateAAD(PURPOSE);return cipher.doFinal(ciphertext);
    }
    void replace(byte[] snapshot)throws Exception {
        if(snapshot==null||snapshot.length<1||snapshot.length>MAX)throw new IllegalArgumentException("Invalid snapshot size");
        SecretKey secret=key(!exists());
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,secret);cipher.updateAAD(PURPOSE);
        byte[] nonce=cipher.getIV(),ciphertext=cipher.doFinal(snapshot),verified=null;
        byte[] encoded=null;
        try{
            if(nonce==null||nonce.length!=12)throw new GeneralSecurityException("Invalid nonce");
            verified=decrypt(secret,nonce,ciphertext);
            if(!MessageDigest.isEqual(snapshot,verified))throw new GeneralSecurityException("Snapshot verification failed");
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();
            DataOutputStream data=new DataOutputStream(bytes);
            data.writeInt(MAGIC);data.writeByte(nonce.length);data.write(nonce);data.writeInt(ciphertext.length);data.write(ciphertext);data.flush();encoded=bytes.toByteArray();
            SnapshotCommit.replace(new SnapshotCommit.Operations(){
                File temporary;FileOutputStream stream;
                public void stage(byte[] value)throws Exception{temporary=File.createTempFile("sendspin-snapshot-", ".tmp", directory);stream=new FileOutputStream(temporary);stream.write(value);stream.flush();}
                public void sync()throws Exception{stream.getFD().sync();}
                public void publish()throws Exception{stream.close();stream=null;Os.rename(temporary.getAbsolutePath(),record.getAbsolutePath());temporary=null;}
                public void cleanup(){if(stream!=null)try{stream.close();}catch(IOException ignored){}if(temporary!=null)temporary.delete();}
            },encoded);
        }finally{if(encoded!=null)Arrays.fill(encoded,(byte)0);Arrays.fill(ciphertext,(byte)0);if(verified!=null)Arrays.fill(verified,(byte)0);}
    }
}
