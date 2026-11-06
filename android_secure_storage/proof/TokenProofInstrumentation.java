package au.local.shieldamp;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;

/** Only the separately installed synthetic proof package may run these tests. */
public final class TokenProofInstrumentation extends Instrumentation {
    private static final String TARGET="local.shieldamp.tokenproof";
    private static final String[] KEYS={"shieldamp.ma.token.v1","shieldamp.sendspin.snapshot.v1"};
    private static final String[] FILES={"music_assistant_token","ma-token-v1.enc","ma-token-v1.enc.bak","sendspin-snapshot-v1.enc","ma-token-v1.enc.new"};
    private int checks;
    private void check(boolean ok)throws Exception{checks++;if(!ok)throw new Exception("check_"+checks);}
    private static void write(File file,byte[] data)throws Exception{try(FileOutputStream out=new FileOutputStream(file)){out.write(data);out.getFD().sync();}}
    private static byte[] read(File file)throws Exception{try(FileInputStream in=new FileInputStream(file);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[1024];int n;while((n=in.read(b))!=-1)out.write(b,0,n);return out.toByteArray();}}
    @Override public void onCreate(Bundle arguments){super.onCreate(arguments);start();}
    @Override public void onStart(){
        Bundle result=new Bundle();boolean owned=false;int code=Activity.RESULT_CANCELED;KeyStore keys=null;Context target=getTargetContext();File dir=target.getFilesDir();
        try{
            if(!TARGET.equals(target.getPackageName()))throw new Exception("wrong_target");
            ApplicationInfo info=target.getPackageManager().getApplicationInfo(TARGET,PackageManager.GET_META_DATA);
            check(info.metaData!=null&&"au.local.shieldamp.ShieldAmpTokenStore".equals(info.metaData.getString("org.godotengine.plugin.v1.ShieldAmpTokenStore")));
            keys=KeyStore.getInstance("AndroidKeyStore");keys.load(null);
            for(String key:KEYS)if(keys.containsAlias(key))throw new Exception("fixture_key_exists");
            for(String name:FILES)if(new File(dir,name).exists())throw new Exception("fixture_file_exists");
            File[] existing=dir.listFiles();if(existing==null)throw new Exception("fixture_directory_unreadable");
            for(File item:existing)if(item.getName().startsWith("sendspin-snapshot-")&&item.getName().endsWith(".tmp"))throw new Exception("fixture_temp_exists");
            owned=true;
            File legacy=new File(dir,FILES[0]);write(legacy,new byte[8193]);
            AndroidTokenVault token=new AndroidTokenVault(target);
            try{TokenMigration.load(token.vault(),token.legacy());throw new Exception("oversize_accepted");}catch(IllegalArgumentException|IOException expected){}
            check(legacy.exists()&&!token.exists());
            byte[] input="synthetic-fixture-token".getBytes(StandardCharsets.UTF_8);write(legacy,input);
            TokenMigration.Result migrated=TokenMigration.load(token.vault(),token.legacy());
            check("migrated".equals(migrated.status)&&Arrays.equals(input,migrated.token)&&!legacy.exists());
            byte[] before=read(new File(dir,FILES[1]));
            try{token.write(new byte[8193]);throw new Exception("oversize_accepted");}catch(IllegalArgumentException expected){}
            check(Arrays.equals(before,read(new File(dir,FILES[1]))));
            AndroidSendspinVault snapshot=new AndroidSendspinVault(target);check(!snapshot.exists());
            byte[] sample={83,83,86,49,0,1,2,3};snapshot.replace(sample);check(Arrays.equals(sample,snapshot.read()));
            File snapshotFile=new File(dir,FILES[3]);byte[] encrypted=read(snapshotFile);
            try{snapshot.replace(new byte[4097]);throw new Exception("oversize_accepted");}catch(IllegalArgumentException expected){}
            check(Arrays.equals(encrypted,read(snapshotFile))&&Arrays.equals(sample,snapshot.read()));
            byte[] corrupt=encrypted.clone();corrupt[corrupt.length-1]^=1;write(snapshotFile,corrupt);
            try{snapshot.read();throw new Exception("corruption_accepted");}catch(java.security.GeneralSecurityException expected){}
            check(snapshot.exists());write(snapshotFile,encrypted);check(Arrays.equals(sample,snapshot.read()));
            result.putString("result","PASS: "+checks+" synthetic checks; manifest metadata only");
            code=Activity.RESULT_OK;
        }catch(Exception failure){result.putString("result","FAIL: "+failure.getClass().getSimpleName());}
        finally{if(owned){
            boolean clean=true;
            for(String name:FILES){File f=new File(dir,name);if(f.exists()&&!f.delete())clean=false;}
            if(keys!=null)for(String key:KEYS)try{keys.deleteEntry(key);if(keys.containsAlias(key))clean=false;}catch(Exception failure){clean=false;}
            if(!clean){code=Activity.RESULT_CANCELED;result.putString("result","FAIL: synthetic cleanup incomplete");}
        }}
        finish(code,result);
    }
}
