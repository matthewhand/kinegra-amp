package au.local.shieldamp;

import android.app.Activity;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/** Optional Godot 3 Android singleton. No token, key or error details are logged. */
public final class ShieldAmpTokenStore extends GodotPlugin {
    private String status="not_initialized", snapshotStatus="error";
    private volatile int staleTasksPruned=0;
    public ShieldAmpTokenStore(Godot godot){super(godot);}
    @Override public String getPluginName(){return "ShieldAmpTokenStore";}
    /** Verified Godot 3.6.3 lifecycle hook; only this package's old Godot tasks. */
    @Override public void onMainResume(){
        super.onMainResume();
        Activity activity=getActivity();if(activity==null)return;
        android.content.ComponentName current=activity.getComponentName();
        if(current==null||!"com.godot.game.GodotApp".equals(current.getClassName()))return;
        int removed=0;
        try{
            android.app.ActivityManager manager=(android.app.ActivityManager)activity.getSystemService(android.content.Context.ACTIVITY_SERVICE);
            if(manager==null)return;
            final int keep=activity.getTaskId();final String own=activity.getPackageName();
            for(android.app.ActivityManager.AppTask task:manager.getAppTasks()){
                try{
                    android.app.ActivityManager.RecentTaskInfo info=task.getTaskInfo();
                    if(info==null||info.baseIntent==null||info.id==keep||info.persistentId==keep)continue;
                    android.content.ComponentName base=info.baseIntent.getComponent();
                    int id=info.id>=0?info.id:info.persistentId;
                    if(base!=null&&SelfTaskCleaner.shouldRemove(keep,id,own,base.getPackageName(),base.getClassName())){
                        task.finishAndRemoveTask();removed++;
                    }
                }catch(RuntimeException unavailable){/* Preserve unknown or inaccessible tasks. */}
            }
        }catch(RuntimeException unavailable){return;}
        if(removed>0){
            staleTasksPruned=(int)Math.min(Integer.MAX_VALUE,(long)staleTasksPruned+removed);
            android.util.Log.i("ShieldAmp","STALE_TASKS_PRUNED="+removed);
        }
    }
    private final OfflineImportController offlineImport=new OfflineImportController();
    @UsedByGodot public boolean beginOfflineImport(String directory){return offlineImport.begin(getActivity(),directory);}
    @UsedByGodot public boolean cancelOfflineImport(){return offlineImport.cancel();}
    @UsedByGodot public String offlineImportStatus(){return offlineImport.status();}
    /** App-private filesystem only; no caller path or other app storage access. */
    @UsedByGodot public String offlineUsableBytes(){
        try{
            Activity activity=getActivity();
            return activity==null ? "" : Long.toString(activity.getFilesDir().getUsableSpace());
        }catch(RuntimeException unavailable){return "";}
    }
    @Override public void onMainActivityResult(int request,int result,android.content.Intent data){
        if(!offlineImport.result(getActivity(),request,result,data))super.onMainActivityResult(request,result,data);
    }
    @UsedByGodot public int staleTaskPrunedCount(){return staleTasksPruned;}
    @UsedByGodot public synchronized String loadToken(){return loadCredential(null,false);}
    /** Compatibility probe only; the library uses endpoint-bound verified migration. */
    @UsedByGodot public synchronized String loadTokenStaged(){return loadCredential(null,true);}
    @UsedByGodot public synchronized String loadTokenForEndpoint(String endpoint){return loadCredential(endpoint,false);}
    private String loadCredential(String endpoint,boolean staged){
        Activity activity=getActivity();if(activity==null){status="unavailable";return "";}
        byte[] checked=null;
        try{
            AndroidTokenVault store=new AndroidTokenVault(activity.getApplicationContext());
            if(store.isForgotten()){status="not_configured";return "";}
            String requested=endpoint==null?null:TokenCredentialRecord.endpoint(endpoint);
            String bound=store.exists()?store.endpoint():"";
            if(requested!=null&&!bound.isEmpty()&&!bound.equals(requested)){status="endpoint_mismatch";return "";}
            TokenMigration.Result result=staged?TokenMigration.stage(store.vault(),store.legacy()):TokenMigration.load(store.vault(),store.legacy());
            try{
                status=result.status;
                if(!staged&&"secure_legacy_remains".equals(status))return "";
                if(requested!=null&&bound.isEmpty()&&result.token.length>0){
                    store.writeForEndpoint(result.token,requested);checked=store.read();
                    if(!MessageDigest.isEqual(result.token,checked)||!requested.equals(store.endpoint()))throw new IllegalStateException("Binding readback failed");
                }
                return new String(result.token,StandardCharsets.UTF_8);
            }finally{Arrays.fill(result.token,(byte)0);}
        }catch(TokenMigration.LegacyConflictException conflict){status="legacy_conflict";return "";}
        catch(Exception failure){status="secure_storage_error";return "";}
        finally{if(checked!=null)Arrays.fill(checked,(byte)0);}
    }
    @UsedByGodot public synchronized String tokenEndpoint(){
        Activity activity=getActivity();if(activity==null){status="unavailable";return "";}
        try{
            AndroidTokenVault store=new AndroidTokenVault(activity.getApplicationContext());
            if(store.isForgotten()){status="not_configured";return "";}
            if(!store.exists()){status=store.legacy().exists()?"legacy_pending":"not_configured";return "";}
            return store.endpoint();
        }catch(Exception failure){status="secure_storage_error";return "";}
    }
    @UsedByGodot public synchronized boolean storeToken(String token){return storeCredential(token,null);}
    @UsedByGodot public synchronized boolean storeTokenForEndpoint(String token,String endpoint){return storeCredential(token,endpoint);}
    private boolean storeCredential(String token,String endpoint){
        Activity activity=getActivity();if(activity==null||token==null){status="unavailable";return false;}
        byte[] input=token.getBytes(StandardCharsets.UTF_8),checked=null;
        try{
            AndroidTokenVault vault=new AndroidTokenVault(activity.getApplicationContext());
            String requested=endpoint==null?(vault.exists()&&!vault.isForgotten()?vault.endpoint():""):TokenCredentialRecord.endpoint(endpoint);
            if(vault.isForgotten()&&!vault.forget()){status="forget_failed";return false;}
            vault.writeForEndpoint(input,requested);checked=vault.read();
            if(!MessageDigest.isEqual(input,checked)||!requested.equals(vault.endpoint()))throw new IllegalStateException("Readback failed");
            if(!vault.deleteLegacy()){status="secure_legacy_remains";return false;}
            if(!vault.clearForgotten()){status="forget_failed";return false;}
            status="secure_no_legacy";return true;
        }catch(Exception failure){status="secure_storage_error";return false;}
        finally{Arrays.fill(input,(byte)0);if(checked!=null)Arrays.fill(checked,(byte)0);}
    }
    /** Local MA access only. Does not revoke a server token or touch Sendspin pairing. */
    @UsedByGodot public synchronized boolean forgetToken(){
        Activity activity=getActivity();if(activity==null){status="unavailable";return false;}
        try{
            boolean removed=new AndroidTokenVault(activity.getApplicationContext()).forget();
            status=removed?"forgotten":"forget_failed";return removed;
        }catch(Exception failure){status="forget_failed";return false;}
    }
    @UsedByGodot public boolean hasUsbWebcam(){
        Activity activity=getActivity(); if(activity==null)return false;
        try{
            android.hardware.usb.UsbManager manager=(android.hardware.usb.UsbManager)activity.getSystemService(android.content.Context.USB_SERVICE);
            if(manager==null)return false;
            for(android.hardware.usb.UsbDevice device:manager.getDeviceList().values()){
                if(device.getDeviceClass()==android.hardware.usb.UsbConstants.USB_CLASS_VIDEO)return true;
                for(int i=0;i<device.getInterfaceCount();i++)
                    if(device.getInterface(i).getInterfaceClass()==android.hardware.usb.UsbConstants.USB_CLASS_VIDEO)return true;
            }
        }catch(RuntimeException unavailable){return false;}
        return false;
    }
    /** Decimal CPU milliseconds; String avoids unsupported Godot 3 JNI long returns. */
    @UsedByGodot public String processCpuTimeMs(){
        return Long.toString(android.os.Process.getElapsedCpuTime());
    }
    /** Platform thermal status, or -1 when this API/service is unavailable. */
    @UsedByGodot public int thermalStatus(){
        if(android.os.Build.VERSION.SDK_INT<29)return -1;
        Activity activity=getActivity();if(activity==null)return -1;
        try{
            android.os.PowerManager manager=(android.os.PowerManager)activity.getSystemService(android.content.Context.POWER_SERVICE);
            return manager==null?-1:manager.getCurrentThermalStatus();
        }catch(RuntimeException unavailable){return -1;}
    }
    @UsedByGodot public synchronized String storageStatus(){return status;}
    @UsedByGodot public synchronized byte[] loadSendspinSnapshot(){
        Activity activity=getActivity();if(activity==null){snapshotStatus="error";return new byte[0];}
        try{
            AndroidSendspinVault vault=new AndroidSendspinVault(activity.getApplicationContext());
            if(!vault.exists()){snapshotStatus="missing";return new byte[0];}
            byte[] value=vault.read();snapshotStatus="secure";return value;
        }catch(Exception failure){snapshotStatus="error";return new byte[0];}
    }
    @UsedByGodot public synchronized boolean replaceSendspinSnapshot(byte[] value){
        Activity activity=getActivity();if(activity==null){snapshotStatus="error";return false;}
        try{new AndroidSendspinVault(activity.getApplicationContext()).replace(value);snapshotStatus="secure";return true;}
        catch(Exception failure){snapshotStatus="error";return false;}
    }
    /** Canonical bounded text bridge for Godot 3 Android JNI. */
    @UsedByGodot public synchronized String loadSendspinSnapshotBase64(){
        byte[] value=loadSendspinSnapshot();
        try{return android.util.Base64.encodeToString(value,android.util.Base64.NO_WRAP);}
        finally{Arrays.fill(value,(byte)0);}
    }
    @UsedByGodot public synchronized boolean replaceSendspinSnapshotBase64(String text){
        byte[] value=null;
        try{
            if(text==null||text.length()<4||text.length()>5464)throw new IllegalArgumentException();
            value=android.util.Base64.decode(text,android.util.Base64.NO_WRAP);
            if(value.length<1||value.length>4096||!android.util.Base64.encodeToString(value,android.util.Base64.NO_WRAP).equals(text))throw new IllegalArgumentException();
            return replaceSendspinSnapshot(value);
        }catch(Exception failure){snapshotStatus="error";return false;}
        finally{if(value!=null)Arrays.fill(value,(byte)0);}
    }
    @UsedByGodot public synchronized String sendspinSnapshotStatus(){return snapshotStatus;}
}
