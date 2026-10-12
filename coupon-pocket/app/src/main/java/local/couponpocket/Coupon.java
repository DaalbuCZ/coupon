package local.couponpocket;

import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.FormatStyle;

public final class Coupon {
    public final String id,title,section,expiry;
    public final boolean activated,processing;
    public final JSONObject raw;
    Coupon(JSONObject p,String section) {
        raw=p;id=p.optString("id","");title=p.optString("title","Coupon");this.section=section;
        activated=p.optBoolean("isActivated",false);processing=p.optBoolean("isProcessing",false);
        JSONObject validity=p.optJSONObject("validity");
        expiry=validity==null?p.optString("endValidityDate",""):validity.optString("end",validity.optString("endDate",""));
    }
    public String validUntil(Locale locale){
        if(expiry.isEmpty())return "";
        LocalDate date;
        try{date=OffsetDateTime.parse(expiry).toLocalDate();}
        catch(java.time.format.DateTimeParseException e){
            try{date=LocalDate.parse(expiry);}
            catch(java.time.format.DateTimeParseException invalid){return "Expiry date unavailable";}
        }
        // Keep the server's validity calendar date rather than shifting it to the phone's timezone.
        return "Valid until "+date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale));
    }
    public static String discountTitle(JSONObject coupon){
        JSONObject discount=coupon.optJSONObject("discount");if(discount==null)return "";
        String title=discount.optString("title").trim();
        return !title.isEmpty()&&discount.optBoolean("hasAsterisk")&&!title.endsWith("*")?title+"*":title;
    }
    public static String discountDescription(JSONObject coupon){
        JSONObject discount=coupon.optJSONObject("discount");return discount==null?"":discount.optString("description").trim();
    }
    public static List<Coupon> parse(String body) throws Exception {
        JSONObject root=new JSONObject(body);JSONArray sections=root.optJSONArray("sections");
        if(sections==null)throw new IllegalArgumentException("Coupon response format changed (missing sections).");
        List<Coupon> coupons=new ArrayList<>();
        for(int i=0;i<sections.length();i++){
            JSONObject section=sections.getJSONObject(i);JSONArray ps=section.optJSONArray("promotions");
            if(ps==null)continue;
            for(int j=0;j<ps.length();j++){
                Coupon c=new Coupon(ps.getJSONObject(j),section.optString("name","Coupons"));
                if(c.id.isEmpty())throw new IllegalArgumentException("Coupon is missing its identifier.");
                coupons.add(c);
            }
        }
        return coupons;
    }
}
