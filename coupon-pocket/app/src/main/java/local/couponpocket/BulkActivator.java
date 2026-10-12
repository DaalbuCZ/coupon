package local.couponpocket;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Confirmed, serial batch. Fresh eligibility per coupon, no mutation retries or invented choices. */
public final class BulkActivator {
    public static final class Result {public int activated,skipped,choices;public boolean cancelled;public Exception failure;}
    private final Api api;
    public BulkActivator(Api api){this.api=api;}
    public Result run(List<Coupon> confirmed,boolean hideOnline,String country,String language,String store,BooleanSupplier cancelled){
        Result result=new Result();Set<String> ids=new LinkedHashSet<>();
        for(Coupon c:confirmed)if(!c.activated&&!c.processing&&(!hideOnline||!c.onlineShop()))ids.add(c.id);
        if(ids.isEmpty())return result;
        try{
            if(cancelled.getAsBoolean()){result.cancelled=true;return result;}
            List<Coupon> fresh=Coupon.parse(api.list(country,language,store));Set<String> seen=new HashSet<>();
            for(Coupon c:fresh){
                if(!ids.contains(c.id)||!seen.add(c.id))continue;
                if(cancelled.getAsBoolean()){result.cancelled=true;break;}
                if(c.activated||c.processing||(hideOnline&&c.onlineShop())){result.skipped++;continue;}
                CouponDetail d=new CouponDetail(api.detail(c.id,country,language,store),c.id);
                if(d.activated||(hideOnline&&new Coupon(d.raw,c.section).onlineShop())){result.skipped++;continue;}
                try{d.available(System.currentTimeMillis());}catch(IllegalArgumentException unavailable){result.skipped++;continue;}
                if(!d.groups.isEmpty()){result.skipped++;result.choices++;continue;}
                if(cancelled.getAsBoolean()){result.cancelled=true;break;}
                api.activation(d.id,true,country,language,store);result.activated++;
            }
            if(!result.cancelled)result.skipped+=ids.size()-seen.size();
        }catch(Exception e){result.failure=e;}
        return result;
    }
}
