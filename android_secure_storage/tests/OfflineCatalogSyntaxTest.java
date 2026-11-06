package au.local.shieldamp;
public final class OfflineCatalogSyntaxTest {
    static int checks;
    static void check(String text,boolean valid)throws Exception {
        boolean accepted=true;try{new OfflineCatalogJson.Syntax(text).validate();}catch(java.io.IOException expected){accepted=false;}
        checks++;if(accepted!=valid)throw new AssertionError("catalog syntax check "+checks);
    }
    public static void main(String[] args)throws Exception {
        for(String text:new String[]{"{}"," {\"version\":1,\"slots\":[]}\n","[true,false,null,-1.2e+3]","{\"title\":\"Synthetic \\u00e9 \\\"\\\\\"}"})check(text,true);
        for(String text:new String[]{"", "{", "{} x", "{version:1}","{'version':1}","{/*comment*/}","{\"x\":1,}","[1,]","NaN","Infinity","01","+1","1.","1e", "\"bad\\x\"", "\"bad\\uGGGG\"", "\"raw\nline\"","[[[[[[[[[[0]]]]]]]]]]"})check(text,false);
        System.out.println("OFFLINE_CATALOG_SYNTAX_CHECKS="+checks);
    }
}
