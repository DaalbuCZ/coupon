package local.couponpocket;

import javax.net.ssl.HttpsURLConnection;
import java.net.URL;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/** Single network boundary: allowlisted HTTPS, no cookies, redirects, tracking, or logging. */
public final class Transport implements RequestClient {
    public static final class Reply {
        public final int status;public final String body;
        Reply(int status,String body){this.status=status;this.body=body;}
        public boolean ok(){return status>=200&&status<300;}
    }
    public Reply call(String method,String url,Map<String,String> headers,String body,String contentType) throws Exception {
        Protocol.allow(url);
        HttpsURLConnection c=(HttpsURLConnection)new URL(url).openConnection();
        try {
            c.setInstanceFollowRedirects(false);c.setRequestMethod(method);
            c.setConnectTimeout(15000);c.setReadTimeout(20000);c.setUseCaches(false);
            c.setRequestProperty("Accept","application/json");
            c.setRequestProperty("User-Agent","CouponPocket/0.3.0 (Android)");
            for(Map.Entry<String,String> h:headers.entrySet()) c.setRequestProperty(h.getKey(),h.getValue());
            if(body!=null){
                byte[] data=body.getBytes(StandardCharsets.UTF_8);
                c.setDoOutput(true);c.setRequestProperty("Content-Type",contentType);c.setFixedLengthStreamingMode(data.length);
                try(java.io.OutputStream out=c.getOutputStream()){out.write(data);}
            }
            int status=c.getResponseCode();
            if(status>=300&&status<400) throw new SecurityException("Server redirect blocked. No token was forwarded.");
            InputStream stream=status>=400?c.getErrorStream():c.getInputStream();
            String response="";
            if(stream!=null)try(InputStream in=stream){response=new String(read(in,4*1024*1024),StandardCharsets.UTF_8);}
            return new Reply(status,response);
        } finally {c.disconnect();}
    }
    public static byte[] read(InputStream in,int limit) throws Exception {
        ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;
        while((n=in.read(buffer))!=-1){if(out.size()+n>limit)throw new IllegalArgumentException("The response or image is too large.");out.write(buffer,0,n);}
        return out.toByteArray();
    }
}
