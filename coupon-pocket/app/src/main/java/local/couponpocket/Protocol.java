package local.couponpocket;

import java.net.URI;
import java.net.URLEncoder;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/** Pure protocol rules, also tested on the JVM. No Android identifiers. */
public final class Protocol {
    public static final String ACCOUNT = "https://accounts.lidl.com/";
    public static final String COUPONS = "https://coupons.lidlplus.com/app/api/";
    public static final String PROFILE = "https://profile.lidlplus.com/api/";
    public static final String CLIENT = "LidlPlusNativeClient";
    public static final String CALLBACK = "com.lidlplus.app://callback";
    public static final String SCOPE = "openid profile offline_access lpprofile lpapis";

    /** Matches the inspected native client's token authentication (ko0 -> i81 -> bhj.p).
     * This fixed value is shipped in the original APK; it is not a user's password.
     * Send it only to the allowlisted account token endpoint, never coupon/profile APIs.
     */
    public static Map<String,String> tokenHeaders() {
        String client=encode(CLIENT)+":"+encode("secret");
        return fields("Authorization","Basic "+Base64.getEncoder().encodeToString(client.getBytes(StandardCharsets.US_ASCII)));
    }

    public static String random() {
        byte[] b = new byte[32];
        new SecureRandom().nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }
    public static String challenge(String verifier) throws Exception {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(
            MessageDigest.getInstance("SHA-256").digest(verifier.getBytes(StandardCharsets.US_ASCII)));
    }
    public static String encode(String value) {
        try { return URLEncoder.encode(value, "UTF-8"); }
        catch (Exception e) { throw new IllegalArgumentException("Cannot encode request", e); }
    }
    public static String path(String value) { return encode(value).replace("+", "%20"); }
    public static String form(Map<String, String> fields) {
        StringBuilder b = new StringBuilder();
        for (Map.Entry<String, String> f : fields.entrySet()) {
            if (b.length() > 0) b.append('&');
            b.append(encode(f.getKey())).append('=').append(encode(f.getValue()));
        }
        return b.toString();
    }
    public static Map<String,String> fields(String... values) {
        Map<String,String> result = new LinkedHashMap<>();
        for (int i=0; i<values.length; i+=2) result.put(values[i], values[i+1]);
        return result;
    }
    public static void allow(String url) {
        URI uri = URI.create(url);
        String host = uri.getHost();
        if (!"https".equals(uri.getScheme()) || uri.getRawUserInfo()!=null ||
            (uri.getPort()!=-1 && uri.getPort()!=443) || uri.getFragment()!=null ||
            !("accounts.lidl.com".equals(host) || "coupons.lidlplus.com".equals(host) ||
              ("profile.lidlplus.com".equals(host) && uri.getRawQuery()==null && uri.getRawPath().matches("/api/v1/[A-Z]{2}/loyalty"))))
            throw new SecurityException("Connection outside the account, coupon and loyalty services was blocked.");
    }
    public static boolean callback(String url) {
        try {
            URI u=URI.create(url);
            return "com.lidlplus.app".equals(u.getScheme()) && "callback".equals(u.getHost()) &&
                u.getPort()==-1 && u.getRawUserInfo()==null && u.getFragment()==null &&
                (u.getRawPath()==null || u.getRawPath().isEmpty());
        } catch (Exception e) { return false; }
    }
    public static boolean matchingState(String actual, String expected) {
        return actual!=null && expected!=null && !expected.isEmpty() &&
            MessageDigest.isEqual(actual.getBytes(StandardCharsets.UTF_8),expected.getBytes(StandardCharsets.UTF_8));
    }
    public static boolean recent(long created, long now) {
        return created>0 && now>=created && now-created<=10*60*1000;
    }
    public static Map<String,String> callbackFields(String url,String expectedState,long created,long now) {
        if(!callback(url))throw new SecurityException("Invalid login callback.");
        Map<String,String> values=new LinkedHashMap<>();
        String query=URI.create(url).getRawQuery();
        if(query==null || query.length()>20000)throw new SecurityException("Invalid login callback parameters.");
        try {
            for(String part:query.split("&")){
                String[] pair=part.split("=",2);
                String key=URLDecoder.decode(pair[0],"UTF-8"),value=pair.length==2?URLDecoder.decode(pair[1],"UTF-8"):"";
                if(values.put(key,value)!=null)throw new SecurityException("Duplicate login callback parameter.");
            }
        } catch(java.io.UnsupportedEncodingException|IllegalArgumentException e){throw new SecurityException("Invalid login callback encoding.");}
        if(!matchingState(values.get("state"),expectedState)||!recent(created,now))
            throw new SecurityException("This callback does not match a recent login started here.");
        return values;
    }
    public static void locale(String country, String language) {
        if (!country.matches("[A-Z]{2}") || !language.matches("[a-z]{2,3}(-[A-Z]{2})?"))
            throw new IllegalArgumentException("Use a two-letter country (CZ) and language (cs-CZ).");
    }
    private Protocol() {}
}
