package au.local.shieldamp;
import java.io.*;
import java.nio.file.*;
import java.util.*;
public final class OfflineFileImporterTest {
    static int checks;
    static void ok(boolean value){checks++;if(!value)throw new AssertionError("offline file check "+checks);}
    interface Run{void run()throws Exception;}
    static void fails(Run run)throws Exception{boolean failed=false;try{run.run();}catch(IOException expected){failed=true;}ok(failed);}
    static byte[] audio(){byte[] b=new byte[20000];b[0]='O';b[1]='g';b[2]='g';b[3]='S';return b;}
    static void noParts(File dir){for(String name:dir.list())ok(!name.endsWith(".part"));}
    public static void main(String[] args)throws Exception {
        Path root=Files.createTempDirectory("shieldamp-import-unit-");
        try{
            File dir=OfflineFileImporter.destination(root.toFile(),root.resolve("offline_music").toString());
            byte[] input=audio();Path original=root.resolve("source.ogg");Files.write(original,input);
            OfflineFileImporter.Result a;
            try(InputStream in=Files.newInputStream(original)){a=OfflineFileImporter.copy(in,"Original.ogg",dir,Long.MAX_VALUE);}
            ok(a.file.isFile()&&a.bytes==input.length&&a.format.equals("ogg")&&!a.duplicate&&a.title.equals("Original"));
            ok(Arrays.equals(Files.readAllBytes(original),input));
            OfflineFileImporter.Result duplicate=OfflineFileImporter.copy(new ByteArrayInputStream(input),"different.ogg",dir,Long.MAX_VALUE);
            ok(duplicate.duplicate&&a.file.equals(duplicate.file));
            ok(a.file.getName().equals("import_"+a.hash+".ogg"));
            fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(new byte[100]),"not audio",dir,Long.MAX_VALUE));noParts(dir);
            fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(input),"too big",dir,OfflineFileImporter.RESERVE_BYTES+10));noParts(dir);
            fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(input),"no space",dir,0));
            fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(input),"negative space",dir,Long.MIN_VALUE));
            final int[] calls={0};fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(input),"cancel",dir,Long.MAX_VALUE,()->{if(++calls[0]>3)throw new IOException("synthetic cancel");}));noParts(dir);
            fails(()->OfflineFileImporter.copy(new InputStream(){int n;public int read()throws IOException{if(n++>100)throw new IOException("synthetic read failure");return n<5?"OggS".charAt(n-1):0;}},"read fail",dir,Long.MAX_VALUE));noParts(dir);
            InputStream huge=new InputStream(){long at;public int read(){return at++<4?"OggS".charAt((int)at-1):0;}public int read(byte[] b,int off,int len){for(int i=0;i<len;i++)b[off+i]=(byte)read();return len;}};
            fails(()->OfflineFileImporter.copy(huge,"over64m",dir,Long.MAX_VALUE));noParts(dir);
            Files.write(a.file.toPath(),new byte[]{1,2,3});
            fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(input),"corrupt duplicate",dir,Long.MAX_VALUE));ok(a.file.length()==3);
            fails(()->OfflineFileImporter.destination(root.toFile(),root.resolve("../offline_music").toString()));
            fails(()->OfflineFileImporter.destination(root.toFile(),"relative/offline_music"));
            Path real=root.resolve("real");Files.createDirectory(real);Path link=root.resolve("linked");Files.createSymbolicLink(link,real);
            fails(()->OfflineFileImporter.destination(root.toFile(),link.resolve("offline_music").toString()));
            Path victim=root.resolve("victim");Files.write(victim,input);a.file.delete();Files.createSymbolicLink(a.file.toPath(),victim);
            fails(()->OfflineFileImporter.copy(new ByteArrayInputStream(input),"linked target",dir,Long.MAX_VALUE));ok(Arrays.equals(Files.readAllBytes(victim),input));
            ok(OfflineFileImporter.title("../private\ntrack.mp3").equals(".. private track"));
            ok(OfflineFileImporter.title(String.join("",Collections.nCopies(300,"a"))).length()==120);
            ok(OfflineFileImporter.format(new byte[]{'I','D','3',0},4).equals("mp3"));
            ok(OfflineFileImporter.format(new byte[]{(byte)255,(byte)251,0,0},4).equals("mp3"));
            System.out.println("OFFLINE_IMPORT_FILE_CHECKS="+checks);
        }finally{try(java.util.stream.Stream<Path> walk=Files.walk(root)){walk.sorted(Comparator.reverseOrder()).forEach(p->{try{Files.deleteIfExists(p);}catch(IOException ignored){}});}}
    }
}
