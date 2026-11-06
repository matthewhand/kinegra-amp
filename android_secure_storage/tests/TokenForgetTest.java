package au.local.shieldamp;

public final class TokenForgetTest {
    static final class Store implements TokenForget.Store {
        String events="",pairing="untouched";boolean blocked,key,legacy,encrypted;
        boolean failBlock,failKey,failLegacy,failEncrypted;
        public void blockReuse()throws Exception{events+="block;";if(failBlock)throw new Exception();blocked=true;}
        public void destroyKey()throws Exception{events+="key;";if(failKey)throw new Exception();key=true;}
        public boolean deleteLegacy(){events+="legacy;";legacy=!failLegacy;return legacy;}
        public boolean deleteEncrypted(){events+="record;";encrypted=!failEncrypted;return encrypted;}
    }
    static int checks;
    static void check(boolean ok){checks++;if(!ok)throw new AssertionError("forget check "+checks);}
    public static void main(String[] args)throws Exception {
        Store store=new Store();check(TokenForget.forget(store));
        check(store.events.equals("block;key;legacy;record;")&&store.blocked&&store.key&&store.legacy&&store.encrypted);
        check(store.pairing.equals("untouched"));
        check(TokenForget.forget(store));check(store.pairing.equals("untouched"));
        store=new Store();store.failBlock=true;
        try{TokenForget.forget(store);throw new AssertionError();}catch(Exception expected){check(store.events.equals("block;")&&!store.key&&!store.legacy&&!store.encrypted);}
        store=new Store();store.failKey=true;check(!TokenForget.forget(store)&&store.blocked&&store.legacy&&store.encrypted);
        store=new Store();store.failLegacy=true;check(!TokenForget.forget(store)&&store.blocked&&store.key&&store.encrypted);
        store=new Store();store.failEncrypted=true;check(!TokenForget.forget(store)&&store.blocked&&store.key&&store.legacy);
        System.out.println("TOKEN_FORGET_CHECKS="+checks);
    }
}
