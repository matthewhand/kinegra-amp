package au.local.shieldamp;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.KeyStore;
import java.security.GeneralSecurityException;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** AES-GCM key stays in AndroidKeyStore; encrypted record stays app-private. */
final class AndroidTokenVault implements TokenMigration.Vault {
    private static final String ALIAS="shieldamp.ma.token.v1";
    private static final int MAX=TokenCredentialRecord.MAX_RECORD;
    private final AtomicFile encrypted;
    private final File legacy;
    private final AtomicFile forgotten;
    AndroidTokenVault(Context context) {
        File dir=context.getFilesDir();
        encrypted=new AtomicFile(new File(dir,"ma-token-v1.enc"));
        legacy=new File(dir,"music_assistant_token");
        forgotten=new AtomicFile(new File(dir,"ma-token-forgotten.flag"));
    }
    TokenMigration.Vault vault(){return this;}
    TokenMigration.Legacy legacy(){
        return new TokenMigration.Legacy(){
            public boolean exists(){return legacy.isFile();}
            public byte[] read()throws Exception{return readLegacy();}
            public boolean delete(){return deleteLegacy();}
        };
    }
    public boolean exists(){return encrypted.getBaseFile().exists()||new File(encrypted.getBaseFile().getPath()+".bak").exists();}
    private SecretKey key(boolean mayCreate)throws Exception {
        KeyStore store=KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if(store.containsAlias(ALIAS)){
            java.security.Key existing=store.getKey(ALIAS,null);
            if(!(existing instanceof SecretKey))throw new GeneralSecurityException("Invalid key");
            return (SecretKey)existing;
        }
        if(!mayCreate)throw new GeneralSecurityException("Encrypted token key unavailable");
        KeyGenerator generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).build());
        return generator.generateKey();
    }
    private byte[] readEncrypted()throws Exception {
        requireNoLinks(encrypted);
        if(!exists())throw new FileNotFoundException();
        try(DataInputStream in=new DataInputStream(encrypted.openRead())){
            if(in.readInt()!=0x53415431)throw new IOException("Invalid encrypted record");
            int nonceSize=in.readUnsignedByte(); if(nonceSize!=12)throw new IOException("Invalid nonce");
            byte[] nonce=new byte[nonceSize];in.readFully(nonce);
            int length=in.readInt(); if(length<17||length>MAX+16)throw new IOException("Invalid ciphertext");
            byte[] ciphertext=new byte[length]; in.readFully(ciphertext); if(in.read()!=-1)throw new IOException("Trailing data");
            Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE,key(false),new GCMParameterSpec(128,nonce));
            try{return cipher.doFinal(ciphertext);}finally{Arrays.fill(ciphertext,(byte)0);}
        }
    }
    public byte[] read()throws Exception {
        byte[] value=readEncrypted();
        try{return TokenCredentialRecord.decode(value).token;}finally{Arrays.fill(value,(byte)0);}
    }
    String endpoint()throws Exception {
        byte[] value=readEncrypted();
        try{TokenCredentialRecord.Record record=TokenCredentialRecord.decode(value);try{return record.endpoint;}finally{Arrays.fill(record.token,(byte)0);}}
        finally{Arrays.fill(value,(byte)0);}
    }
    public void write(byte[] token)throws Exception {writeForEndpoint(token,exists()?endpoint():"");}
    void writeForEndpoint(byte[] token,String endpoint)throws Exception {
        byte[] value=TokenCredentialRecord.encode(endpoint,token);
        try{writeEncrypted(value);}finally{Arrays.fill(value,(byte)0);}
    }
    private void writeEncrypted(byte[] token)throws Exception {
        requireNoLinks(encrypted);
        if(token==null||token.length<1||token.length>MAX)throw new IllegalArgumentException("Invalid token size");
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE,key(!exists()));
        byte[] nonce=cipher.getIV(), ciphertext=cipher.doFinal(token); if(nonce==null||nonce.length!=12)throw new GeneralSecurityException("Invalid nonce");
        FileOutputStream raw=null;
        try{raw=encrypted.startWrite(); DataOutputStream out=new DataOutputStream(raw);out.writeInt(0x53415431);out.writeByte(nonce.length);out.write(nonce);out.writeInt(ciphertext.length);out.write(ciphertext);out.flush();encrypted.finishWrite(raw);}
        catch(Exception failure){if(raw!=null)encrypted.failWrite(raw);throw failure;}
        finally{Arrays.fill(ciphertext,(byte)0);}
    }
    boolean isForgotten(){return anyRecord(forgotten);}
    private static boolean anyRecord(AtomicFile file){
        String path=file.getBaseFile().getPath();
        for(String suffix:new String[]{"",".bak",".new"}){
            File target=new File(path+suffix);
            if(target.exists()||Files.isSymbolicLink(target.toPath()))return true;
        }
        return false;
    }
    private static void requireNoLinks(AtomicFile file)throws IOException {
        String path=file.getBaseFile().getPath();
        for(String suffix:new String[]{"",".bak",".new"})
            if(Files.isSymbolicLink(new File(path+suffix).toPath()))throw new IOException("Unexpected record link");
    }
    private static boolean removeRecord(AtomicFile file){
        String path=file.getBaseFile().getPath();
        try{requireNoLinks(file);}catch(IOException failure){return false;}
        file.delete();new File(path+".new").delete();
        return !anyRecord(file);
    }
    boolean clearForgotten(){return removeRecord(forgotten);}
    boolean deleteLegacy(){
        if(Files.isSymbolicLink(legacy.toPath()))return false;
        if(!legacy.exists())return true;
        // Best effort only: flash/journaling may retain old physical blocks.
        try(RandomAccessFile file=new RandomAccessFile(legacy,"rw")){
            byte[] zeros=new byte[1024];long left=Math.min(file.length(),8192);
            while(left>0){int count=(int)Math.min(left,zeros.length);file.write(zeros,0,count);left-=count;}
            file.getFD().sync();
        }catch(IOException failure){/* Still try logical deletion. */}
        return !legacy.exists()||legacy.delete();
    }
    boolean forget()throws Exception {
        return TokenForget.forget(new TokenForget.Store(){
            public void blockReuse()throws Exception {
                requireNoLinks(forgotten);
                FileOutputStream raw=null;
                try{raw=forgotten.startWrite();raw.write(1);forgotten.finishWrite(raw);}
                catch(Exception failure){if(raw!=null)forgotten.failWrite(raw);throw failure;}
            }
            public void destroyKey()throws Exception {
                KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);store.deleteEntry(ALIAS);
                if(store.containsAlias(ALIAS))throw new GeneralSecurityException("Token key remains");
            }
            public boolean deleteLegacy(){return AndroidTokenVault.this.deleteLegacy();}
            public boolean deleteEncrypted(){return removeRecord(encrypted);}
        });
    }
    private byte[] readLegacy()throws Exception {
        if(Files.isSymbolicLink(legacy.toPath()))throw new IOException("Unexpected legacy link");
        try(InputStream in=new FileInputStream(legacy); ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] chunk=new byte[1024];int n,total=0;while((n=in.read(chunk))!=-1){total+=n;if(total>MAX)throw new IOException("Legacy token too large");out.write(chunk,0,n);}Arrays.fill(chunk,(byte)0);
            // Match the existing Godot provisioner, which trims surrounding whitespace.
            return new String(out.toByteArray(),StandardCharsets.UTF_8).trim().getBytes(StandardCharsets.UTF_8);
        }
    }
}
