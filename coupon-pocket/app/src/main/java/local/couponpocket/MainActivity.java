package local.couponpocket;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.*;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public final class MainActivity extends Activity {
    private static final int BG=Color.rgb(242,244,246),INK=Color.rgb(36,42,48),GREEN=Color.rgb(43,53,62),MUTED=Color.rgb(97,105,113);
    private App app;
    private LinearLayout root,content,nav,floating;
    private ProgressBar progress,pullProgress;
    private Button bulkButton,shopButton;
    private final List<Button> navButtons=new ArrayList<>();
    private boolean hideOnline=false;
    private java.util.concurrent.atomic.AtomicBoolean batchCancel;
    private BulkActivator.Result batchResult;
    private TextView status,couponNotice;
    private ScrollView scroll;
    private String renderedPage="";
    private boolean couponListVisible=false;
    private final List<CouponRow> rows=new ArrayList<>();
    private static final class CouponRow {
        Coupon coupon;TextView tag,title,discount,discountDescription,expiry,processing;Button change;
    }
    private boolean busy=false,demo=false,signedIn=false,stale=true,onlyActive=false,imagesEnabled=true;
    private String country="CZ",language="cs-CZ",store="",page="coupons";
    private List<Coupon> coupons=new ArrayList<>();
    private byte[] cardImage;
    private String cardText="",loyaltyId="",cardNotice="";
    private long cacheTime;
    interface Work {void run() throws Exception;}

    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);app=(App)getApplication();
        if(saved!=null){demo=saved.getBoolean("demo");page=saved.getString("page","coupons");onlyActive="activated".equals(page);}
        shell();
        job("Opening your wallet…",()->{
            JSONObject settings=app.vault.json("settings");
            imagesEnabled=settings.optBoolean("images",true);hideOnline=settings.optBoolean("hideOnline",false);
            country=settings.optString("country","CZ");language=settings.optString("language","cs-CZ");store=settings.optString("store","");
            signedIn=app.api.signedIn();loadCard();loadCache();
        },()->{
            if(getIntent().getData()!=null){consumeCallback(getIntent().getData());return;}
            if(demo)preview();else render();
        });
    }
    @Override protected void onSaveInstanceState(Bundle out){super.onSaveInstanceState(out);out.putBoolean("demo",demo);out.putString("page",page);out.putBoolean("active",onlyActive);}
    @Override protected void onStop(){super.onStop();if(batchCancel!=null)batchCancel.set(true);}
    private boolean couponPage(){return "coupons".equals(page)||"activated".equals(page);}
    private void navigate(String next){page=next;onlyActive="activated".equals(page);render();}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);if(intent.getData()!=null)consumeCallback(intent.getData());}
    private void consumeCallback(Uri uri){
        getIntent().setData(null);
        if(busy){app.worker.execute(()->runOnUiThread(()->{if(!isDestroyed())consumeCallback(uri);}));return;}
        job("Completing login…",()->{app.api.finishLogin(uri.toString());app.images.clear();signedIn=true;demo=false;coupons.clear();loadCard();},()->{render();refresh();});
    }
    private void shell(){
        root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(BG);setContentView(root);
        root.setOnApplyWindowInsetsListener((v,insets)->{root.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);header.setPadding(dp(14),dp(5),dp(14),dp(5));root.addView(header);
        TextView brand=text("Coupon Pocket",13,INK);brand.setTypeface(null,Typeface.BOLD);header.addView(brand,new LinearLayout.LayoutParams(0,dp(28),1));
        brand.setGravity(Gravity.CENTER_VERTICAL);brand.setContentDescription("Coupon Pocket. Tap to refresh coupons.");brand.setOnClickListener(v->{if(!busy&&couponPage()&&signedIn)refresh();});
        status=text("",12,MUTED); // Task labels are accessible through the small progress indicator, not a permanent banner.
        progress=new ProgressBar(this);header.addView(progress,new LinearLayout.LayoutParams(dp(20),dp(20)));progress.setVisibility(View.INVISIBLE);
        FrameLayout viewport=new FrameLayout(this);root.addView(viewport,new LinearLayout.LayoutParams(-1,0,1));
        scroll=new RefreshScroll(this,new RefreshScroll.Listener(){
            public boolean allowed(){return !busy&&couponPage()&&(signedIn||demo);}
            public void pull(float distance){content.setTranslationY(Math.min(dp(56),distance*.35f));pullProgress.setVisibility(distance>0?View.VISIBLE:View.GONE);}
            public void refresh(){MainActivity.this.refresh();}
        });scroll.setFillViewport(true);viewport.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
        content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);scroll.addView(content);
        pullProgress=new ProgressBar(this);FrameLayout.LayoutParams pull=new FrameLayout.LayoutParams(dp(24),dp(24),Gravity.TOP|Gravity.CENTER_HORIZONTAL);pull.topMargin=dp(8);viewport.addView(pullProgress,pull);pullProgress.setVisibility(View.GONE);
        floating=new LinearLayout(this);floating.setOrientation(LinearLayout.VERTICAL);floating.setGravity(Gravity.RIGHT);
        FrameLayout.LayoutParams floats=new FrameLayout.LayoutParams(dp(132),-2,Gravity.RIGHT|Gravity.BOTTOM);floats.setMargins(0,0,dp(12),dp(12));viewport.addView(floating,floats);
        bulkButton=button(floating,"Activate all",this::activateAll,true,0);bulkButton.setElevation(dp(5));
        shopButton=button(floating,"≡",this::toggleShop,false,0);shopButton.setTextSize(25);shopButton.setPadding(0,0,0,0);shopButton.setElevation(dp(5));
        LinearLayout.LayoutParams filter=new LinearLayout.LayoutParams(dp(48),dp(48));filter.gravity=Gravity.RIGHT;filter.topMargin=dp(7);floating.removeView(shopButton);floating.addView(shopButton,filter);
        nav=new LinearLayout(this);nav.setGravity(Gravity.CENTER);nav.setPadding(dp(7),dp(3),dp(7),dp(3));nav.setBackgroundColor(Color.WHITE);root.addView(nav);
        navButtons.add(button(nav,"Coupons",()->navigate("coupons"),false,1));
        navButtons.add(button(nav,"Activated",()->navigate("activated"),false,1));
        navButtons.add(button(nav,"Checkout",()->navigate("card"),false,1));
        for(Button button:navButtons){button.setTextSize(12);button.setPadding(dp(3),dp(6),dp(3),dp(6));}
    }
    private void chrome(){
        floating.setVisibility(couponPage()&&(signedIn||demo)?View.VISIBLE:View.GONE);
        bulkButton.setVisibility(!onlyActive?View.VISIBLE:View.GONE);bulkButton.setEnabled(!demo&&!stale&&signedIn&&!bulkCandidates().isEmpty());
        shopButton.setBackground(shape(hideOnline?GREEN:Color.rgb(230,235,238),24));shopButton.setTextColor(hideOnline?Color.WHITE:INK);
        shopButton.setContentDescription(hideOnline?"Show ONLINESHOP coupons":"Hide ONLINESHOP coupons");shopButton.setSelected(hideOnline);shopButton.setText(hideOnline?"✓":"≡");shopButton.setTooltipText(hideOnline?"Show ONLINESHOP coupons":"Hide ONLINESHOP coupons");
        int selected="coupons".equals(page)?0:"activated".equals(page)?1:2;
        for(int i=0;i<navButtons.size();i++)navButtons.get(i).setBackground(shape(i==selected?Color.rgb(230,235,238):Color.WHITE,8));
    }
    private void toggleShop(){
        boolean value=!hideOnline;
        job("Saving filter…",()->{JSONObject saved=app.vault.json("settings");saved.put("hideOnline",value);app.vault.json("settings",saved);hideOnline=value;},this::render);
    }
    private List<Coupon> bulkCandidates(){List<Coupon> list=new ArrayList<>();for(Coupon c:coupons)if(!c.activated&&!c.processing&&(!hideOnline||!c.onlineShop()))list.add(c);return list;}
    private TextView text(String s,int size,int color){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setLineSpacing(dp(3),1);return v;}
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private void paragraph(LinearLayout parent,String s){TextView v=text(s,15,MUTED);v.setPadding(0,dp(7),0,dp(12));parent.addView(v);}
    private void heading(LinearLayout parent,String s){TextView v=text(s,22,INK);v.setTypeface(null,Typeface.BOLD);v.setPadding(0,0,0,dp(8));parent.addView(v);}
    private LinearLayout panel(){LinearLayout p=new LinearLayout(this);p.setOrientation(LinearLayout.VERTICAL);p.setPadding(dp(18),dp(18),dp(18),dp(18));p.setBackground(shape(Color.WHITE,18));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(12);content.addView(p,lp);return p;}
    private Button button(LinearLayout parent,String label,Runnable action,boolean primary,int weight){
        Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setTextSize(14);b.setTextColor(primary?Color.WHITE:GREEN);
        b.setBackground(shape(primary?GREEN:Color.rgb(230,235,238),12));b.setPadding(dp(10),dp(10),dp(10),dp(10));b.setMinHeight(dp(48));
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(weight>0?0:-1,-2,weight);lp.setMargins(dp(3),dp(5),dp(3),dp(5));parent.addView(b,lp);
        b.setEnabled(!busy);b.setOnClickListener(v->{if(!busy)action.run();});return b;
    }
    private void pauseInputs(View view,List<View> paused){
        // Button handlers already ignore taps while busy; keep their appearance and state.
        if((view instanceof EditText||view instanceof CompoundButton)&&view.isEnabled()){
            paused.add(view);view.setEnabled(false);
        }
        if(view instanceof android.view.ViewGroup){
            android.view.ViewGroup group=(android.view.ViewGroup)view;
            for(int i=0;i<group.getChildCount();i++)pauseInputs(group.getChildAt(i),paused);
        }
    }
    private void job(String label,Work work,Runnable done){
        if(busy)return;busy=true;status.setText(label);progress.setContentDescription(label);progress.setVisibility(View.VISIBLE);List<View> paused=new ArrayList<>();pauseInputs(content,paused);
        app.worker.execute(()->{
            Exception error=null;try{work.run();}catch(Exception e){
                error=e;
                try{signedIn=app.api.signedIn();if(!signedIn&&!demo){coupons.clear();stale=true;loyaltyId="";}}catch(Exception ignored){}
            }final Exception result=error;
            runOnUiThread(()->{
                if(isDestroyed()||isFinishing())return;
                busy=false;progress.setVisibility(View.INVISIBLE);for(View view:paused)view.setEnabled(true);
                if(result!=null){if(couponPage())updateCoupons();else render();error(result);}else done.run();
            });
        });
    }
    private void error(Exception e){
        String message;
        if(e instanceof java.net.SocketTimeoutException)message="The request timed out. Its result is uncertain; refresh before trying an activation again.";
        else if(e instanceof java.io.IOException)message="Could not reach the service. Check your connection. If changing a coupon, refresh before retrying.";
        else if(e instanceof IllegalArgumentException || e instanceof SecurityException)message=e.getMessage();
        else message="This client could not read the response or local data. No successful change was confirmed.";
        status.setText("Action could not be completed");
        new AlertDialog.Builder(this).setTitle("Could not complete action").setMessage(message).setPositiveButton("Close",null).show();
    }
    private void summary(){chrome();}
    private void render(){
        int oldY=page.equals(renderedPage)?scroll.getScrollY():0;renderedPage=page;
        scroll.post(()->scroll.scrollTo(0,oldY));
        rows.clear();couponListVisible=false;couponNotice=null;
        content.removeAllViews();content.setPadding(dp(10),dp(7),dp(10),dp(couponPage()?(!onlyActive?124:68):16));summary();
        if("settings".equals(page)){settings();return;}
        if("card".equals(page)){card();return;}
        if(!signedIn&&!demo){welcome();return;}
        couponListVisible=true;
        couponNotice=text("",15,MUTED);couponNotice.setPadding(0,dp(7),0,dp(12));content.addView(couponNotice);updateNotice();
        int count=0;LinearLayout pair=null;
        for(Coupon c:coupons){
            if((onlyActive&&!c.activated)||(hideOnline&&c.onlineShop()))continue;
            if(count%2==0){
                pair=new LinearLayout(this);pair.setOrientation(LinearLayout.HORIZONTAL);
                LinearLayout.LayoutParams line=new LinearLayout.LayoutParams(-1,-2);line.bottomMargin=dp(8);content.addView(pair,line);
            }
            CouponRow row=new CouponRow();row.coupon=c;rows.add(row);
            FrameLayout tileView=new FrameLayout(this);tileView.setBackground(shape(Color.WHITE,10));tileView.setClipToOutline(true);
            LinearLayout.LayoutParams tile=new LinearLayout.LayoutParams(0,-1,1);if(count%2==0)tile.rightMargin=dp(4);else tile.leftMargin=dp(4);pair.addView(tileView,tile);count++;
            if(imagesEnabled&&!demo&&!ImageUrl.from(c.raw).isEmpty()){
                ImageView picture=new ImageView(this);picture.setScaleType(ImageView.ScaleType.FIT_CENTER);picture.setAlpha(.55f);picture.setContentDescription(c.title);
                FrameLayout.LayoutParams media=new FrameLayout.LayoutParams(dp(144),dp(118),Gravity.RIGHT|Gravity.TOP);media.rightMargin=-dp(24);tileView.addView(picture,media);app.images.show(picture,ImageUrl.from(c.raw));
                View wash=new View(this);wash.setBackground(new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,new int[]{Color.WHITE,0xddffffff,0x00ffffff}));tileView.addView(wash,new FrameLayout.LayoutParams(-1,dp(118)));
            }
            LinearLayout p=new LinearLayout(this);p.setOrientation(LinearLayout.VERTICAL);p.setPadding(dp(10),dp(10),dp(10),dp(10));tileView.addView(p,new FrameLayout.LayoutParams(-1,-1));
            row.tag=text("",10,GREEN);row.tag.setTypeface(null,Typeface.BOLD);row.tag.setMaxLines(1);row.tag.setEllipsize(android.text.TextUtils.TruncateAt.END);p.addView(row.tag);
            row.title=text("",15,INK);row.title.setTypeface(null,Typeface.BOLD);row.title.setMinLines(2);row.title.setMaxLines(3);row.title.setEllipsize(android.text.TextUtils.TruncateAt.END);row.title.setPadding(0,dp(5),0,dp(5));p.addView(row.title);
            row.title.setOnClickListener(v->{if(!busy)details(row.coupon);});row.title.setContentDescription("Coupon details");
            row.discount=text("",25,GREEN);row.discount.setTypeface(null,Typeface.BOLD);row.discount.setBackgroundColor(Color.WHITE);p.addView(row.discount);
            row.discountDescription=text("",13,MUTED);row.discountDescription.setBackgroundColor(Color.WHITE);row.discountDescription.setMaxLines(2);row.discountDescription.setEllipsize(android.text.TextUtils.TruncateAt.END);p.addView(row.discountDescription);
            row.expiry=text("",12,MUTED);row.expiry.setBackgroundColor(Color.WHITE);row.expiry.setPadding(0,dp(4),0,dp(6));p.addView(row.expiry);
            row.processing=text("Processing…",12,MUTED);p.addView(row.processing);
            p.addView(new View(this),new LinearLayout.LayoutParams(-1,0,1));
            row.change=button(p,"",()->confirm(row.coupon),true,0);bind(row,c);
        }
        if(count%2==1){LinearLayout.LayoutParams blank=new LinearLayout.LayoutParams(0,1,1);blank.leftMargin=dp(4);pair.addView(new View(this),blank);}
        if(count==0){LinearLayout p=panel();heading(p,onlyActive?"No activated coupons":"No coupons");}
        if(demo)button(content,"Leave preview",()->{demo=false;coupons.clear();render();},false,0);
    }
    private void updateNotice(){
        couponNotice.setVisibility(stale&&!demo?View.VISIBLE:View.GONE);
        couponNotice.setText("Pull down to refresh.");
    }
    private void bind(CouponRow row,Coupon coupon){
        row.coupon=coupon;
        row.tag.setText(coupon.activated?"ACTIVATED":coupon.onlineShop()?"ONLINESHOP":"");
        row.title.setText(coupon.title);row.title.setContentDescription(coupon.title+". Show coupon details.");
        String discount=Coupon.discountTitle(coupon.raw),description=Coupon.discountDescription(coupon.raw);
        row.discount.setText(plain(discount));row.discount.setVisibility(discount.isEmpty()?View.GONE:View.VISIBLE);
        row.discountDescription.setText(plain(description));row.discountDescription.setVisibility(description.isEmpty()?View.GONE:View.VISIBLE);
        String validity=coupon.validUntil(java.util.Locale.forLanguageTag(language));row.expiry.setText(validity);
        row.expiry.setVisibility(validity.isEmpty()?View.GONE:View.VISIBLE);
        row.processing.setVisibility(coupon.processing?View.VISIBLE:View.GONE);
        row.change.setText(coupon.activated?"Deactivate":"Activate");
        row.change.setEnabled(!demo&&!coupon.processing&&!stale);
    }
    private CharSequence plain(String text){return android.text.Html.fromHtml(text,android.text.Html.FROM_HTML_MODE_LEGACY,(source)->null,null);}
    private void updateCoupons(){
        if(!couponPage()){render();return;}
        if(!couponListVisible||(!signedIn&&!demo)){render();return;}
        List<Coupon> visible=new ArrayList<>();for(Coupon c:coupons)if((!onlyActive||c.activated)&&(!hideOnline||!c.onlineShop()))visible.add(c);
        // Preserve the actual views and images for an unchanged list. Rebuild only for structural changes.
        if(visible.size()!=rows.size()){render();return;}
        for(int i=0;i<rows.size();i++){
            Coupon old=rows.get(i).coupon,next=visible.get(i);
            if(!old.id.equals(next.id)||!old.section.equals(next.section)||!ImageUrl.from(old.raw).equals(ImageUrl.from(next.raw))){render();return;}
        }
        for(int i=0;i<rows.size();i++)bind(rows.get(i),visible.get(i));
        updateNotice();summary();
    }
    private void image(LinearLayout parent,String url,String alt,int height){
        if(!imagesEnabled||demo||url.isEmpty())return;
        ImageView view=new ImageView(this);view.setContentDescription(alt);view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams size=new LinearLayout.LayoutParams(-1,dp(height));size.bottomMargin=dp(10);parent.addView(view,size);
        app.images.show(view,url);
    }
    private void welcome(){
        LinearLayout p=panel();heading(p,"Log in");
        button(p,"Log in with Lidl",this::login,true,0);
        button(p,"Preview without logging in",this::preview,false,0);
    }
    private void login(){
        job("Preparing secure browser login…",()->{loginUrl=app.api.beginLogin(country,language);},()->{
            render();try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(loginUrl)));}
            catch(android.content.ActivityNotFoundException e){error(new IllegalArgumentException("Install or enable a browser to log in."));}
            finally{loginUrl=null;}
        });
    }
    private String loginUrl;
    private void refresh(){
        if(demo){render();return;}
        job("Loading coupons…",()->{String body=app.api.list(country,language,store);coupons=Coupon.parse(body);cacheTime=System.currentTimeMillis();stale=false;signedIn=app.api.signedIn();
            if(loyaltyId.isEmpty())try{loyaltyId=app.api.loyalty(country,language);cardNotice="";}
            catch(Exception e){cardNotice="Account card could not be retrieved. Retry on the Checkout card tab, or import your existing card.";signedIn=app.api.signedIn();if(!signedIn){coupons.clear();stale=true;loyaltyId="";}}},this::updateCoupons);
    }
    private void loadCache() throws Exception {
        coupons=new ArrayList<>();stale=true;cacheTime=0;
        JSONObject cached=app.vault.json("coupons");
        if(signedIn&&country.equals(cached.optString("country"))&&language.equals(cached.optString("language"))&&store.equals(cached.optString("store"))){
            String body=cached.optString("body");if(!body.isEmpty()){coupons=Coupon.parse(body);cacheTime=cached.optLong("saved");}
        }
    }
    private void preview(){
        demo=true;stale=false;page="coupons";onlyActive=false;
        try{coupons=Coupon.parse("{\"sections\":[{\"name\":\"Examples\",\"promotions\":[{\"id\":\"example-1\",\"title\":\"A little less on your weekly shop\",\"isActivated\":false},{\"id\":\"example-2\",\"title\":\"Your next coffee break\",\"isActivated\":true}]}]}");}
        catch(Exception e){error(e);}render();
    }
    private void details(Coupon c){
        if(demo){showDetails(c.raw,c);return;}
        job("Loading coupon details…",()->{detailResult=app.api.detail(c.id,country,language,store);},()->{summary();showDetails(detailResult,c);detailResult=null;});
    }
    private JSONObject detailResult;
    private void showDetails(JSONObject d,Coupon c){
        try{
            if(demo){new AlertDialog.Builder(this).setTitle(c.title).setMessage("Example coupon. No server operation is available in preview.").setPositiveButton("Close",null).show();return;}
            CouponDetail detail=new CouponDetail(d,c.id);
            CharSequence plain=android.text.Html.fromHtml(detail.terms(),android.text.Html.FROM_HTML_MODE_LEGACY,(source)->null,null);
            LinearLayout body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);body.setPadding(dp(20),dp(12),dp(20),dp(12));
            image(body,ImageUrl.from(d),detail.title,200);
            String benefit=Coupon.discountTitle(d),benefitDescription=Coupon.discountDescription(d);
            if(!benefit.isEmpty()){TextView amount=text(plain(benefit).toString(),24,GREEN);amount.setTypeface(null,Typeface.BOLD);body.addView(amount);}
            if(!benefitDescription.isEmpty())paragraph(body,plain(benefitDescription).toString());
            String validity=new Coupon(d,c.section).validUntil(java.util.Locale.forLanguageTag(language));if(!validity.isEmpty())paragraph(body,validity);
            TextView terms=text(plain.toString(),15,INK);body.addView(terms);
            ScrollView scroll=new ScrollView(this);scroll.addView(body);
            AlertDialog.Builder builder=new AlertDialog.Builder(this).setTitle(detail.title).setView(scroll).setPositiveButton("Close",null);
            if(!detail.groups.isEmpty()&&detail.activated&&!stale)builder.setNeutralButton("Change products",(dialog,which)->prepareChange(c,true));
            builder.show();
        }catch(Exception e){error(e);}
    }
    private void confirm(Coupon c){prepareChange(c,false);}
    private void prepareChange(Coupon c,boolean products){
        job("Checking current coupon details…",()->{detailResult=app.api.detail(c.id,country,language,store);},()->{
            summary();
            try{
                CouponDetail detail=new CouponDetail(detailResult,c.id);detail.available(System.currentTimeMillis());
                if(detail.activated!=c.activated)throw new IllegalArgumentException("The activation state changed. Refresh the coupon list first.");
                if(products||(!detail.activated&&!detail.groups.isEmpty())){chooseProducts(detail,products);return;}
                new AlertDialog.Builder(this).setTitle(detail.activated?"Deactivate coupon?":"Activate coupon?")
                    .setMessage(detail.title).setNegativeButton("Cancel",null).setPositiveButton("Confirm",(dialog,which)->mutate(detail,false,null)).show();
            }catch(Exception e){stale=true;updateCoupons();error(e);}finally{detailResult=null;}
        });
    }
    private void chooseProducts(CouponDetail detail,boolean override){
        LinearLayout choices=new LinearLayout(this);choices.setOrientation(LinearLayout.VERTICAL);choices.setPadding(dp(20),dp(10),dp(20),dp(10));
        paragraph(choices,"Choose one product in each group. Lidl checks the product rules at checkout.");
        java.util.Map<String,String> selected=new java.util.LinkedHashMap<>();
        for(CouponDetail.Group group:detail.groups){
            heading(choices,group.title);RadioGroup radio=new RadioGroup(this);choices.addView(radio);
            java.util.Map<Integer,String> identifiers=new java.util.HashMap<>();
            int existing=View.NO_ID,selectedCount=0;
            for(CouponDetail.Article article:group.articles){
                image(radio,article.image,article.title,110);
                RadioButton option=new RadioButton(this);option.setId(View.generateViewId());option.setText(article.title);option.setTextColor(INK);
                identifiers.put(option.getId(),article.id);radio.addView(option);
                if(article.selected){existing=option.getId();selectedCount++;}
            }
            radio.setOnCheckedChangeListener((view,id)->{String article=identifiers.get(id);if(article!=null)selected.put(group.id,article);else selected.remove(group.id);});
            if(selectedCount==1)radio.check(existing);
        }
        ScrollView scroll=new ScrollView(this);scroll.addView(choices);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle(override?"Change selected products":"Choose products to activate")
            .setView(scroll).setNegativeButton("Cancel",null).setPositiveButton("Confirm",null).create();
        dialog.setOnShowListener(ignored->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(view->{
            try{detail.selection(selected);dialog.dismiss();mutate(detail,override,new java.util.LinkedHashMap<>(selected));}
            catch(Exception e){Toast.makeText(this,e.getMessage(),Toast.LENGTH_LONG).show();}
        }));dialog.show();
    }
    private void mutate(CouponDetail displayed,boolean override,java.util.Map<String,String> selected){
        stale=true;
        for(CouponRow row:rows)if(row.coupon.id.equals(displayed.id))row.change.setText("Updating…");
        job("Updating coupon…",()->{
            // Re-read after user confirmation; selections are validated against this latest response.
            CouponDetail latest=new CouponDetail(app.api.detail(displayed.id,country,language,store),displayed.id);
            latest.available(System.currentTimeMillis());
            if(latest.activated!=displayed.activated)throw new IllegalArgumentException("Coupon state changed while you were choosing. Refresh first.");
            if(selected!=null)app.api.select(latest,override,selected,country,language,store);
            else {
                if(!latest.activated&&!latest.groups.isEmpty())throw new IllegalArgumentException("This coupon requires product choices. Refresh first.");
                app.api.activation(latest.id,!latest.activated,country,language,store);
            }
        },this::refresh);
    }
    private void activateAll(){
        if(busy||stale||demo||!signedIn)return;
        List<Coupon> confirmed=bulkCandidates();if(confirmed.isEmpty())return;
        new AlertDialog.Builder(this).setTitle("Activate all visible coupons?")
            .setMessage("Check and activate up to "+confirmed.size()+" coupons. Product choices and unavailable coupons are skipped.")
            .setNegativeButton("Cancel",null).setPositiveButton("Activate all",(dialog,which)->{
                stale=true;batchCancel=new java.util.concurrent.atomic.AtomicBoolean(false);final java.util.concurrent.atomic.AtomicBoolean cancellation=batchCancel;
                AlertDialog running=new AlertDialog.Builder(this).setTitle("Activating coupons…").setMessage("You can stop the remaining requests.")
                    .setPositiveButton("Stop",(d,w)->cancellation.set(true)).create();running.setCanceledOnTouchOutside(false);running.setOnCancelListener(d->cancellation.set(true));running.show();
                job("Activating coupons…",()->{
                    batchResult=new BulkActivator(app.api).run(confirmed,hideOnline,country,language,store,cancellation::get);
                    try{coupons=Coupon.parse(app.api.list(country,language,store));cacheTime=System.currentTimeMillis();stale=false;}
                    catch(Exception refreshFailed){stale=true;if(batchResult.failure==null)batchResult.failure=refreshFailed;}
                    try{signedIn=app.api.signedIn();if(!signedIn){coupons.clear();loyaltyId="";stale=true;}}
                    catch(Exception sessionFailed){stale=true;batchResult.failure=sessionFailed;}
                },()->{
                    running.dismiss();batchCancel=null;updateCoupons();
                    String message=batchResult.activated+" activated · "+batchResult.skipped+" skipped"+(batchResult.choices>0?" ("+batchResult.choices+" need product choices)":"");
                    if(batchResult.cancelled)message+="\nStopped.";
                    if(batchResult.failure!=null)message+="\nStopped after a failed or uncertain request. Refresh before retrying.";
                    new AlertDialog.Builder(this).setTitle("Activation results").setMessage(message).setPositiveButton("Close",null).show();
                });
            }).show();
    }
    private void loadCard() throws Exception {
        cardImage=app.vault.read("card-image");byte[] text=app.vault.read("card-text");cardText=text==null?"":new String(text,StandardCharsets.UTF_8);
        JSONObject saved=app.vault.json("loyalty");loyaltyId=signedIn&&country.equals(saved.optString("country"))?saved.optString("id"):"";
    }
    private void card(){
        LinearLayout top=new LinearLayout(this);top.setGravity(Gravity.CENTER_VERTICAL);content.addView(top);
        TextView label=text("Checkout",20,INK);label.setTypeface(null,Typeface.BOLD);top.addView(label,new LinearLayout.LayoutParams(0,-2,1));
        Button settingsButton=button(top,"⚙",()->navigate("settings"),false,0);settingsButton.setContentDescription("Settings");settingsButton.setTextSize(22);settingsButton.setPadding(0,0,0,0);settingsButton.setLayoutParams(new LinearLayout.LayoutParams(dp(44),dp(44)));
        LinearLayout p=panel();
        if(cardImage!=null){
            Bitmap bitmap=BitmapFactory.decodeByteArray(cardImage,0,cardImage.length);
            if(bitmap!=null){ImageView image=new ImageView(this);image.setImageBitmap(bitmap);image.setAdjustViewBounds(true);image.setContentDescription("Your imported checkout card image");p.addView(image,new LinearLayout.LayoutParams(-1,-2));}
        }else if(!cardText.isEmpty()){
            try{p.addView(new QrView(this,cardText),new LinearLayout.LayoutParams(-1,dp(320)));}catch(Exception e){paragraph(p,"Saved QR data could not be rendered. Import a card image instead.");}
        }else if(!loyaltyId.isEmpty()&&signedIn&&!demo){
            try{p.addView(new QrView(this,loyaltyId),new LinearLayout.LayoutParams(-1,dp(320)));}
            catch(Exception e){paragraph(p,"Account card cannot be rendered. Import your existing card instead.");}
        }else paragraph(p,"Import a cropped screenshot of your own existing Lidl Plus card. The card stays on this device; no image is uploaded.");
        if(!cardNotice.isEmpty())paragraph(p,cardNotice);
        if(signedIn&&!demo)button(p,"Retrieve account card",()->job("Retrieving account loyalty card…",()->{
            loyaltyId=app.api.loyalty(country,language);cardNotice="";
        },this::render),true,0);
        if(cardImage!=null||!cardText.isEmpty())paragraph(p,"Showing your imported card. Remove the import to display your account card.");
        button(p,"Import card image",()->{
            Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(pick,17);
        },true,0);
        button(p,"Import existing QR text",this::importText,false,0);
        if(cardImage!=null||!cardText.isEmpty())button(p,"Remove card",()->job("Removing card…",()->{app.vault.delete("card-image");app.vault.delete("card-text");cardImage=null;cardText="";},this::render),false,0);
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(request!=17||result!=RESULT_OK||data==null||data.getData()==null)return;
        Uri uri=data.getData();
        job("Saving card on this device…",()->{
            byte[] bytes;try(InputStream in=getContentResolver().openInputStream(uri)){if(in==null)throw new IllegalArgumentException("Cannot read the selected image.");bytes=Transport.read(in,8*1024*1024);}
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,bounds);
            if(bounds.outWidth<=0||bounds.outHeight<=0)throw new IllegalArgumentException("Select a valid card image.");
            BitmapFactory.Options opts=new BitmapFactory.Options();opts.inSampleSize=1;
            while(Math.max(bounds.outWidth,bounds.outHeight)/opts.inSampleSize>2048)opts.inSampleSize*=2;
            Bitmap bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.length,opts);
            if(bitmap==null)throw new IllegalArgumentException("Cannot decode this image.");
            ByteArrayOutputStream out=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.PNG,100,out);bitmap.recycle();
            byte[] clean=out.toByteArray();if(clean.length>8*1024*1024)throw new IllegalArgumentException("The card image is too large.");
            app.vault.write("card-image",clean);app.vault.delete("card-text");cardImage=clean;cardText="";
        },this::render);
    }
    private void importText(){
        EditText input=new EditText(this);input.setHint("Exact text decoded from your own card QR");input.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        new AlertDialog.Builder(this).setTitle("Existing card QR text").setMessage("Paste the exact payload of your own loyalty card. This does not generate a new account or coupon.")
            .setView(input).setNegativeButton("Cancel",null).setPositiveButton("Save",(d,w)->{
                String value=input.getText().toString();
                job("Saving QR text…",()->{
                    if(value.isEmpty()||value.length()>2048)throw new IllegalArgumentException("Enter 1–2048 characters from your existing card.");
                    io.nayuki.qrcodegen.QrCode.encodeText(value,io.nayuki.qrcodegen.QrCode.Ecc.MEDIUM);
                    app.vault.write("card-text",value.getBytes(StandardCharsets.UTF_8));app.vault.delete("card-image");cardText=value;cardImage=null;
                },this::render);
            }).show();
    }
    private EditText field(LinearLayout p,String label,String value){
        p.addView(text(label,13,MUTED));EditText e=new EditText(this);e.setSingleLine(true);e.setText(value);e.setTextColor(INK);p.addView(e);return e;
    }
    private void settings(){
        button(content,"Back to checkout",()->navigate("card"),false,0);
        LinearLayout p=panel();heading(p,"Your region");
        EditText c=field(p,"Country (for example CZ)",country),l=field(p,"Language (for example cs-CZ)",language),s=field(p,"Store ID (optional)",store);
        button(p,"Save region",()->{
            String cc=c.getText().toString().trim().toUpperCase(java.util.Locale.ROOT),ll=l.getText().toString().trim(),ss=s.getText().toString().trim();
            job("Saving region…",()->{
                Protocol.locale(cc,ll);if(!ss.isEmpty()&&!ss.matches("[A-Za-z0-9_-]{1,100}"))throw new IllegalArgumentException("Store ID must contain letters, digits, hyphens or underscores.");
                app.vault.json("settings",new JSONObject().put("country",cc).put("language",ll).put("store",ss).put("images",imagesEnabled).put("hideOnline",hideOnline));
                if(!country.equals(cc)){app.vault.delete("loyalty");app.vault.delete("card-image");app.vault.delete("card-text");loyaltyId="";cardImage=null;cardText="";cardNotice="";app.images.clear();}
                country=cc;language=ll;store=ss;app.vault.delete("coupons");coupons.clear();stale=true;demo=false;
            },this::render);
        },true,0);
        LinearLayout privacy=panel();heading(privacy,"Preferences");
        CheckBox images=new CheckBox(this);images.setText("Load coupon pictures");images.setTextColor(INK);images.setChecked(imagesEnabled);privacy.addView(images);
        images.setOnCheckedChangeListener((view,value)->job("Saving picture preference…",()->{
            JSONObject saved=app.vault.json("settings");saved.put("images",value);app.vault.json("settings",saved);imagesEnabled=value;app.images.clear();
        },this::render));
        button(privacy,signedIn?"Log out and erase local data":"Erase local data",()->new AlertDialog.Builder(this).setTitle("Erase this wallet?")
            .setMessage("Removes tokens, coupons, region settings and imported card from this device. Your Lidl account and browser login remain.")
            .setNegativeButton("Cancel",null).setPositiveButton("Erase",(d,w)->job("Erasing local data…",()->{
                app.api.signOut();app.images.clear();imagesEnabled=true;hideOnline=false;signedIn=false;demo=false;coupons.clear();cardImage=null;cardText="";loyaltyId="";cardNotice="";country="CZ";language="cs-CZ";store="";cacheTime=0;stale=true;
            },()->{page="coupons";render();})),false,0);
    }
}
