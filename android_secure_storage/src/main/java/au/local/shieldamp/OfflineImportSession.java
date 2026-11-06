package au.local.shieldamp;

import java.io.Closeable;
import java.io.IOException;

/** One picker/worker at a time. Cancellation never authorizes another worker early. */
final class OfflineImportSession {
    static final class Job implements OfflineFileImporter.Check {
        final long epoch; final int request;
        volatile boolean cancelled=false;
        volatile String reason="cancelled";
        private long deadline=Long.MAX_VALUE,fileEpoch=0;
        private boolean fileOpen=false;
        private Closeable input;
        private Runnable queryCancel;
        Job(long e,int r){epoch=e;request=r;}
        synchronized long deadline(long milliseconds){fileOpen=true;deadline=System.nanoTime()+milliseconds*1000000L;return ++fileEpoch;}
        synchronized void endFile(long file){if(file==fileEpoch){fileOpen=false;deadline=Long.MAX_VALUE;}}
        synchronized boolean timeout(long file){if(!fileOpen||file!=fileEpoch||cancelled)return false;cancel("timed_out");return true;}
        public synchronized void check()throws IOException {
            if(!cancelled&&System.nanoTime()>deadline){cancelled=true;reason="timed_out";}
            if(cancelled)throw new IOException("Import cancelled or timed out");
        }
        synchronized void attach(Closeable value)throws IOException {input=value;check();}
        synchronized void detach(Closeable value){if(input==value)input=null;}
        synchronized void query(Runnable cancel){queryCancel=cancel;}
        synchronized void clearQuery(){queryCancel=null;}
        synchronized void cancel(String why){cancelled=true;reason=why;}
        void closeActive(){
            Closeable stream;Runnable query;
            synchronized(this){stream=input;query=queryCancel;}
            if(query!=null)try{query.run();}catch(RuntimeException ignored){}
            if(stream!=null)try{stream.close();}catch(IOException ignored){}
        }
    }
    private long epoch=0;
    private int nextRequest=0x4b41;
    private Job current;
    private boolean worker=false;
    private String state="idle";
    private int imported=0,skipped=0,errors=0;
    synchronized Job begin(){
        if(worker||"choosing".equals(state)||nextRequest>0x7fff)return null;
        current=new Job(++epoch,nextRequest++);state="choosing";imported=skipped=errors=0;return current;
    }
    synchronized boolean ownsRequest(int request){return request>=0x4b41&&request<nextRequest;}
    synchronized void invalidDestination(){if(!busy()){current=null;state="error";imported=skipped=0;errors=1;}}
    synchronized boolean choosing(Job job){return current==job&&!job.cancelled&&"choosing".equals(state);}
    synchronized Job requested(int request){return current!=null&&current.request==request&&choosing(current)?current:null;}
    synchronized boolean startWorker(Job job){if(!choosing(job))return false;worker=true;state="copying";return true;}
    synchronized boolean cancel(String reason){
        if(current==null||(!worker&&!"choosing".equals(state)))return false;
        current.cancel(reason);state=worker?"cancelling":reason;return true;
    }
    synchronized Job current(){return current;}
    synchronized void choosingFailed(Job job,String reason){if(choosing(job)){job.cancel(reason);state=reason;}}
    synchronized void counted(Job job,boolean duplicate){if(current==job){if(duplicate)skipped++;else imported++;}}
    synchronized void error(Job job){if(current==job)errors++;}
    synchronized void finished(Job job){
        if(current!=job)return;
        worker=false;
        state=job.cancelled?job.reason:(errors>0&&imported+skipped==0?"error":"complete");
    }
    synchronized String state(){return worker&&current!=null&&current.cancelled?"cancelling":state;}
    synchronized int[] counts(){return new int[]{imported,skipped,errors};}
    synchronized String reason(){return current!=null&&current.cancelled?current.reason:"";}
    synchronized boolean busy(){return worker||"choosing".equals(state);}
}
