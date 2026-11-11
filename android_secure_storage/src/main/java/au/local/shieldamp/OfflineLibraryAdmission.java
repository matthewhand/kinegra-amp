package au.local.shieldamp;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;

/** Read-only union of append-only slots and unadopted private hash files. */
final class OfflineLibraryAdmission {
    static final int MAX_IDENTITIES=4096,MAX_ENTRIES=16384,MAX_CATALOG_BYTES=4194304;
    static final Pattern HASH=Pattern.compile("[0-9a-f]{64}");
    static final Pattern FILE=Pattern.compile("import_([0-9a-f]{64})\\.(?:mp3|ogg)(?:\\.meta\\.json)?(?:\\.delete)?");
    interface CatalogReader {Set<String> read(File file)throws IOException;}
    static boolean number(Object value,long low,long high){
        if(!(value instanceof Number))return false;double n=((Number)value).doubleValue();
        return Double.isFinite(n)&&n==Math.rint(n)&&n>=low&&n<=high;
    }
    static Set<String> validate(Object version,List<Map<String,Object>> slots)throws IOException {
        if(!number(version,1,1)||slots==null||slots.size()>MAX_IDENTITIES)throw new IOException("Catalog needs repair");
        Set<String> ids=new HashSet<>();
        for(Map<String,Object> row:slots){
            if(row==null)throw new IOException("Catalog needs repair");
            Object hash=row.get("sha256"),file=row.get("file"),title=row.get("title");
            if(!(hash instanceof String)||!HASH.matcher((String)hash).matches()||!(file instanceof String)||!(file.equals("import_"+hash+".mp3")||file.equals("import_"+hash+".ogg"))||!(title instanceof String)||((String)title).trim().isEmpty()||((String)title).length()>240||!number(row.get("bytes"),4,OfflineFileImporter.MAX_BYTES)||!(row.get("deleted") instanceof Boolean)||!ids.add((String)hash))throw new IOException("Catalog needs repair");
        }
        return ids;
    }
    static void admit(File directory,String hash,CatalogReader reader)throws IOException {
        if(hash==null||!HASH.matcher(hash).matches())throw new IOException("Invalid import identity");
        File catalog=OfflineFileImporter.child(directory,"catalog-v1.json");Set<String> assigned=new HashSet<>();
        if(catalog.exists()){
            if(!catalog.isFile()||catalog.length()<2||catalog.length()>MAX_CATALOG_BYTES)throw new IOException("Catalog needs repair");
            assigned.addAll(reader.read(catalog));
            if(assigned.size()>MAX_IDENTITIES)throw new IOException("Catalog needs repair");
        }else{
            for(String marker:new String[]{"slots-assigned-v1","catalog-v1.json.new","catalog-v1.json.bak"})if(OfflineFileImporter.child(directory,marker).exists())throw new IOException("Catalog missing; imports paused");
        }
        Set<String> all=new HashSet<>(assigned);int visited=0;
        try(DirectoryStream<Path> files=Files.newDirectoryStream(directory.toPath())){
            for(Path path:files){
                if(++visited>MAX_ENTRIES)throw new IOException("Too many library entries");
                Matcher match=FILE.matcher(path.getFileName().toString());
                if(!match.matches())continue;
                File file=OfflineFileImporter.child(directory,path.getFileName().toString());
                if(!file.isFile())throw new IOException("Invalid library entry");
                all.add(match.group(1));
            }
        }
        // Stable catalog slots, including deleted ones, can always be restored.
        if(assigned.contains(hash))return;
        if(all.size()>MAX_IDENTITIES||(!all.contains(hash)&&all.size()>=MAX_IDENTITIES))throw new IOException("Library slot limit reached");
    }
}
