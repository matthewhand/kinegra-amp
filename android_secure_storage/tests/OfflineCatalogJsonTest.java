package au.local.shieldamp;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
public final class OfflineCatalogJsonTest {
    static int checks;
    static void check(File f,String json,boolean valid)throws Exception{
        Files.write(f.toPath(),json.getBytes(StandardCharsets.UTF_8));boolean accepted=true;
        try{OfflineCatalogJson.read(f);}catch(IOException expected){accepted=false;}
        checks++;if(accepted!=valid)throw new AssertionError("catalog JSON check "+checks);
    }
    public static void main(String[] args)throws Exception{
        File f=File.createTempFile("shieldamp-json-",".json");
        try{
            String h=String.format("%064x",1),r="{\"sha256\":\""+h+"\",\"file\":\"import_"+h+".ogg\",\"title\":\"Synthetic\",\"bytes\":8,\"deleted\":true}";
            check(f,"{\"version\":1,\"slots\":["+r+"]}",true);
            check(f,"{\"version\":2,\"slots\":["+r+"]}",false);
            check(f,"{\"version\":1,\"slots\":["+r+","+r+"]}",false);
            check(f,"{",false);check(f,"[]",false);check(f,"{\"version\":1,\"slots\":[]}",true);
            check(f,"{\"version\":1,\"slots\":[{}]}",false);
            check(f,"{\"version\":1,\"slots\":["+r.replace("true","\"true\"")+"]}",false);
            check(f,"{\"version\":1,\"slots\":[]} trailing",false);
            check(f,"{version:1,slots:[]}",false);
            check(f,"{\"version\":1,\"slots\":[],}",false);
            check(f,"{/*comment*/\"version\":1,\"slots\":[]}",false);
            System.out.println("OFFLINE_CATALOG_JSON_CHECKS="+checks);
        }finally{f.delete();}
    }
}
