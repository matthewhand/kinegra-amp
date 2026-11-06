package au.local.shieldamp;

import java.io.*;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Locale;

/** A server binding and token share one authenticated encrypted transaction. */
final class TokenCredentialRecord {
    static final int MAX_TOKEN=8192, MAX_ENDPOINT=256, MAX_RECORD=MAX_TOKEN+MAX_ENDPOINT+8;
    private static final int MAGIC=0x53414332;
    static final class Record {
        final String endpoint; final byte[] token;
        Record(String endpoint,byte[] token){this.endpoint=endpoint;this.token=token;}
    }
    static String endpoint(String value)throws Exception {
        if(value==null)throw new IllegalArgumentException("Missing endpoint");
        String normalized=value.trim().toLowerCase(Locale.ROOT);
        if(normalized.endsWith("/"))normalized=normalized.substring(0,normalized.length()-1);
        if(normalized.length()<1||normalized.length()>MAX_ENDPOINT)throw new IllegalArgumentException("Invalid endpoint");
        URI uri=new URI(normalized);
        if(!("https".equals(uri.getScheme())||"http".equals(uri.getScheme()))||uri.getHost()==null||uri.getRawUserInfo()!=null||uri.getRawQuery()!=null||uri.getRawFragment()!=null||(uri.getRawPath()!=null&&!uri.getRawPath().isEmpty())||uri.getPort()==0||uri.getPort()>65535)
            throw new IllegalArgumentException("Invalid endpoint");
        for(int i=0;i<normalized.length();i++)if(normalized.charAt(i)<33||normalized.charAt(i)>126)throw new IllegalArgumentException("Invalid endpoint");
        return normalized;
    }
    static byte[] encode(String endpoint,byte[] token)throws Exception {
        if(token==null||token.length<1||token.length>MAX_TOKEN)throw new IllegalArgumentException("Invalid token size");
        String origin=endpoint.isEmpty()?"":endpoint(endpoint);
        byte[] address=origin.getBytes(StandardCharsets.UTF_8);
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        DataOutputStream out=new DataOutputStream(bytes);
        out.writeInt(MAGIC);out.writeShort(address.length);out.write(address);out.writeShort(token.length);out.write(token);out.flush();
        return bytes.toByteArray();
    }
    static Record decode(byte[] value)throws Exception {
        if(value==null||value.length<1||value.length>MAX_RECORD)throw new IOException("Invalid credential record");
        if(value.length<4||new DataInputStream(new ByteArrayInputStream(value)).readInt()!=MAGIC){
            if(value.length>MAX_TOKEN)throw new IOException("Invalid legacy record");
            return new Record("",value.clone());
        }
        DataInputStream in=new DataInputStream(new ByteArrayInputStream(value));in.readInt();
        int size=in.readUnsignedShort();if(size>MAX_ENDPOINT)throw new IOException("Invalid endpoint size");
        byte[] address=new byte[size];in.readFully(address);
        String origin=new String(address,StandardCharsets.UTF_8);
        if(!origin.isEmpty()&&!endpoint(origin).equals(origin))throw new IOException("Invalid endpoint binding");
        int length=in.readUnsignedShort();if(length<1||length>MAX_TOKEN)throw new IOException("Invalid token size");
        byte[] token=new byte[length];
        try{in.readFully(token);if(in.read()!=-1)throw new IOException("Trailing record data");return new Record(origin,token);}
        catch(Exception failure){Arrays.fill(token,(byte)0);throw failure;}
    }
}
