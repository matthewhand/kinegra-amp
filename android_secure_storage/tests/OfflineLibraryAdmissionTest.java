package au.local.shieldamp;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.security.*;
public final class OfflineLibraryAdmissionTest {
    static int checks;
    static void ok(boolean v){checks++;if(!v)throw new AssertionError("admission check "+checks);}
    interface Run{void run()throws Exception;}
    static void fail(Run r)throws Exception{boolean failed=false;try{r.run();}catch(IOException e){failed=true;}ok(failed);}
    static String id(int i){return String.format("%064x",i);}
    static Map<String,Object> row(String id){Map<String,Object> m=new HashMap<>();m.put("sha256",id);m.put("file","import_"+id+".ogg");m.put("title","Synthetic");m.put("bytes",8);m.put("deleted",true);return m;}
    public static void main(String[] args)throws Exception{
        Path root=Files.createTempDirectory("shieldamp-capacity-test-");
        try{
            File dir=Files.createDirectory(root.resolve("offline_music")).toFile();
            Set<String> slots=new HashSet<>();for(int i=1;i<=1023;i++)slots.add(id(i));
            File catalog=new File(dir,"catalog-v1.json");Files.write(catalog.toPath(),new byte[]{'{','}'});
            OfflineLibraryAdmission.CatalogReader reader=f->slots;
            byte[] first=new byte[]{'O','g','g','S',1,2,3,4},second=new byte[]{'O','g','g','S',5,6,7,8};
            OfflineFileImporter.Result imported=OfflineFileImporter.copy(new ByteArrayInputStream(first),"first.ogg",dir,Long.MAX_VALUE,OfflineFileImporter.ALWAYS,h->OfflineLibraryAdmission.admit(dir,h,reader));
            ok(imported.file.exists());
            fail(()->OfflineFileImporter.copy(new ByteArrayInputStream(second),"second.ogg",dir,Long.MAX_VALUE,OfflineFileImporter.ALWAYS,h->OfflineLibraryAdmission.admit(dir,h,reader)));
            ok(dir.list().length==2);for(String name:dir.list())ok(!name.endsWith(".part"));
            // A full stable catalog, including tombstones, can restore its same hash.
            slots.add(imported.hash);imported.file.delete();
            OfflineFileImporter.Result restore=OfflineFileImporter.copy(new ByteArrayInputStream(first),"restore.ogg",dir,Long.MAX_VALUE,OfflineFileImporter.ALWAYS,h->OfflineLibraryAdmission.admit(dir,h,reader));
            ok(restore.hash.equals(imported.hash)&&restore.file.exists());
            fail(()->OfflineLibraryAdmission.admit(dir,id(5000),reader));
            List<Map<String,Object>> records=new ArrayList<>();records.add(row(id(1)));
            ok(OfflineLibraryAdmission.validate(1,records).contains(id(1)));
            fail(()->OfflineLibraryAdmission.validate(2,records));
            records.add(row(id(1)));fail(()->OfflineLibraryAdmission.validate(1,records));records.remove(1);
            records.get(0).put("deleted","false");fail(()->OfflineLibraryAdmission.validate(1,records));records.get(0).put("deleted",false);
            records.get(0).put("bytes",Double.NaN);fail(()->OfflineLibraryAdmission.validate(1,records));
            fail(()->OfflineLibraryAdmission.admit(dir,id(1),f->{throw new IOException("corrupt JSON");}));
            catalog.delete();Files.write(new File(dir,"slots-assigned-v1").toPath(),new byte[]{1});
            fail(()->OfflineLibraryAdmission.admit(dir,imported.hash,reader));
            new File(dir,"slots-assigned-v1").delete();Files.write(new File(dir,"catalog-v1.json.new").toPath(),new byte[]{1});
            fail(()->OfflineLibraryAdmission.admit(dir,imported.hash,reader));new File(dir,"catalog-v1.json.new").delete();
            // Pending receipts and staged deletes reserve identities before Godot adoption.
            restore.file.delete();String pending=id(9000);Files.write(new File(dir,"import_"+pending+".mp3.meta.json.delete").toPath(),new byte[]{1});
            slots.remove(imported.hash);Files.write(catalog.toPath(),new byte[]{'{','}'});
            fail(()->OfflineLibraryAdmission.admit(dir,id(9001),reader));OfflineLibraryAdmission.admit(dir,pending,reader);ok(true);
            Files.delete(new File(dir,"import_"+pending+".mp3.meta.json.delete").toPath());
            Path outside=root.resolve("outside");Files.write(outside,new byte[]{1});Files.createSymbolicLink(new File(dir,"import_"+pending+".ogg").toPath(),outside);
            fail(()->OfflineLibraryAdmission.admit(dir,pending,reader));ok(Files.readAllBytes(outside)[0]==1);
            System.out.println("OFFLINE_LIBRARY_ADMISSION_CHECKS="+checks);
        }finally{try(java.util.stream.Stream<Path> walk=Files.walk(root)){walk.sorted(Comparator.reverseOrder()).forEach(p->{try{Files.deleteIfExists(p);}catch(IOException ignored){}});}}
    }
}
