package au.local.shieldamp;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public final class TokenMigrationTest {
    static final class FakeVault implements TokenMigration.Vault {
        byte[] data; boolean failRead,failWrite,corrupt;
        public boolean exists(){return data!=null;}
        public byte[] read()throws Exception{if(failRead)throw new Exception();return corrupt?new byte[]{9}:data.clone();}
        public void write(byte[] v)throws Exception{if(failWrite)throw new Exception();data=v.clone();}
    }
    static final class FakeLegacy implements TokenMigration.Legacy {
        byte[] data="fixture-token".getBytes(StandardCharsets.UTF_8); boolean failDelete,deleted;
        public boolean exists(){return data!=null;}
        public byte[] read(){return data.clone();}
        public boolean delete(){if(failDelete)return false;deleted=true;data=null;return true;}
    }
    static int checks;
    static void check(boolean ok){checks++;if(!ok)throw new AssertionError("check "+checks);}
    public static void main(String[] args)throws Exception {
        FakeVault stagedVault=new FakeVault();FakeLegacy stagedLegacy=new FakeLegacy();
        TokenMigration.Result staged=TokenMigration.stage(stagedVault,stagedLegacy);
        check("secure_legacy_remains".equals(staged.status)&&stagedLegacy.exists()&&!stagedLegacy.deleted&&stagedVault.exists());
        stagedVault=new FakeVault();stagedLegacy=new FakeLegacy();stagedVault.failRead=true;
        try{TokenMigration.stage(stagedVault,stagedLegacy);throw new AssertionError();}catch(Exception expected){check(stagedLegacy.exists()&&!stagedLegacy.deleted);}
        FakeVault v=new FakeVault();FakeLegacy l=new FakeLegacy();
        TokenMigration.Result ok=TokenMigration.load(v,l);check(l.deleted);check("migrated_no_legacy".equals(ok.status));check(new String(ok.token,StandardCharsets.UTF_8).equals("fixture-token"));
        v=new FakeVault();l=new FakeLegacy();v.failWrite=true;try{TokenMigration.load(v,l);throw new AssertionError();}catch(Exception expected){check(!l.deleted&&l.exists());}
        v=new FakeVault();l=new FakeLegacy();v.failRead=true;try{TokenMigration.load(v,l);throw new AssertionError();}catch(Exception expected){check(!l.deleted&&l.exists());}
        v=new FakeVault();l=new FakeLegacy();v.corrupt=true;try{TokenMigration.load(v,l);throw new AssertionError();}catch(Exception expected){check(!l.deleted&&l.exists());}
        v=new FakeVault();l=new FakeLegacy();l.failDelete=true;ok=TokenMigration.load(v,l);check("secure_legacy_remains".equals(ok.status)&&l.exists());
        v=new FakeVault();l=new FakeLegacy();v.data=new byte[]{1,2};v.failRead=true;try{TokenMigration.load(v,l);throw new AssertionError();}catch(Exception expected){check(!l.deleted&&l.exists());}
        v=new FakeVault();l=new FakeLegacy();v.data=new byte[]{1,2};try{TokenMigration.load(v,l);throw new AssertionError();}catch(TokenMigration.LegacyConflictException expected){check(l.exists()&&!l.deleted);}
        v=new FakeVault();l=new FakeLegacy();l.data=new byte[0];try{TokenMigration.load(v,l);throw new AssertionError();}catch(Exception expected){check(!l.deleted&&!v.exists());}
        v=new FakeVault();l=new FakeLegacy();l.data=new byte[8193];try{TokenMigration.load(v,l);throw new AssertionError();}catch(Exception expected){check(!l.deleted&&!v.exists());}
        v=new FakeVault();l=new FakeLegacy();v.data=l.data.clone();ok=TokenMigration.load(v,l);
        check(l.deleted&&"migrated_no_legacy".equals(ok.status));
        v=new FakeVault();l=new FakeLegacy();v.data=l.data.clone();l.failDelete=true;ok=TokenMigration.load(v,l);
        check(!l.deleted&&"secure_legacy_remains".equals(ok.status));
        v=new FakeVault();l=new FakeLegacy();v.data=l.data.clone();l.data=null;ok=TokenMigration.load(v,l);
        check("secure_no_legacy".equals(ok.status));
        System.out.println("TOKEN_MIGRATION_CHECKS="+checks);
    }
}
