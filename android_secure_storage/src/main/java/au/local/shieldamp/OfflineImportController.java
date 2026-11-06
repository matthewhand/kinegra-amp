package au.local.shieldamp;

import android.app.Activity;
import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.CancellationSignal;
import android.provider.OpenableColumns;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.json.JSONObject;

/** User-initiated SAF copies. No broad storage/network permission or retained URI grants. */
final class OfflineImportController {
    private static final int MAX_SELECTION=32;
    private static final long FILE_TIMEOUT_MS=60000, PICKER_TIMEOUT_MS=300000;
    private final OfflineImportSession session=new OfflineImportSession();
    // One watchdog/canceller and at most one copy worker; a blocked provider
    // cannot cause new workers to accumulate after cancellation.
    private final ScheduledThreadPoolExecutor watchdog=new ScheduledThreadPoolExecutor(1,r->{Thread t=new Thread(r,"ShieldAmp-import-watchdog");t.setDaemon(true);return t;});
    private ScheduledFuture<?> pickerTimer;
    private OfflineImportSession.Job pickerJob;
    OfflineImportController(){watchdog.setRemoveOnCancelPolicy(true);}
    private synchronized void cancelPickerTimer(OfflineImportSession.Job job){if(pickerJob==job&&pickerTimer!=null){pickerTimer.cancel(false);pickerTimer=null;pickerJob=null;}}
    private File directory;
    synchronized boolean begin(Activity activity,String requested){
        if(activity==null||session.busy())return false;
        final File target;
        try{target=OfflineFileImporter.destination(activity.getFilesDir(),requested);}
        catch(IOException invalid){session.invalidDestination();return false;}
        final OfflineImportSession.Job job=session.begin();if(job==null)return false;
        directory=target;
        pickerJob=job;pickerTimer=watchdog.schedule(()->{synchronized(session){if(session.choosing(job))session.cancel("timed_out");}},PICKER_TIMEOUT_MS,TimeUnit.MILLISECONDS);
        activity.runOnUiThread(()->{
            if(!session.choosing(job))return;
            try{
                Intent picker=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("audio/*");
                picker.putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true);
                picker.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                if(picker.resolveActivity(activity.getPackageManager())==null){session.choosingFailed(job,"picker_unavailable");cancelPickerTimer(job);return;}
                activity.startActivityForResult(picker,job.request);
            }catch(RuntimeException unavailable){session.choosingFailed(job,"error");cancelPickerTimer(job);}
        });
        return true;
    }
    boolean cancel(){
        OfflineImportSession.Job job;
        synchronized(session){if(!session.cancel("cancelled"))return false;job=session.current();}
        cancelPickerTimer(job);
        watchdog.execute(job::closeActive);
        return true;
    }
    boolean result(Activity activity,int request,int result,Intent data){
        if(!session.ownsRequest(request))return false;
        final OfflineImportSession.Job job=session.requested(request);if(job==null)return true;
        cancelPickerTimer(job);
        if(result!=Activity.RESULT_OK||data==null){session.choosingFailed(job,"cancelled");return true;}
        final ArrayList<Uri> documents=new ArrayList<>();ClipData clips=data.getClipData();
        if(clips!=null){if(clips.getItemCount()>MAX_SELECTION)session.error(job);for(int i=0;i<Math.min(MAX_SELECTION,clips.getItemCount());i++){Uri u=clips.getItemAt(i).getUri();if(u!=null&&!documents.contains(u))documents.add(u);}}
        else if(data.getData()!=null)documents.add(data.getData());
        if(activity==null||documents.isEmpty()){session.choosingFailed(job,"cancelled");return true;}
        final ContentResolver resolver=activity.getApplicationContext().getContentResolver();final File target=directory;
        if(!session.startWorker(job))return true;
        Thread worker=new Thread(()->{
            try{
                for(Uri uri:documents){
                    if(job.cancelled)break;
                    if(!"content".equals(uri.getScheme())){session.error(job);continue;}
                    final long fileEpoch=job.deadline(FILE_TIMEOUT_MS);
                    final ScheduledFuture<?> timer=watchdog.schedule(()->{if(job.timeout(fileEpoch))job.closeActive();},FILE_TIMEOUT_MS,TimeUnit.MILLISECONDS);
                    OfflineFileImporter.Result copied=null;
                    try{
                        job.check();String name="Imported audio";CancellationSignal signal=new CancellationSignal();job.query(signal::cancel);job.check();
                        try(Cursor c=resolver.query(uri,new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE},null,null,null,signal)){
                            job.check();
                            if(c!=null&&c.moveToFirst()){
                                int ix=c.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(ix>=0&&!c.isNull(ix)){name=c.getString(ix);if(name!=null&&name.length()>512)name=name.substring(0,512);}
                                int length=c.getColumnIndex(OpenableColumns.SIZE);if(length>=0&&!c.isNull(length)&&c.getLong(length)>OfflineFileImporter.MAX_BYTES)throw new IOException("File too large");
                            }
                        }finally{job.clearQuery();}
                        job.check();
                        try(InputStream in=resolver.openInputStream(uri)){
                            if(in==null)throw new IOException("Document unavailable");
                            try{job.attach(in);copied=OfflineFileImporter.copy(in,name,target,target.getUsableSpace(),job,hash->OfflineLibraryAdmission.admit(target,hash,OfflineCatalogJson::read));}
                            finally{job.detach(in);}
                        }
                        // Commit metadata and completion as one cancellation boundary.
                        synchronized(session){synchronized(job){
                            job.check();OfflineLibraryAdmission.admit(target,copied.hash,OfflineCatalogJson::read);writeMetadata(target,copied);session.counted(job,copied.duplicate);copied=null;
                        }}
                    }catch(Exception failure){
                        if(!job.cancelled)session.error(job);
                    }finally{
                        timer.cancel(false);job.endFile(fileEpoch);job.clearQuery();
                        if(copied!=null&&!copied.duplicate)copied.file.delete();
                    }
                }
            }finally{session.finished(job);}
        },"ShieldAmp-offline-import");
        try{worker.setPriority(Thread.MIN_PRIORITY);worker.start();}
        catch(RuntimeException unavailable){session.error(job);session.finished(job);}
        return true;
    }
    private void writeMetadata(File target,OfflineFileImporter.Result copy)throws Exception {
        File metadata=OfflineFileImporter.child(target,copy.file.getName()+".meta.json");
        OfflineFileImporter.child(target,metadata.getName()+".new");OfflineFileImporter.child(target,metadata.getName()+".bak");
        if(metadata.exists()){
            if(metadata.length()>2048)throw new IOException("Invalid library metadata");
            byte[] bytes=new byte[(int)metadata.length()];
            try(DataInputStream in=new DataInputStream(new FileInputStream(metadata))){in.readFully(bytes);}
            JSONObject old=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
            if(old.getInt("version")!=1||!old.getString("file").equals(copy.file.getName())||!old.getString("sha256").equals(copy.hash)||old.getLong("bytes")!=copy.bytes)throw new IOException("Invalid library metadata");
            return;
        }
        JSONObject record=new JSONObject().put("version",1).put("file",copy.file.getName()).put("title",copy.title).put("bytes",copy.bytes).put("sha256",copy.hash);
        AtomicFile atomic=new AtomicFile(metadata);FileOutputStream out=null;
        try{out=atomic.startWrite();out.write((record.toString()+"\n").getBytes(StandardCharsets.UTF_8));atomic.finishWrite(out);out=null;}
        finally{if(out!=null)atomic.failWrite(out);}
    }
    String status(){
        try{synchronized(session){int[] count=session.counts();return new JSONObject().put("state",session.state()).put("reason",session.reason()).put("imported",count[0]).put("skipped",count[1]).put("errors",count[2]).toString();}}
        catch(Exception unavailable){return "{\"state\":\"error\"}";}
    }
}
