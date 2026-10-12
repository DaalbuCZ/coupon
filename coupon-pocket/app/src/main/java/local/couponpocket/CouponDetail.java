package local.couponpocket;

import org.json.JSONArray;
import org.json.JSONObject;
import java.time.OffsetDateTime;
import java.util.*;

/** Observed coupon groups; choice identifiers always come from server details. */
public final class CouponDetail {
    public final JSONObject raw;
    public final String id,title;
    public final boolean activated;
    public final List<Group> groups=new ArrayList<>();
    public static final class Article {
        public final String id,title,image; public final boolean selected;
        Article(JSONObject a){image=ImageUrl.from(a);id=a.optString("id");title=a.optString("title",id);selected=a.optBoolean("selected");}
    }
    public static final class Group {
        public final String id,title; public final List<Article> articles=new ArrayList<>();
        Group(JSONObject g) throws Exception {
            id=g.getString("id");title=g.optString("title","Choose a product");
            JSONArray list=g.getJSONArray("articles");Set<String> ids=new HashSet<>();
            for(int i=0;i<list.length();i++){
                Article a=new Article(list.getJSONObject(i));
                if(a.id.isEmpty()||!ids.add(a.id))throw new IllegalArgumentException("Unsupported product choices.");
                articles.add(a);
            }
            if(id.isEmpty()||articles.isEmpty())throw new IllegalArgumentException("Unsupported product group.");
        }
    }
    public CouponDetail(JSONObject d,String expectedId) throws Exception {
        raw=d;id=d.getString("id");title=d.optString("title","Coupon");activated=d.getBoolean("isActivated");
        if(!id.equals(expectedId))throw new SecurityException("Coupon details do not match the requested coupon.");
        JSONArray list=d.optJSONArray("groups");
        if(d.has("groups")&&!d.isNull("groups")&&list==null)throw new IllegalArgumentException("Unsupported product group format.");
        Set<String> ids=new HashSet<>();
        if(list!=null)for(int i=0;i<list.length();i++){
            Group group=new Group(list.getJSONObject(i));if(!ids.add(group.id))throw new IllegalArgumentException("Duplicate product group.");groups.add(group);
        }
    }
    public void available(long now) {
        if(raw.optBoolean("isRedeemed"))throw new IllegalArgumentException("This coupon has already been redeemed.");
        if(raw.optBoolean("isProcessing"))throw new IllegalArgumentException("This coupon is processing. Refresh later.");
        JSONObject a=raw.optJSONObject("availability");
        if(a!=null&&a.optBoolean("apologizeStatus"))throw new IllegalArgumentException("This coupon is currently unavailable. Check its terms.");
        JSONObject v=raw.optJSONObject("validity");
        if(v!=null){
            checkTime(v.optString("start"),now,true);checkTime(v.optString("end"),now,false);
        }
    }
    private static void checkTime(String value,long now,boolean start) {
        if(value.isEmpty())return;
        final long time;
        try{time=OffsetDateTime.parse(value).toInstant().toEpochMilli();}
        catch(Exception e){throw new IllegalArgumentException("Cannot verify coupon validity. Refresh or use Lidl Plus.");}
        if(start?now<time:now>time)throw new IllegalArgumentException(start?"This coupon is not valid yet.":"This coupon has expired.");
    }
    public String selection(Map<String,String> choices) throws Exception {
        if(choices.size()!=groups.size())throw new IllegalArgumentException("Choose one product in every group.");
        JSONArray selected=new JSONArray();
        for(Group g:groups){
            String id=choices.get(g.id);boolean found=false;
            for(Article a:g.articles)if(a.id.equals(id))found=true;
            if(!found)throw new IllegalArgumentException("Choose one product in every group.");
            selected.put(new JSONObject().put("groupId",g.id).put("articleId",id));
        }
        return new JSONObject().put("articleSelection",selected).toString();
    }
    public String terms(){
        StringBuilder out=new StringBuilder(raw.optString("description"));
        for(String key:new String[]{"conditions","characteristics"}){
            JSONObject object=raw.optJSONObject(key);
            if(object!=null)append(out,object);
            JSONArray list=raw.optJSONArray(key);
            if(list!=null)for(int i=0;i<list.length();i++){object=list.optJSONObject(i);if(object!=null)append(out,object);}
        }
        JSONObject availability=raw.optJSONObject("availability");if(availability!=null){
            String message=availability.optString("text");if(!message.isEmpty())out.append("\n\n").append(availability.optString("title")).append("\n").append(message);
        }
        JSONArray articles=raw.optJSONArray("articles");if(articles!=null)for(int i=0;i<articles.length();i++){
            JSONObject a=articles.optJSONObject(i);if(a!=null)out.append("\n\n").append(a.optString("description"));
        }
        return out.length()==0?"No additional terms returned.":out.toString();
    }
    private static void append(StringBuilder out,JSONObject o){out.append("\n\n").append(o.optString("title")).append("\n").append(o.optString("description"));}
}
