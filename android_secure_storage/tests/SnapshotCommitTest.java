package au.local.shieldamp;
import java.util.Arrays;

public final class SnapshotCommitTest {
    static final class Fake implements SnapshotCommit.Operations {
        byte[] committed={1}, staged; int fail; boolean clean;
        public void stage(byte[] value)throws Exception{if(fail==1)throw new Exception();staged=value.clone();}
        public void sync()throws Exception{if(fail==2)throw new Exception();}
        public void publish()throws Exception{if(fail==3)throw new Exception();committed=staged.clone();}
        public void cleanup(){staged=null;clean=true;}
    }
    public static void main(String[] args)throws Exception{
        int checks=0;
        for(int point=1;point<=3;point++){
            Fake f=new Fake();f.fail=point;
            try{SnapshotCommit.replace(f,new byte[]{2});throw new AssertionError("accepted failed stage");}
            catch(Exception expected){if(!Arrays.equals(f.committed,new byte[]{1})||!f.clean)throw new AssertionError("prior snapshot lost");checks++;}
        }
        Fake f=new Fake();SnapshotCommit.replace(f,new byte[]{2});
        if(!Arrays.equals(f.committed,new byte[]{2})||!f.clean)throw new AssertionError("successful commit failed");checks++;
        System.out.println("SNAPSHOT_COMMIT_CHECKS="+checks);
    }
}
