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
    private static final int BG=Color.rgb(245,247,242),INK=Color.rgb(27,42,34),GREEN=Color.rgb(23,103,73),MUTED=Color.rgb(96,111,101);
    private App app;
    private LinearLayout root,content,nav;
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
        if(saved!=null){demo=saved.getBoolean("demo");page=saved.getString("page","coupons");onlyActive=saved.getBoolean("active");}
        shell();
        job("Opening your wallet…",()->{
            JSONObject settings=app.vault.json("settings");
            imagesEnabled=settings.optBoolean("images",true);
            country=settings.optString("country","CZ");language=settings.optString("language","cs-CZ");store=settings.optString("store","");
            signedIn=app.api.signedIn();loadCard();loadCache();
        },()->{
            if(getIntent().getData()!=null){consumeCallback(getIntent().getData());return;}
            if(demo)preview();else render();
        });
    }
    @Override protected void onSaveInstanceState(Bundle out){super.onSaveInstanceState(out);out.putBoolean("demo",demo);out.putString("page",page);out.putBoolean("active",onlyActive);}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);if(intent.getData()!=null)consumeCallback(intent.getData());}
    private void consumeCallback(Uri uri){
        getIntent().setData(null);
        if(busy){app.worker.execute(()->runOnUiThread(()->{if(!isDestroyed())consumeCallback(uri);}));return;}
        job("Completing login…",()->{app.api.finishLogin(uri.toString());app.images.clear();signedIn=true;demo=false;coupons.clear();loadCard();},()->{render();refresh();});
    }
    private void shell(){
        root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(BG);
        root.setPadding(dp(20),dp(18),dp(20),dp(12));setContentView(root);
        root.setOnApplyWindowInsetsListener((v,insets)->{
            root.setPadding(dp(20)+insets.getSystemWindowInsetLeft(),dp(18)+insets.getSystemWindowInsetTop(),
                dp(20)+insets.getSystemWindowInsetRight(),dp(12)+insets.getSystemWindowInsetBottom());
            return insets;
        });
        TextView brand=text("COUPON POCKET",13,GREEN);brand.setLetterSpacing(.13f);brand.setTypeface(null,Typeface.BOLD);root.addView(brand);
        TextView title=text("A quieter checkout.",28,INK);title.setTypeface(null,Typeface.BOLD);title.setPadding(0,dp(8),0,dp(4));root.addView(title);
        status=text("Login, coupons, your card.",14,MUTED);root.addView(status);
        scroll=new ScrollView(this);scroll.setFillViewport(true);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(0,dp(20),0,dp(20));scroll.addView(content);
        nav=new LinearLayout(this);nav.setGravity(Gravity.CENTER);root.addView(nav);
        button(nav,"Coupons",()->{page="coupons";render();},false,1);
        button(nav,"Checkout card",()->{page="card";render();},false,1);
        button(nav,"Settings",()->{page="settings";render();},false,1);
    }
    private TextView text(String s,int size,int color){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setLineSpacing(dp(3),1);return v;}
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private void paragraph(LinearLayout parent,String s){TextView v=text(s,15,MUTED);v.setPadding(0,dp(7),0,dp(12));parent.addView(v);}
    private void heading(LinearLayout parent,String s){TextView v=text(s,22,INK);v.setTypeface(null,Typeface.BOLD);v.setPadding(0,0,0,dp(8));parent.addView(v);}
    private LinearLayout panel(){LinearLayout p=new LinearLayout(this);p.setOrientation(LinearLayout.VERTICAL);p.setPadding(dp(18),dp(18),dp(18),dp(18));p.setBackground(shape(Color.WHITE,18));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(12);content.addView(p,lp);return p;}
    private Button button(LinearLayout parent,String label,Runnable action,boolean primary,int weight){
        Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setTextSize(14);b.setTextColor(primary?Color.WHITE:GREEN);
        b.setBackground(shape(primary?GREEN:Color.rgb(231,239,230),12));b.setPadding(dp(10),dp(10),dp(10),dp(10));b.setMinHeight(dp(48));
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
        if(busy)return;busy=true;status.setText(label);List<View> paused=new ArrayList<>();pauseInputs(content,paused);
        app.worker.execute(()->{
            Exception error=null;try{work.run();}catch(Exception e){
                error=e;
                try{signedIn=app.api.signedIn();if(!signedIn&&!demo){coupons.clear();stale=true;loyaltyId="";}}catch(Exception ignored){}
            }final Exception result=error;
            runOnUiThread(()->{
                if(isDestroyed()||isFinishing())return;
                busy=false;for(View view:paused)view.setEnabled(true);
                if(result!=null){if("coupons".equals(page))updateCoupons();else render();error(result);}else done.run();
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
    private void summary(){
        status.setText(demo?"PREVIEW · example coupons, no network":signedIn?"Your account · "+country+" · "+(stale?"saved view":"just refreshed"):"No analytics or advertising SDKs.");
    }
    private void render(){
        int oldY=page.equals(renderedPage)?scroll.getScrollY():0;renderedPage=page;
        scroll.post(()->scroll.scrollTo(0,oldY));
        rows.clear();couponListVisible=false;couponNotice=null;
        content.removeAllViews();summary();
        if("settings".equals(page)){settings();return;}
        if("card".equals(page)){card();return;}
        if(!signedIn&&!demo){welcome();return;}
        couponListVisible=true;
        LinearLayout top=new LinearLayout(this);content.addView(top);
        button(top,"Refresh",this::refresh,true,1);
        button(top,onlyActive?"Show all":"Activated only",()->{onlyActive=!onlyActive;render();},false,1);
        couponNotice=text("",15,MUTED);couponNotice.setPadding(0,dp(7),0,dp(12));content.addView(couponNotice);updateNotice();
        int count=0;LinearLayout pair=null;
        for(Coupon c:coupons){
            if(onlyActive&&!c.activated)continue;
            if(count%2==0){
                pair=new LinearLayout(this);pair.setOrientation(LinearLayout.HORIZONTAL);
                LinearLayout.LayoutParams line=new LinearLayout.LayoutParams(-1,-2);line.bottomMargin=dp(12);content.addView(pair,line);
            }
            CouponRow row=new CouponRow();row.coupon=c;rows.add(row);
            LinearLayout p=new LinearLayout(this);p.setOrientation(LinearLayout.VERTICAL);p.setPadding(dp(12),dp(14),dp(12),dp(12));p.setBackground(shape(Color.WHITE,16));
            LinearLayout.LayoutParams tile=new LinearLayout.LayoutParams(0,-1,1);if(count%2==0)tile.rightMargin=dp(6);else tile.leftMargin=dp(6);pair.addView(p,tile);count++;
            row.tag=text("",11,GREEN);row.tag.setTypeface(null,Typeface.BOLD);row.tag.setMaxLines(1);row.tag.setEllipsize(android.text.TextUtils.TruncateAt.END);p.addView(row.tag);
            image(p,ImageUrl.from(c.raw),c.title,120);
            row.title=text("",17,INK);row.title.setTypeface(null,Typeface.BOLD);row.title.setMinLines(2);row.title.setMaxLines(3);row.title.setEllipsize(android.text.TextUtils.TruncateAt.END);row.title.setPadding(0,dp(6),0,dp(6));p.addView(row.title);
            row.discount=text("",22,GREEN);row.discount.setTypeface(null,Typeface.BOLD);p.addView(row.discount);
            row.discountDescription=text("",13,MUTED);row.discountDescription.setMaxLines(2);row.discountDescription.setEllipsize(android.text.TextUtils.TruncateAt.END);p.addView(row.discountDescription);
            row.expiry=text("",12,MUTED);row.expiry.setPadding(0,dp(7),0,dp(8));p.addView(row.expiry);
            row.processing=text("Processing…",12,MUTED);p.addView(row.processing);
            p.addView(new View(this),new LinearLayout.LayoutParams(-1,0,1));
            button(p,"Details",()->details(row.coupon),false,0);
            row.change=button(p,"",()->confirm(row.coupon),true,0);bind(row,c);
        }
        if(count%2==1){LinearLayout.LayoutParams blank=new LinearLayout.LayoutParams(0,1,1);blank.leftMargin=dp(6);pair.addView(new View(this),blank);}
        if(count==0){LinearLayout p=panel();heading(p,onlyActive?"No activated coupons":"Your coupons will appear here");paragraph(p,"Refresh after logging in. An empty list may also mean there are no available coupons for your selected region.");}
        if(demo)button(content,"Leave preview",()->{demo=false;coupons.clear();render();},false,0);
    }
    private void updateNotice(){
        couponNotice.setVisibility(stale&&!demo?View.VISIBLE:View.GONE);
        couponNotice.setText(cacheTime>0?"Saved on "+java.text.DateFormat.getDateTimeInstance().format(new java.util.Date(cacheTime))+". Refresh to check activation and expiry.":"Refresh to load your coupons.");
    }
    private void bind(CouponRow row,Coupon coupon){
        row.coupon=coupon;
        row.tag.setText(coupon.activated?"ACTIVATED":coupon.section.toUpperCase(java.util.Locale.ROOT));
        row.title.setText(coupon.title);
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
        if(!"coupons".equals(page)){render();return;}
        if(!couponListVisible||(!signedIn&&!demo)){render();return;}
        List<Coupon> visible=new ArrayList<>();for(Coupon c:coupons)if(!onlyActive||c.activated)visible.add(c);
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
        LinearLayout p=panel();heading(p,"Just the essentials");paragraph(p,"Sign in with Lidl, activate your coupons, then show your existing card at checkout.");
        paragraph(p,"Your password stays in the browser. This app sends no analytics, advertising IDs, location, or screen-view events.");
        button(p,"Log in with Lidl",this::login,true,0);
        button(p,"Preview without logging in",this::preview,false,0);
        paragraph(content,"Independent experimental client. Lidl may reject login or coupon requests. Login-page cookies and server-side processing are controlled by Lidl.");
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
        demo=true;stale=false;page="coupons";
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
    private void loadCard() throws Exception {
        cardImage=app.vault.read("card-image");byte[] text=app.vault.read("card-text");cardText=text==null?"":new String(text,StandardCharsets.UTF_8);
        JSONObject saved=app.vault.json("loyalty");loyaltyId=signedIn&&country.equals(saved.optString("country"))?saved.optString("id"):"";
    }
    private void card(){
        LinearLayout p=panel();heading(p,"Ready at checkout");
        if(cardImage!=null){
            Bitmap bitmap=BitmapFactory.decodeByteArray(cardImage,0,cardImage.length);
            if(bitmap!=null){ImageView image=new ImageView(this);image.setImageBitmap(bitmap);image.setAdjustViewBounds(true);image.setContentDescription("Your imported checkout card image");p.addView(image,new LinearLayout.LayoutParams(-1,-2));}
        }else if(!cardText.isEmpty()){
            try{p.addView(new QrView(this,cardText),new LinearLayout.LayoutParams(-1,dp(320)));}catch(Exception e){paragraph(p,"Saved QR data could not be rendered. Import a card image instead.");}
        }else if(!loyaltyId.isEmpty()&&signedIn&&!demo){
            try{p.addView(new QrView(this,loyaltyId),new LinearLayout.LayoutParams(-1,dp(320)));paragraph(p,"Account loyalty card · "+country+" · saved for offline use");}
            catch(Exception e){paragraph(p,"Account card cannot be rendered. Import your existing card instead.");}
        }else paragraph(p,"Import a cropped screenshot of your own existing Lidl Plus card. The card stays on this device; no image is uploaded.");
        if(!cardNotice.isEmpty())paragraph(p,cardNotice);
        if(signedIn&&!demo)button(p,"Retrieve account card",()->job("Retrieving account loyalty card…",()->{
            loyaltyId=app.api.loyalty(country,language);cardNotice="";
        },this::render),true,0);
        if(cardImage!=null||!cardText.isEmpty())paragraph(p,"Showing your imported card. Remove the import to display your account card.");
        paragraph(p,"Activation happens on Lidl's servers. Show this card at checkout to identify your account. Importing an image or QR text does not create coupons or guarantee redemption.");
        button(p,"Import card image",()->{
            Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(pick,17);
        },true,0);
        button(p,"Import existing QR text",this::importText,false,0);
        if(cardImage!=null||!cardText.isEmpty())button(p,"Remove card",()->job("Removing card…",()->{app.vault.delete("card-image");app.vault.delete("card-text");cardImage=null;cardText="";},this::render),false,0);
        paragraph(content,"Card display works offline. Expiring or payment QR codes must not be saved here; use your ordinary loyalty card.");
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
        LinearLayout p=panel();heading(p,"Your region");
        EditText c=field(p,"Country (for example CZ)",country),l=field(p,"Language (for example cs-CZ)",language),s=field(p,"Store ID (optional)",store);
        button(p,"Save region",()->{
            String cc=c.getText().toString().trim().toUpperCase(java.util.Locale.ROOT),ll=l.getText().toString().trim(),ss=s.getText().toString().trim();
            job("Saving region…",()->{
                Protocol.locale(cc,ll);if(!ss.isEmpty()&&!ss.matches("[A-Za-z0-9_-]{1,100}"))throw new IllegalArgumentException("Store ID must contain letters, digits, hyphens or underscores.");
                app.vault.json("settings",new JSONObject().put("country",cc).put("language",ll).put("store",ss).put("images",imagesEnabled));
                if(!country.equals(cc)){app.vault.delete("loyalty");app.vault.delete("card-image");app.vault.delete("card-text");loyaltyId="";cardImage=null;cardText="";cardNotice="";app.images.clear();}
                country=cc;language=ll;store=ss;app.vault.delete("coupons");coupons.clear();stale=true;demo=false;
            },this::render);
        },true,0);
        LinearLayout privacy=panel();heading(privacy,"Less data, by design");
        CheckBox images=new CheckBox(this);images.setText("Load coupon pictures");images.setTextColor(INK);images.setChecked(imagesEnabled);privacy.addView(images);
        images.setOnCheckedChangeListener((view,value)->job("Saving picture preference…",()->{
            JSONObject saved=app.vault.json("settings");saved.put("images",value);app.vault.json("settings",saved);imagesEnabled=value;app.images.clear();
        },this::render));
        paragraph(privacy,"Account, coupon and loyalty-card requests use Lidl services. Enabled pictures load directly from image URLs in coupon responses without your login token. No ads, analytics, crash reporting, device identifiers, location, notifications, or background refresh. Pictures are cached only in memory; you can disable them above.");
        paragraph(privacy,"Tokens, saved coupons and your checkout card are encrypted on this device. Backups are disabled. Screenshots are allowed. Your browser and Lidl's servers have their own privacy practices.");
        button(privacy,signedIn?"Log out and erase local data":"Erase local data",()->new AlertDialog.Builder(this).setTitle("Erase this wallet?")
            .setMessage("Removes tokens, coupons, region settings and imported card from this device. Your Lidl account and browser login remain.")
            .setNegativeButton("Cancel",null).setPositiveButton("Erase",(d,w)->job("Erasing local data…",()->{
                app.api.signOut();app.images.clear();imagesEnabled=true;signedIn=false;demo=false;coupons.clear();cardImage=null;cardText="";loyaltyId="";cardNotice="";country="CZ";language="cs-CZ";store="";cacheTime=0;stale=true;
            },()->{page="coupons";render();})),false,0);
        paragraph(content,"Coupon Pocket 0.2.5 · independent experimental client. Login and checkout compatibility require testing with a real account. No Lidl assets or original application code are included.");
    }
}
