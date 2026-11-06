package au.local.shieldamp;
import java.io.*;
public final class OfflineImportSessionTest {
    static int checks;
    static void ok(boolean b){checks++;if(!b)throw new AssertionError("offline session check "+checks);}
    public static void main(String[] args)throws Exception{
        OfflineImportSession s=new OfflineImportSession();OfflineImportSession.Job a=s.begin();
        ok(a!=null&&s.choosing(a)&&s.begin()==null);
        ok(s.ownsRequest(a.request)&&!s.ownsRequest(a.request+1)&&!s.ownsRequest(1));
        ok(s.cancel("cancelled")&&s.requested(a.request)==null&&!s.startWorker(a));
        OfflineImportSession.Job b=s.begin();ok(b!=null&&b.request!=a.request&&b.epoch>a.epoch);
        s.choosingFailed(a,"error");s.error(a);s.finished(a);ok(s.choosing(b)&&s.counts()[2]==0);
        ok(s.startWorker(b)&&s.busy()&&s.begin()==null);
        final boolean[] closed={false};b.attach(()->closed[0]=true);
        ok(s.cancel("cancelled")&&s.state().equals("cancelling")&&s.begin()==null);
        b.closeActive();ok(closed[0]);
        boolean thrown=false;try{b.check();}catch(IOException yes){thrown=true;}ok(thrown);
        s.finished(b);ok(s.state().equals("cancelled")&&!s.busy());
        OfflineImportSession.Job c=s.begin();ok(s.startWorker(c));
        long first=c.deadline(60000);c.endFile(first);long second=c.deadline(60000);
        ok(!c.timeout(first)&&!c.cancelled);ok(c.timeout(second)&&c.cancelled&&s.begin()==null);
        s.finished(c);ok(s.state().equals("timed_out"));
        OfflineImportSession.Job d=s.begin();ok(s.startWorker(d));
        s.counted(d,false);s.counted(d,true);s.error(d);s.finished(d);
        ok(s.state().equals("complete")&&s.counts()[0]==1&&s.counts()[1]==1&&s.counts()[2]==1);
        OfflineImportSession.Job e=s.begin();s.startWorker(e);s.error(e);s.finished(e);ok(s.state().equals("error"));
        OfflineImportSession.Job f=s.begin();s.startWorker(f);f.deadline(0);Thread.sleep(1);
        thrown=false;try{f.check();}catch(IOException yes){thrown=true;}ok(thrown&&f.reason.equals("timed_out")&&s.begin()==null);
        s.finished(f);ok(s.state().equals("timed_out"));
        OfflineImportSession.Job g=s.begin();ok(s.startWorker(g));
        java.nio.file.Path directory=java.nio.file.Files.createTempDirectory("shieldamp-stalled-provider-");
        java.util.concurrent.CountDownLatch entered=new java.util.concurrent.CountDownLatch(1),release=new java.util.concurrent.CountDownLatch(1);
        InputStream blocked=new InputStream(){public int read()throws IOException{entered.countDown();try{release.await();}catch(InterruptedException e){throw new IOException("interrupted");}throw new IOException("closed synthetic provider");}public void close(){release.countDown();}};
        final boolean[] queryCancelled={false};g.query(()->queryCancelled[0]=true);g.attach(blocked);
        Thread reader=new Thread(()->{try{OfflineFileImporter.copy(blocked,"synthetic.ogg",directory.toFile(),Long.MAX_VALUE,g);}catch(IOException expected){}finally{s.finished(g);}});
        reader.start();ok(entered.await(1,java.util.concurrent.TimeUnit.SECONDS));
        ok(s.cancel("cancelled")&&s.begin()==null);g.closeActive();reader.join(1000);
        ok(!reader.isAlive()&&queryCancelled[0]&&s.state().equals("cancelled"));
        ok(directory.toFile().list().length==0);java.nio.file.Files.delete(directory);
        System.out.println("OFFLINE_IMPORT_SESSION_CHECKS="+checks);
    }
}
