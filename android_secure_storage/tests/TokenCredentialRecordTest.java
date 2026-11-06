package au.local.shieldamp;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public final class TokenCredentialRecordTest {
    static int checks;
    static void check(boolean ok){checks++;if(!ok)throw new AssertionError("record check "+checks);}
    static void rejects(byte[] value)throws Exception {try{TokenCredentialRecord.decode(value);throw new AssertionError();}catch(java.io.IOException expected){checks++;}}
    public static void main(String[] args)throws Exception {
        byte[] token="synthetic-library-access".getBytes(StandardCharsets.UTF_8);
        byte[] encoded=TokenCredentialRecord.encode("HTTPS://EXAMPLE.INVALID:8443/",token);
        TokenCredentialRecord.Record record=TokenCredentialRecord.decode(encoded);
        check(record.endpoint.equals("https://example.invalid:8443")&&Arrays.equals(record.token,token));
        check(!record.endpoint.equals("https://other.invalid:8443"));
        encoded[encoded.length-1]=0;check(Arrays.equals(record.token,token));
        record=TokenCredentialRecord.decode(token);check(record.endpoint.isEmpty()&&Arrays.equals(record.token,token)&&record.token!=token);
        byte[] max=new byte[8192];record=TokenCredentialRecord.decode(TokenCredentialRecord.encode("https://example.invalid",max));check(record.token.length==8192);
        try{TokenCredentialRecord.encode("https://example.invalid",new byte[8193]);throw new AssertionError();}catch(IllegalArgumentException expected){checks++;}
        for(String endpoint:new String[]{"https://user:secret@example.invalid","https://example.invalid/path","https://example.invalid?token=secret","https://example.invalid#fragment","file:///tmp/x","https://example.invalid:0","https://example.invalid:65536","https://example.invalid\n"}){
            try{TokenCredentialRecord.endpoint(endpoint);if(endpoint.endsWith("\n")){checks++;continue;}throw new AssertionError();}catch(Exception expected){checks++;}
        }
        encoded=TokenCredentialRecord.encode("https://example.invalid",token);
        rejects(Arrays.copyOf(encoded,7));rejects(Arrays.copyOf(encoded,encoded.length-1));
        rejects(Arrays.copyOf(encoded,encoded.length+1));rejects(new byte[0]);
        System.out.println("TOKEN_RECORD_CHECKS="+checks);
    }
}
