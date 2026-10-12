package local.couponpocket;

import org.json.JSONObject;
import org.json.JSONArray;
import java.util.*;
import java.io.IOException;
import java.nio.file.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import io.nayuki.qrcodegen.QrCode;

public final class ClientTest {
    static int checks;
    static final String FIXTURE="{\"sections\":[{\"name\":\"Weekly\",\"promotions\":[{\"id\":\"coupon/one\",\"title\":\"Coffee\",\"isActivated\":true},{\"id\":\"two\",\"title\":\"Bread\",\"isActivated\":false,\"isProcessing\":true}]}]}";
    interface Throwing {void run() throws Exception;}
    static void ok(boolean condition,String message){checks++;if(!condition)throw new AssertionError(message);}
    static void fails(Throwing work,String message) throws Exception {checks++;try{work.run();}catch(Exception expected){return;}throw new AssertionError(message);}
    static class Memory implements Storage {
        Map<String,String> saved=new HashMap<>();
        public JSONObject json(String name) throws Exception{return new JSONObject(saved.getOrDefault(name,"{}"));}
        public void json(String name,JSONObject data){saved.put(name,data.toString());}
        public void delete(String name){saved.remove(name);}
        public void clear(){saved.clear();}
    }
    static class Fake implements RequestClient {
        static class Call {String method,url,body,type;Map<String,String> headers;Call(String m,String u,Map<String,String> h,String b,String t){method=m;url=u;headers=new HashMap<>(h);body=b;type=t;}}
        List<Call> calls=new ArrayList<>();Deque<Object> replies=new ArrayDeque<>();
        void reply(int status,String body){replies.add(new Transport.Reply(status,body));}
        public Transport.Reply call(String method,String url,Map<String,String> headers,String body,String type) throws Exception {
            Protocol.allow(url);calls.add(new Call(method,url,headers,body,type));
            Object result=replies.remove();if(result instanceof Exception)throw (Exception)result;return (Transport.Reply)result;
        }
    }
    static JSONObject tokens(String access,String refresh,long expiry) throws Exception {
        return new JSONObject().put("access_token",access).put("refresh_token",refresh).put("expires",expiry);
    }
    public static void main(String[] args) throws Exception {
        ok(Protocol.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk").equals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"),"RFC 7636 PKCE test vector");
        String random=Protocol.random();ok(random.length()==43&&!random.equals(Protocol.random()),"Secure random state/verifier");
        for(String url:new String[]{Protocol.ACCOUNT+"connect/token",Protocol.COUPONS+"v4/promotionslist"}){Protocol.allow(url);checks++;}
        for(String url:new String[]{"http://coupons.lidlplus.com/","https://mobile-otel.lidlplus.com/","https://accounts.lidl.com.evil.test/","https://accounts.lidl.com@evil.test/","https://evil.test@accounts.lidl.com/","https://accounts.lidl.com:444/","https://accounts.lidl.com/#fragment","file:///tmp/token","https://accounts.lidl.com./"})fails(()->Protocol.allow(url),"Reject external or unsafe destination "+url);
        ok(Protocol.callback(Protocol.CALLBACK+"?code=x"),"Expected redirect URI accepted");
        for(String url:new String[]{"https://callback?code=x","com.lidlplus.app://callback/evil?code=x","com.lidlplus.app://user@callback?code=x","com.lidlplus.app://callback:42?code=x","com.lidlplus.app://callback#code=x"})ok(!Protocol.callback(url),"Reject unexpected redirect shape");
        long now=System.currentTimeMillis();
        Map<String,String> parsed=Protocol.callbackFields(Protocol.CALLBACK+"?state=expected&code=a%2Bb","expected",now,now);
        ok(parsed.get("code").equals("a+b"),"Decode authorization code once");
        fails(()->Protocol.callbackFields(Protocol.CALLBACK+"?state=wrong&code=x","expected",now,now),"Reject wrong OAuth state");
        fails(()->Protocol.callbackFields(Protocol.CALLBACK+"?state=expected&state=expected&code=x","expected",now,now),"Reject duplicate OAuth state");
        fails(()->Protocol.callbackFields(Protocol.CALLBACK+"?state=expected&code=x","expected",now-600001,now),"Reject expired state");
        fails(()->Protocol.callbackFields(Protocol.CALLBACK+"?state=expected&code=x","expected",now+1,now),"Reject future state");
        fails(()->Protocol.callbackFields(Protocol.CALLBACK+"?state=%XX&code=x","expected",now,now),"Reject malformed encoding");
        Protocol.locale("CZ","cs-CZ");checks++;
        fails(()->Protocol.locale("CZ\r\nX: injected","cs-CZ"),"Reject header injection");
        ok(Protocol.path("coupon/one ?").equals("coupon%2Fone%20%3F"),"Escape coupon identifier as one path component");
        List<Coupon> coupons=Coupon.parse(FIXTURE);
        ok(coupons.size()==2&&coupons.get(0).activated&&coupons.get(1).processing,"Parse section list and activation status");
        fails(()->Coupon.parse("{\"other\":[]}"),"Reject incompatible response schema");
        fails(()->Coupon.parse("{\"sections\":[{\"promotions\":[{\"title\":\"Missing ID\"}]}]}"),"Reject coupon without identifier");
        Coupon dated=new Coupon(new JSONObject().put("id","date").put("validity",new JSONObject().put("end","2026-10-12T00:30:00+02:00")),"Weekly");
        ok(dated.validUntil(Locale.US).equals("Valid until Oct 12, 2026"),"Readable expiry date preserves server calendar day near midnight");
        Coupon dateOnly=new Coupon(new JSONObject().put("id","date").put("endValidityDate","2026-10-12"),"Weekly");
        ok(dateOnly.validUntil(Locale.US).equals("Valid until Oct 12, 2026"),"Support ISO date-only validity");
        ok(!dated.validUntil(Locale.forLanguageTag("cs-CZ")).contains("T00")&&!dated.validUntil(Locale.forLanguageTag("cs-CZ")).equals(dated.validUntil(Locale.US)),"Format dates in selected language without timestamp");
        ok(new Coupon(new JSONObject().put("id","date"),"Weekly").validUntil(Locale.US).isEmpty(),"Hide missing validity rather than inventing date");
        ok(new Coupon(new JSONObject().put("id","date").put("endValidityDate","unrecognized"),"Weekly").validUntil(Locale.US).equals("Expiry date unavailable"),"Unreadable expiry gets a clear fallback");
        JSONObject percentage=new JSONObject().put("discount",new JSONObject().put("title","-20%").put("description","On fruit").put("hasAsterisk",true));
        ok(Coupon.discountTitle(percentage).equals("-20%*")&&Coupon.discountDescription(percentage).equals("On fruit"),"Use explicit server discount title and condition asterisk");
        percentage.getJSONObject("discount").put("title","-20%*");
        ok(Coupon.discountTitle(percentage).equals("-20%*"),"Preserve existing asterisk without duplication");
        JSONObject money=new JSONObject().put("discount",new JSONObject().put("title","-30 Kč").put("description","On coffee"));
        ok(Coupon.discountTitle(money).equals("-30 Kč"),"Preserve supplied money amount and currency without guessing");
        ok(Coupon.discountTitle(new JSONObject()).isEmpty()&&Coupon.discountDescription(new JSONObject()).isEmpty(),"Missing discount does not invent an amount");
        Memory memory=new Memory();Fake fake=new Fake();Api api=new Api(memory,fake);
        String login=api.beginLogin("CZ","cs-CZ");
        ok(login.startsWith(Protocol.ACCOUNT+"connect/authorize?")&&login.contains("code_challenge_method=S256"),"Browser authorization with PKCE");
        String state=memory.json("pending").getString("state");
        fails(()->api.finishLogin(Protocol.CALLBACK+"?state=wrong&code=x"),"Invalid state cannot exchange token");
        ok(fake.calls.isEmpty(),"No network on rejected callback");
        fake.reply(200,"{\"access_token\":\"access-one\",\"refresh_token\":\"refresh-one\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"id_token\":\"not-stored\"}");
        api.finishLogin(Protocol.CALLBACK+"?state="+state+"&code=auth-code");
        ok(api.signedIn()&&!memory.saved.containsKey("pending"),"Login saves session and consumes pending state");
        ok(!memory.saved.get("session").contains("id_token"),"Do not retain unused identity token");
        ok(fake.calls.get(0).body.contains("code_verifier=")&&!fake.calls.get(0).body.contains("client_id=")&&!fake.calls.get(0).body.contains("client_secret"),"Original token form uses PKCE with client authentication in header");
        String clientAuth="Basic "+Base64.getEncoder().encodeToString("LidlPlusNativeClient:secret".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
        ok(fake.calls.get(0).headers.get("Authorization").equals(clientAuth),"Match original token client authentication");
        fails(()->api.finishLogin(Protocol.CALLBACK+"?state="+state+"&code=auth-code"),"Reject callback replay");
        ok(fake.calls.size()==1,"Replay does not reach token server");
        fake.reply(200,FIXTURE);api.list("CZ","cs-CZ","");
        Fake.Call list=fake.calls.get(1);
        ok(list.url.equals("https://coupons.lidlplus.com/app/api/v4/promotionslist"),"List URL includes the actual factory base path, not just host");
        ok(list.headers.get("Authorization").equals("Bearer access-one"),"Account token attached to coupon read");
        ok(!list.headers.containsKey("Segment-Ids")&&!list.headers.containsKey("Store-Id")&&!list.headers.containsKey("DeviceId"),"Omit optional identity/segmentation fields");
        ok(memory.saved.containsKey("coupons"),"Validated coupon data cached");
        fake.reply(204,"");api.activation("coupon/one",true,"CZ","cs-CZ","");
        Fake.Call mutation=fake.calls.get(2);
        ok(mutation.method.equals("POST")&&mutation.url.equals("https://coupons.lidlplus.com/app/api/v2/promotions/coupon%2Fone/activation"),"Correct activation verb and escaped ID");
        ok(mutation.type.equals("application/json")&&new JSONObject(mutation.body).getJSONArray("articleSelection").length()==0,"Basic activation sends observed empty selection JSON with its media type");
        ok(!mutation.headers.containsKey("Action-Location"),"Omit optional action attribution");
        ok(!memory.saved.containsKey("coupons"),"Invalidate cache after successful mutation");
        fake.reply(415,"");int rejectedMediaBefore=fake.calls.size();
        fails(()->api.activation("two",true,"CZ","cs-CZ",""),"Surface rejected media type");
        ok(fake.calls.size()==rejectedMediaBefore+1,"Never retry activation automatically after 415");
        fake.reply(401,"");int before=fake.calls.size();
        fails(()->api.activation("two",false,"CZ","cs-CZ",""),"Report rejected mutation");
        ok(fake.calls.size()==before+1,"Never automatically replay mutation on 401");
        Fake.Call deactivate=fake.calls.get(fake.calls.size()-1);
        ok(deactivate.method.equals("DELETE")&&deactivate.url.equals("https://coupons.lidlplus.com/app/api/v2/promotions/two/activation"),"Deactivation URL includes the same factory base path");
        fake.replies.add(new IOException("Simulated timeout"));before=fake.calls.size();
        fails(()->api.activation("two",true,"CZ","cs-CZ",""),"Report uncertain mutation");
        ok(fake.calls.size()==before+1,"Never automatically replay uncertain mutation");
        fake.reply(401,"");fake.reply(200,"{\"access_token\":\"access-two\",\"refresh_token\":\"refresh-two\",\"token_type\":\"Bearer\",\"expires_in\":3600}");fake.reply(200,FIXTURE);
        api.list("CZ","cs-CZ","");
        Fake.Call refreshRequest=fake.calls.get(fake.calls.size()-2);
        ok(refreshRequest.headers.get("Authorization").equals(clientAuth)&&!refreshRequest.body.contains("client_id="),"Refresh uses same observed client authentication");
        ok(memory.json("session").getString("refresh_token").equals("refresh-two"),"Rotate refresh token");
        ok(fake.calls.get(fake.calls.size()-1).headers.get("Authorization").equals("Bearer access-two"),"Read retry uses refreshed token");
        memory.json("session",tokens("old","refresh-two",now-100));fake.reply(400,"");
        fails(()->api.list("CZ","cs-CZ",""),"Invalid refresh fails");
        ok(!api.signedIn()&&!memory.saved.containsKey("coupons"),"Clear invalid session and cache");
        memory.json("session",tokens("store-token","store-refresh",now+3600000));fake.reply(200,FIXTURE);api.list("CZ","cs-CZ","123");
        ok(fake.calls.get(fake.calls.size()-1).headers.get("Store-Id").equals("123"),"Store context sent on observed list route");
        fake.reply(200,"{\"id\":\"two\"}");api.detail("two","CZ","cs-CZ","123");
        ok(fake.calls.get(fake.calls.size()-1).url.equals("https://coupons.lidlplus.com/app/api/v4/promotionsdetails/two"),"Detail URL includes actual coupon base path");
        ok(!fake.calls.get(fake.calls.size()-1).headers.containsKey("Store-Id"),"Do not add unobserved store header to details");
        // Loyalty endpoint and scalar handling: never encode a token or whole response object.
        Protocol.allow(Protocol.PROFILE+"v1/CZ/loyalty");checks++;
        for(String url:new String[]{"https://profile.lidlplus.com/api/v1/CZ/loyalty?event=x","https://profile.lidlplus.com/api/v1/profile/salesforceid","https://profile.lidlplus.com/api/v1/CZ/loyalty/extra","https://profile.lidlplus.com/api/v1/%43Z/loyalty","https://profile.lidlplus.com.evil.test/api/v1/CZ/loyalty"})
            fails(()->Protocol.allow(url),"Limit profile host to observed loyalty read");
        ok(LoyaltyCard.parse("\"001234567890\"").equals("001234567890"),"JSON string loyalty ID preserves zeroes");
        ok(LoyaltyCard.parse("001234567890").equals("001234567890"),"Plain loyalty ID preserves zeroes");
        for(String body:new String[]{"", "null", "{}", "[]", "123,456", "\"\"", "\"abc\\nxyz\"", "\"abc\",\"def\""})
            fails(()->LoyaltyCard.parse(body),"Reject malformed loyalty payload");
        memory.json("session",tokens("card-token","card-refresh",now+3600000));
        fake.reply(200,"\"001234567890\"");
        ok(api.loyalty("CZ","cs-CZ").equals("001234567890"),"Fetch server-issued loyalty ID");
        Fake.Call card=fake.calls.get(fake.calls.size()-1);
        ok(card.method.equals("GET")&&card.url.equals(Protocol.PROFILE+"v1/CZ/loyalty"),"Exact account loyalty endpoint");
        ok(card.headers.get("Authorization").equals("Bearer card-token")&&!card.headers.containsKey("Store-Id"),"Minimal authenticated card read");
        ok(memory.json("loyalty").getString("country").equals("CZ"),"Bind cached loyalty ID to region");
        fake.reply(200,"{\"loyaltyId\":\"unexpected-shape\"}");
        fails(()->api.loyalty("CZ","cs-CZ"),"Reject unobserved card response shape");
        ok(memory.json("loyalty").getString("id").equals("001234567890"),"Malformed response cannot overwrite saved card");
        JSONObject product=new JSONObject("{\"id\":\"meal/one\",\"title\":\"Meal deal\",\"isActivated\":false,\"description\":\"Lunch\",\"conditions\":{\"title\":\"Terms\",\"description\":\"Buy both products\"},\"groups\":[{\"id\":\"drink\",\"title\":\"Drink\",\"articles\":[{\"id\":\"coffee\",\"title\":\"Coffee\",\"selected\":true},{\"id\":\"tea\",\"title\":\"Tea\"}]},{\"id\":\"food\",\"articles\":[{\"id\":\"bread\",\"title\":\"Bread\"}]}]}");
        CouponDetail detail=new CouponDetail(product,"meal/one");
        ok(detail.groups.size()==2&&detail.groups.get(0).articles.get(0).selected,"Parse product groups and existing selections");
        ok(detail.terms().contains("Buy both products"),"Display coupon conditions");
        fails(()->new CouponDetail(product,"different"),"Reject mismatched detail identifier");
        fails(()->new CouponDetail(new JSONObject(product.toString()).put("groups",new JSONObject()),"meal/one"),"Reject unknown group schema before activation");
        JSONObject duplicate=new JSONObject(product.toString());duplicate.getJSONArray("groups").put(duplicate.getJSONArray("groups").getJSONObject(0));
        fails(()->new CouponDetail(duplicate,"meal/one"),"Reject duplicate choice groups");
        Map<String,String> choices=Protocol.fields("drink","tea","food","bread");
        JSONArray selected=new JSONObject(detail.selection(choices)).getJSONArray("articleSelection");
        ok(selected.length()==2&&selected.getJSONObject(0).getString("groupId").equals("drink")&&selected.getJSONObject(0).getString("articleId").equals("tea"),"Observed selection body structure");
        fails(()->detail.selection(Protocol.fields("drink","tea")),"Every group must have a choice");
        fails(()->detail.selection(Protocol.fields("drink","invented","food","bread")),"Reject invented article IDs");
        fails(()->detail.selection(Protocol.fields("drink","tea","food","bread","extra","x")),"Reject extra group IDs");
        detail.available(now);checks++;
        for(String flag:new String[]{"isRedeemed","isProcessing"}){
            JSONObject blocked=new JSONObject(product.toString()).put(flag,true);
            fails(()->new CouponDetail(blocked,"meal/one").available(now),"Block "+flag);
        }
        JSONObject unavailable=new JSONObject(product.toString()).put("availability",new JSONObject().put("apologizeStatus",true));
        fails(()->new CouponDetail(unavailable,"meal/one").available(now),"Block unavailable coupon");
        for(String validity:new String[]{"{\"end\":\"2000-01-01T00:00:00Z\"}","{\"start\":\"2100-01-01T00:00:00Z\"}","{\"end\":\"changed-format\"}"}){
            JSONObject blocked=new JSONObject(product.toString()).put("validity",new JSONObject(validity));
            fails(()->new CouponDetail(blocked,"meal/one").available(now),"Block expired, future or unknown validity");
        }
        fake.reply(204,"");api.select(detail,false,choices,"CZ","cs-CZ","");
        Fake.Call activation=fake.calls.get(fake.calls.size()-1);
        ok(activation.method.equals("POST")&&activation.url.equals("https://coupons.lidlplus.com/app/api/v2/promotions/meal%2Fone/activation")&&new JSONObject(activation.body).getJSONArray("articleSelection").length()==2,"Activate with chosen products");
        CouponDetail activeDetail=new CouponDetail(new JSONObject(product.toString()).put("isActivated",true),"meal/one");
        fake.reply(204,"");api.select(activeDetail,true,choices,"CZ","cs-CZ","");
        Fake.Call override=fake.calls.get(fake.calls.size()-1);
        ok(override.method.equals("PATCH")&&override.url.equals("https://coupons.lidlplus.com/app/api/v4/overrides/discount/meal%2Fone"),"Change existing choices through observed override endpoint");
        before=fake.calls.size();fails(()->api.select(activeDetail,false,choices,"CZ","cs-CZ",""),"Reject mismatched activation state");
        ok(fake.calls.size()==before,"Rejected selection state makes no network call");
        JSONObject changed=new JSONObject(product.toString());changed.getJSONArray("groups").getJSONObject(0).getJSONArray("articles").remove(1);
        CouponDetail changedDetail=new CouponDetail(changed,"meal/one");
        before=fake.calls.size();fails(()->api.select(changedDetail,false,choices,"CZ","cs-CZ",""),"Revalidate selected articles when server groups change");
        ok(fake.calls.size()==before,"Removed article makes no mutation call");
        memory.json("coupons",new JSONObject().put("body",FIXTURE));fake.replies.add(new IOException("Simulated uncertainty"));before=fake.calls.size();
        fails(()->api.select(detail,false,choices,"CZ","cs-CZ",""),"Report uncertain selection change");
        ok(fake.calls.size()==before+1&&!memory.saved.containsKey("coupons"),"No mutation replay; uncertain result invalidates persisted cache");
        api.beginLogin("CZ","cs-CZ");String nextState=memory.json("pending").getString("state");
        fake.reply(200,"{\"access_token\":\"new-account\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
        api.finishLogin(Protocol.CALLBACK+"?state="+nextState+"&code=new-code");
        ok(!memory.saved.containsKey("loyalty"),"New account login clears previous loyalty card");
        ok(ImageUrl.from(new JSONObject("{\"image\":{\"url\":\"https://cdn.example.test/coffee.png\",\"altText\":\"Coffee\"}}")).equals("https://cdn.example.test/coffee.png"),"Observed single-image model URL");
        ok(ImageUrl.from(new JSONObject("{\"images\":[{\"url\":\"https://cdn.example.test/detail.png\"}]}" )).equals("https://cdn.example.test/detail.png"),"Observed detail-image list URL");
        ok(ImageUrl.from(new JSONObject()).isEmpty(),"Coupons without images need no image request");
        ImageUrl.allow("https://cdn.example.test/photo.webp?size=small");checks++;
        for(String url:new String[]{"http://cdn.example.test/photo.png","file:///tmp/card","https://user:password@cdn.example.test/photo","https://localhost/photo","https://host.local/photo","https://cdn.example.test:444/photo","https://cdn.example.test/photo#token"})
            fails(()->ImageUrl.allow(url),"Reject unsafe image URL");
        for(String address:new String[]{"127.0.0.1","10.0.0.1","192.168.1.1","169.254.1.1","100.64.0.1","0.0.0.0","198.18.1.1","224.0.0.1","::1","fc00::1","fe80::1"})
            fails(()->ImageUrl.publicAddress(java.net.InetAddress.getByName(address)),"Reject local image destination "+address);
        ImageUrl.publicAddress(java.net.InetAddress.getByAddress(new byte[]{8,8,8,8}));checks++;
        // Authentication failures preserve state validation and never replay one-use codes.
        api.beginLogin("CZ","cs-CZ");String rejectedState=memory.json("pending").getString("state");
        fake.reply(400,"{\"error\":\"invalid_client\",\"error_description\":\"private@example.test token=secret-user-token\"}");before=fake.calls.size();
        try{api.finishLogin(Protocol.CALLBACK+"?state="+rejectedState+"&code=rejected-code");throw new AssertionError("Expected failed exchange");}
        catch(IllegalArgumentException e){ok(e.getMessage().contains("invalid_client")&&!e.getMessage().contains("private@example.test")&&!e.getMessage().contains("secret-user-token"),"Display only safe OAuth error code");}
        ok(fake.calls.size()==before+1&&!memory.saved.containsKey("pending"),"Failed token exchange consumes state and is not retried");
        fails(()->api.finishLogin(Protocol.CALLBACK+"?state="+rejectedState+"&code=rejected-code"),"Rejected exchange code cannot be replayed");
        for(String code:new String[]{"invalid_grant","invalid_request","invalid_scope","unauthorized_client","unsupported_grant_type","access_denied","temporarily_unavailable","server_error"}){
            String message=OAuthError.message("Login exchange",400,new JSONObject().put("error",code).put("error_description","private-token").toString());
            ok(message.contains(code)&&!message.contains("private-token"),"Recognized OAuth failure "+code);
        }
        for(String body:new String[]{"<html>private-token</html>","{\"error\":\"private-token\"}","{\"error\":{\"token\":\"private-token\"}}"})
            ok(!OAuthError.message("Login exchange",400,body).contains("private-token"),"Unknown responses cannot leak server data");
        api.signOut();ok(memory.saved.isEmpty(),"Logout erases storage");
        // Export actual library output for independent OpenCV decoding.
        Files.createDirectories(Paths.get("build/test-output"));
        String[] payloads={"1234567890123456","TEST-CARD:cz:coffee-42"};
        for(int i=0;i<payloads.length;i++){
            QrCode qr=QrCode.encodeText(payloads[i],QrCode.Ecc.MEDIUM);int scale=8,border=4,size=(qr.size+2*border)*scale;
            BufferedImage image=new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
            for(int y=0;y<size;y++)for(int x=0;x<size;x++)image.setRGB(x,y,qr.getModule(x/scale-border,y/scale-border)?0x000000:0xFFFFFF);
            ImageIO.write(image,"png",Paths.get("build/test-output/qr-"+i+".png").toFile());
        }
        System.out.println("PASS: "+checks+" protocol, privacy, parser and API behavior checks; no live network requests.");
    }
}
