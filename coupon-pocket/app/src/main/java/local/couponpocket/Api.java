package local.couponpocket;

import org.json.JSONObject;
import java.util.Map;

public final class Api {
    private final Storage vault;
    private final RequestClient transport;
    public Api(Storage vault){this(vault,new Transport());}
    public Api(Storage vault,RequestClient transport){this.vault=vault;this.transport=transport;}
    public boolean signedIn() throws Exception {return !vault.json("session").optString("access_token").isEmpty();}
    public String beginLogin(String country,String language) throws Exception {
        Protocol.locale(country,language);
        String verifier=Protocol.random(),state=Protocol.random();
        vault.json("pending",new JSONObject().put("verifier",verifier).put("state",state).put("created",System.currentTimeMillis()));
        return Protocol.ACCOUNT+"connect/authorize?"+Protocol.form(Protocol.fields(
            "client_id",Protocol.CLIENT,"response_type","code","redirect_uri",Protocol.CALLBACK,
            "scope",Protocol.SCOPE,"state",state,"nonce",Protocol.random(),
            "code_challenge",Protocol.challenge(verifier),"code_challenge_method","S256",
            "country_code",country,"language",language));
    }
    public void finishLogin(String callback) throws Exception {
        JSONObject pending=vault.json("pending");
        Map<String,String> fields=Protocol.callbackFields(callback,pending.optString("state"),pending.optLong("created"),System.currentTimeMillis());
        String verifier=pending.optString("verifier");
        vault.delete("pending");
        if(fields.containsKey("error"))throw new IllegalArgumentException("Login was cancelled or rejected by Lidl.");
        if(verifier.isEmpty())throw new SecurityException("Missing login code.");
        String code=fields.get("code");
        if(code==null || code.isEmpty() || code.length()>8192)throw new SecurityException("Invalid login code.");
        Transport.Reply reply=transport.call("POST",Protocol.ACCOUNT+"connect/token",Protocol.tokenHeaders(),
            Protocol.form(Protocol.fields("grant_type","authorization_code",
                "redirect_uri",Protocol.CALLBACK,"code",code,"code_verifier",verifier)),"application/x-www-form-urlencoded");
        if(!reply.ok())throw new IllegalArgumentException(OAuthError.message("Login exchange",reply.status,reply.body));
        // A new login may select another account; never carry its card or cache over.
        for(String name:new String[]{"coupons","card-image","card-text","loyalty"})vault.delete(name);
        saveTokens(reply.body,"");
    }
    private void saveTokens(String body,String previousRefresh) throws Exception {
        JSONObject result=new JSONObject(body);
        String access=result.optString("access_token"),type=result.optString("token_type");
        if(access.isEmpty() || !"Bearer".equalsIgnoreCase(type))throw new SecurityException("No supported access token returned.");
        long seconds=result.optLong("expires_in",300);
        if(seconds<=0 || seconds>365L*24*3600)throw new SecurityException("Invalid token expiry.");
        vault.json("session",new JSONObject().put("access_token",access)
            .put("refresh_token",result.optString("refresh_token",previousRefresh))
            .put("expires",System.currentTimeMillis()+seconds*1000));
    }
    private String access(boolean forceRefresh) throws Exception {
        JSONObject session=vault.json("session");String token=session.optString("access_token");
        if(token.isEmpty())throw new IllegalArgumentException("Log in first.");
        if(forceRefresh || session.optLong("expires")<System.currentTimeMillis()+60000){
            String refresh=session.optString("refresh_token");
            if(refresh.isEmpty())throw new IllegalArgumentException("Your session expired. Log in again.");
            Transport.Reply reply=transport.call("POST",Protocol.ACCOUNT+"connect/token",Protocol.tokenHeaders(),
                Protocol.form(Protocol.fields("grant_type","refresh_token","refresh_token",refresh)),
                "application/x-www-form-urlencoded");
            if(!reply.ok()){
                if(reply.status==400 || reply.status==401){vault.delete("session");vault.delete("coupons");vault.delete("loyalty");}
                throw new IllegalArgumentException(OAuthError.message("Session refresh",reply.status,reply.body));
            }
            saveTokens(reply.body,refresh);token=vault.json("session").getString("access_token");
        }
        return token;
    }
    private Transport.Reply request(String method,String path,String country,String language,String store,String body) throws Exception {
        return requestUrl(method,Protocol.COUPONS+path,country,language,store,body);
    }
    private Transport.Reply requestUrl(String method,String url,String country,String language,String store,String body) throws Exception {
        Protocol.locale(country,language);
        Map<String,String> headers=Protocol.fields("Authorization","Bearer "+access(false),"Country",country,"Accept-Language",language);
        if(!store.isEmpty() && url.equals(Protocol.COUPONS+"v4/promotionslist"))headers.put("Store-Id",store);
        Transport.Reply reply=transport.call(method,url,headers,body,"application/json");
        // Retry only reads. Never automatically repeat an activation after an uncertain result.
        if(reply.status==401 && "GET".equals(method)){
            headers.put("Authorization","Bearer "+access(true));
            reply=transport.call(method,url,headers,body,"application/json");
        }
        if(!reply.ok())throw new IllegalArgumentException("Service request failed (HTTP "+reply.status+"). "+
            (reply.status==401?"Log in again; no change was confirmed.":reply.status==403?"Lidl did not permit this request.":"No change was confirmed. Refresh before retrying."));
        return reply;
    }
    public String list(String country,String language,String store) throws Exception {
        String body=request("GET","v4/promotionslist",country,language,store,null).body;
        Coupon.parse(body);
        vault.json("coupons",new JSONObject().put("body",body).put("saved",System.currentTimeMillis())
            .put("country",country).put("language",language).put("store",store));
        return body;
    }
    public JSONObject detail(String id,String country,String language,String store) throws Exception {
        return new JSONObject(request("GET","v4/promotionsdetails/"+Protocol.path(id),country,language,store,null).body);
    }
    public void activation(String id,boolean activate,String country,String language,String store) throws Exception {
        vault.delete("coupons");
        request(activate?"POST":"DELETE","v2/promotions/"+Protocol.path(id)+"/activation",country,language,store,activate?"{\"articleSelection\":[]}":null);
    }
    public String loyalty(String country,String language) throws Exception {
        String id=LoyaltyCard.parse(requestUrl("GET",Protocol.PROFILE+"v1/"+country+"/loyalty",country,language,"",null).body);
        vault.json("loyalty",new JSONObject().put("id",id).put("country",country).put("saved",System.currentTimeMillis()));
        return id;
    }
    public void select(CouponDetail detail,boolean override,Map<String,String> choices,String country,String language,String store) throws Exception {
        detail.available(System.currentTimeMillis());
        if(override!=detail.activated)throw new IllegalArgumentException("Coupon activation state changed. Refresh first.");
        String body=detail.selection(choices);
        // Invalidate before sending: a timeout may still mean the server committed the change.
        vault.delete("coupons");
        request(override?"PATCH":"POST",override?"v4/overrides/discount/"+Protocol.path(detail.id):
            "v2/promotions/"+Protocol.path(detail.id)+"/activation",country,language,store,body);
    }
    public void signOut() throws Exception {vault.clear();}
}
