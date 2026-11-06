package au.local.shieldamp;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;
/** Bounded Android platform JSON adapter; never writes or repairs the catalog. */
final class OfflineCatalogJson {
    // Android's JSON reader accepts extensions Godot does not. Validate the
    // bounded strict JSON grammar first so a corrupt catalog cannot reset slots.
    static final class Syntax {
        final String text;int at=0,nodes=0;
        Syntax(String value){text=value;}
        void bad()throws IOException{throw new IOException("Catalog needs repair");}
        void space(){while(at<text.length()&&" \t\r\n".indexOf(text.charAt(at))>=0)at++;}
        boolean take(char c){space();if(at<text.length()&&text.charAt(at)==c){at++;return true;}return false;}
        void validate()throws IOException{value(0);space();if(at!=text.length())bad();}
        void value(int depth)throws IOException{
            if(depth>8||++nodes>20000)bad();space();if(at>=text.length())bad();char c=text.charAt(at);
            if(c=='{'){at++;if(take('}'))return;do{space();string();if(!take(':'))bad();value(depth+1);}while(take(','));if(!take('}'))bad();return;}
            if(c=='['){at++;if(take(']'))return;do{value(depth+1);}while(take(','));if(!take(']'))bad();return;}
            if(c=='"'){string();return;}
            for(String literal:new String[]{"true","false","null"})if(text.startsWith(literal,at)){at+=literal.length();return;}
            if(c=='-')at++;
            if(at>=text.length())bad();
            if(text.charAt(at)=='0')at++;
            else{if(text.charAt(at)<'1'||text.charAt(at)>'9')bad();while(at<text.length()&&Character.isDigit(text.charAt(at))&&text.charAt(at)<128)at++;}
            if(at<text.length()&&text.charAt(at)=='.'){at++;digits();}
            if(at<text.length()&&(text.charAt(at)=='e'||text.charAt(at)=='E')){at++;if(at<text.length()&&(text.charAt(at)=='+'||text.charAt(at)=='-'))at++;digits();}
        }
        void digits()throws IOException{int start=at;while(at<text.length()&&text.charAt(at)>='0'&&text.charAt(at)<='9')at++;if(at==start)bad();}
        void string()throws IOException{
            if(at>=text.length()||text.charAt(at++)!='"')bad();
            while(at<text.length()){
                char c=text.charAt(at++);if(c=='"')return;if(c<32)bad();
                if(c=='\\'){
                    if(at>=text.length())bad();char escaped=text.charAt(at++);
                    if(escaped=='u'){for(int i=0;i<4;i++){if(at>=text.length()||"0123456789abcdefABCDEF".indexOf(text.charAt(at++))<0)bad();}}
                    else if("\"\\/bfnrt".indexOf(escaped)<0)bad();
                }
            }
            bad();
        }
    }
    static Set<String> read(File file)throws IOException {
        if(file.length()<2||file.length()>OfflineLibraryAdmission.MAX_CATALOG_BYTES)throw new IOException("Catalog needs repair");
        byte[] data=new byte[(int)file.length()];
        try(DataInputStream in=new DataInputStream(new FileInputStream(file))){in.readFully(data);if(in.read()!=-1)throw new IOException("Catalog moved during read");}
        try{
            String text=StandardCharsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(data)).toString();new Syntax(text).validate();
            JSONObject json=new JSONObject(text);
            Object raw=json.opt("slots");if(!(raw instanceof JSONArray))throw new IOException("Catalog needs repair");
            JSONArray array=(JSONArray)raw;if(array.length()>OfflineLibraryAdmission.MAX_IDENTITIES)throw new IOException("Catalog needs repair");
            List<Map<String,Object>> rows=new ArrayList<>();
            for(int i=0;i<array.length();i++){
                Object item=array.get(i);if(!(item instanceof JSONObject))throw new IOException("Catalog needs repair");
                JSONObject record=(JSONObject)item;Map<String,Object> values=new HashMap<>();
                for(String key:new String[]{"sha256","file","title","bytes","deleted"})values.put(key,record.opt(key));
                rows.add(values);
            }
            return OfflineLibraryAdmission.validate(json.opt("version"),rows);
        }catch(JSONException invalid){throw new IOException("Catalog needs repair");}
    }
}
