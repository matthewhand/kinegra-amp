package au.local.shieldamp;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.WindowManager;
import android.widget.TextView;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;

/** Fixed synthetic inputs, fresh isolated UID only, no network or media access. */
public final class SecurityLifecycleProofActivity extends Activity {
    private static final String TARGET="local.shieldamp.securityproof20261103";
    private static final String TAG="ShieldAmpSecurityProof";
    private static final String MA_KEY="shieldamp.ma.token.v1", SDK_KEY="shieldamp.sendspin.snapshot.v1";
    private static final String FIRST="https://first.invalid", SECOND="https://second.invalid";
    private static final String TOKEN="synthetic-platform-access-20261103", REPLACEMENT="synthetic-replacement-20261103";
    private int checks;
    private static final class FailedCheck extends Exception {final int code;FailedCheck(int code){this.code=code;}}
    private void check(boolean ok)throws Exception {
        checks++;
        if(!ok)throw new FailedCheck(checks);
        Log.i(TAG,"PASS_"+checks);
    }
    private static void write(File path,byte[] value)throws Exception {
        try(FileOutputStream out=new FileOutputStream(path)){out.write(value);out.getFD().sync();}
    }
    private static byte[] read(File path)throws Exception {
        try(FileInputStream in=new FileInputStream(path);ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] block=new byte[1024];int count;
            while((count=in.read(block))!=-1)out.write(block,0,count);
            return out.toByteArray();
        }
    }
    private static boolean contains(byte[] bytes,byte[] needle){
        for(int i=0;i<=bytes.length-needle.length;i++){
            boolean match=true;
            for(int n=0;n<needle.length;n++)if(bytes[i+n]!=needle[n]){match=false;break;}
            if(match)return true;
        }
        return false;
    }
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        TextView label=new TextView(this);label.setText("Running isolated synthetic credential checks");setContentView(label);
        new Thread(new Runnable(){public void run(){runProof();}},"SyntheticSecurityProof").start();
    }
    private void runProof(){
        boolean pass=false;
        try{
            check(TARGET.equals(getPackageName()));
            check(getApplicationInfo().uid==android.os.Process.myUid());
            check(getPackageManager().getPackageInfo(TARGET,0).sharedUserId==null);
            KeyStore keys=KeyStore.getInstance("AndroidKeyStore");keys.load(null);
            check(!keys.containsAlias(MA_KEY)&&!keys.containsAlias(SDK_KEY));
            File dir=getFilesDir();
            for(String name:new String[]{"music_assistant_token","ma-token-v1.enc","ma-token-v1.enc.bak","ma-token-v1.enc.new","ma-token-forgotten.flag","ma-token-forgotten.flag.bak","ma-token-forgotten.flag.new","sendspin-snapshot-v1.enc"})
                check(!new File(dir,name).exists());
            org.godotengine.godot.Godot host=new org.godotengine.godot.Godot(this);
            ShieldAmpTokenStore plugin=new ShieldAmpTokenStore(host);
            File legacy=new File(dir,"music_assistant_token"),encrypted=new File(dir,"ma-token-v1.enc");
            write(legacy,TOKEN.getBytes(StandardCharsets.UTF_8));
            check(TOKEN.equals(plugin.loadTokenStaged())&&"secure_legacy_remains".equals(plugin.storageStatus())&&legacy.isFile());
            keys.load(null);check(keys.containsAlias(MA_KEY));
            check(TOKEN.equals(plugin.loadTokenForEndpoint(FIRST))&&"migrated_no_legacy".equals(plugin.storageStatus()));
            check(!legacy.exists()&&encrypted.isFile()&&FIRST.equals(plugin.tokenEndpoint()));
            byte[] encryptedBefore=read(encrypted);
            check(!contains(encryptedBefore,TOKEN.getBytes(StandardCharsets.UTF_8)));
            ShieldAmpTokenStore reopened=new ShieldAmpTokenStore(host);
            check(reopened.loadTokenForEndpoint(SECOND).isEmpty()&&"endpoint_mismatch".equals(reopened.storageStatus()));
            check(Arrays.equals(encryptedBefore,read(encrypted))&&!legacy.exists());
            check(TOKEN.equals(reopened.loadTokenForEndpoint(FIRST))&&"secure_no_legacy".equals(reopened.storageStatus()));
            AndroidSendspinVault sdk=new AndroidSendspinVault(this);
            byte[] snapshot={83,83,86,49,1,2,3,4,5,6};sdk.replace(snapshot);
            byte[] sdkEncrypted=read(new File(dir,"sendspin-snapshot-v1.enc"));
            keys.load(null);check(keys.containsAlias(SDK_KEY)&&Arrays.equals(snapshot,sdk.read()));
            write(legacy,"different-synthetic-access".getBytes(StandardCharsets.UTF_8));
            check(reopened.loadTokenForEndpoint(FIRST).isEmpty()&&"legacy_conflict".equals(reopened.storageStatus()));
            check(legacy.exists()&&Arrays.equals(encryptedBefore,read(encrypted)));
            check(reopened.forgetToken()&&"forgotten".equals(reopened.storageStatus()));
            AndroidTokenVault token=new AndroidTokenVault(this);
            keys.load(null);check(!keys.containsAlias(MA_KEY)&&!token.exists()&&!legacy.exists()&&token.isForgotten());
            check(reopened.loadTokenForEndpoint(FIRST).isEmpty()&&"not_configured".equals(reopened.storageStatus()));
            check(keys.containsAlias(SDK_KEY)&&Arrays.equals(snapshot,sdk.read())&&Arrays.equals(sdkEncrypted,read(new File(dir,"sendspin-snapshot-v1.enc"))));
            check(reopened.forgetToken()&&"forgotten".equals(reopened.storageStatus()));
            keys.load(null);check(!keys.containsAlias(MA_KEY)&&keys.containsAlias(SDK_KEY)&&Arrays.equals(snapshot,sdk.read()));
            check(reopened.storeTokenForEndpoint(REPLACEMENT,SECOND)&&"secure_no_legacy".equals(reopened.storageStatus()));
            check(!token.isForgotten()&&SECOND.equals(reopened.tokenEndpoint())&&REPLACEMENT.equals(reopened.loadTokenForEndpoint(SECOND)));
            check(reopened.loadTokenForEndpoint(FIRST).isEmpty()&&"endpoint_mismatch".equals(reopened.storageStatus()));
            check(reopened.forgetToken());
            keys.load(null);check(!keys.containsAlias(MA_KEY)&&keys.containsAlias(SDK_KEY)&&Arrays.equals(snapshot,sdk.read())&&Arrays.equals(sdkEncrypted,read(new File(dir,"sendspin-snapshot-v1.enc"))));
            Arrays.fill(encryptedBefore,(byte)0);Arrays.fill(sdkEncrypted,(byte)0);Arrays.fill(snapshot,(byte)0);
            pass=true;
        }catch(Throwable failure){Log.i(TAG,"FAIL_"+(failure instanceof FailedCheck?((FailedCheck)failure).code:1000+checks));}
        Log.i(TAG,"SECURITY_PROOF_RESULT="+(pass?"PASS":"FAIL")+" CHECKS="+checks);
        final boolean ok=pass;
        runOnUiThread(new Runnable(){public void run(){setResult(ok?RESULT_OK:RESULT_CANCELED);finish();}});
    }
}
