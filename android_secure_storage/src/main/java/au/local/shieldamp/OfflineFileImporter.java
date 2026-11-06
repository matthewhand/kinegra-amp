package au.local.shieldamp;

import java.io.*;
import java.security.*;
import java.util.UUID;
import java.nio.file.Files;
import java.nio.file.Path;

/** Bounded app-owned copies only; never renames or deletes a source document. */
final class OfflineFileImporter {
    static final long MAX_BYTES=64L*1024*1024, RESERVE_BYTES=128L*1024*1024;
    static final class Result {
        final File file; final String hash,format,title; final long bytes; final boolean duplicate;
        Result(File f,String h,String fmt,String t,long n,boolean d){file=f;hash=h;format=fmt;title=t;bytes=n;duplicate=d;}
    }
    interface Check {void check()throws IOException;}
    interface Admission {void check(String hash)throws IOException;}
    static final Check ALWAYS=()->{};
    static File destination(File privateRoot,String requested)throws IOException {
        if(requested==null||!new File(requested).isAbsolute())throw new IOException("Invalid library destination");
        File root=privateRoot.getCanonicalFile();
        Path rawRoot=privateRoot.getAbsoluteFile().toPath().normalize();
        Path raw=new File(requested).getAbsoluteFile().toPath().normalize();
        Path base=raw.startsWith(rawRoot)?rawRoot:root.toPath();
        if(!raw.startsWith(base)||raw.equals(base))throw new IOException("Invalid library destination");
        Path cursor=base;
        for(Path part:base.relativize(raw)){cursor=cursor.resolve(part);if(Files.isSymbolicLink(cursor))throw new IOException("Library path must not be a link");}
        File target=raw.toFile().getCanonicalFile();
        if(!target.getPath().startsWith(root.getPath()+File.separator)||!target.getName().equals("offline_music"))throw new IOException("Invalid library destination");
        if(!target.isDirectory()&&!target.mkdirs())throw new IOException("Library unavailable");
        return target;
    }
    static File child(File directory,String name)throws IOException {
        File root=directory.getCanonicalFile(),file=new File(directory,name);
        if(!root.toPath().equals(directory.getAbsoluteFile().toPath().normalize()))throw new IOException("Library directory changed");
        if(!file.getCanonicalFile().getParentFile().equals(root)||Files.isSymbolicLink(file.toPath()))throw new IOException("Invalid library file");
        return file;
    }
    static String title(String name){
        String clean=name==null?"":name.replaceAll("[\\p{Cntrl}\\\\/:]+"," ").trim();
        clean=clean.replaceFirst("(?i)\\.(mp3|ogg|oga)$","").trim();
        if(clean.isEmpty())clean="Imported audio";
        return clean.substring(0,Math.min(120,clean.length()));
    }
    static String format(byte[] header,int count)throws IOException {
        if(count>=4&&header[0]=='O'&&header[1]=='g'&&header[2]=='g'&&header[3]=='S')return "ogg";
        if(count>=3&&header[0]=='I'&&header[1]=='D'&&header[2]=='3')return "mp3";
        if(count>=2&&(header[0]&255)==255&&(header[1]&224)==224&&(header[1]&6)!=0&&(header[1]&24)!=8)return "mp3";
        throw new IOException("Choose MP3 or Ogg audio");
    }
    static String hex(byte[] bytes){char[] chars=new char[bytes.length*2];String digits="0123456789abcdef";for(int i=0;i<bytes.length;i++){int v=bytes[i]&255;chars[i*2]=digits.charAt(v>>>4);chars[i*2+1]=digits.charAt(v&15);}return new String(chars);}
    static String digest(File file,Check guard)throws IOException {
        try(InputStream in=new FileInputStream(file)){MessageDigest d=MessageDigest.getInstance("SHA-256");byte[] b=new byte[8192];int n;while(true){guard.check();n=in.read(b);if(n<0)break;if(n>0)d.update(b,0,n);}return hex(d.digest());}
        catch(NoSuchAlgorithmException e){throw new IOException("Digest unavailable");}
    }
    static Result copy(InputStream input,String displayName,File directory,long usableBytes)throws IOException {
        return copy(input,displayName,directory,usableBytes,ALWAYS);
    }
    static Result copy(InputStream input,String displayName,File directory,long usableBytes,Check guard)throws IOException {
        return copy(input,displayName,directory,usableBytes,guard,hash->{});
    }
    static Result copy(InputStream input,String displayName,File directory,long usableBytes,Check guard,Admission admission)throws IOException {
        if(input==null||!directory.isDirectory())throw new IOException("Source or destination unavailable");
        guard.check();
        if(usableBytes<RESERVE_BYTES+4)throw new IOException("Not enough device storage");
        long budget=Math.min(MAX_BYTES,usableBytes-RESERVE_BYTES);if(budget<4)throw new IOException("Not enough device storage");
        File temporary=child(directory,"import_"+UUID.randomUUID()+".part");
        if(!temporary.createNewFile())throw new IOException("Import unavailable");
        try {
            MessageDigest d=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[8192],header=new byte[16];int headerCount=0,n;long total=0;
            try(FileOutputStream out=new FileOutputStream(temporary)){
                while(true){
                    guard.check();n=input.read(buffer);guard.check();if(n==-1)break;
                    if(n==0)continue;
                    if(n>budget-total)throw new IOException("File too large or device storage low");
                    if(headerCount<header.length){int take=Math.min(n,header.length-headerCount);System.arraycopy(buffer,0,header,headerCount,take);headerCount+=take;}
                    out.write(buffer,0,n);d.update(buffer,0,n);total+=n;
                }
                out.getFD().sync();
            }
            guard.check();
            if(total<4)throw new IOException("Empty or invalid audio");
            String fmt=format(header,headerCount),hash=hex(d.digest());File target=child(directory,"import_"+hash+"."+fmt);
            guard.check();admission.check(hash);guard.check();
            if(target.exists()){
                if(target.length()!=total||!digest(target,guard).equals(hash))throw new IOException("Existing library file needs attention");
                return new Result(target,hash,fmt,title(displayName),total,true);
            }
            guard.check();
            // Same private directory, no REPLACE_EXISTING: never overwrite a
            // destination appearing between the duplicate check and publication.
            Files.move(temporary.toPath(),target.toPath());
            return new Result(target,hash,fmt,title(displayName),total,false);
        }catch(NoSuchAlgorithmException e){throw new IOException("Digest unavailable");}
        finally{if(temporary.exists())temporary.delete();}
    }
}
