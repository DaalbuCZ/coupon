package local.couponpocket;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.LruCache;
import android.widget.ImageView;
import java.lang.ref.WeakReference;
import java.net.InetAddress;
import java.net.URL;
import java.io.InputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import javax.net.ssl.HttpsURLConnection;

/** Token-free image GETs, no redirects or persistent image storage. */
public final class Images {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    private final LruCache<String,Bitmap> cache=new LruCache<String,Bitmap>(6*1024*1024){
        @Override protected int sizeOf(String key,Bitmap value){return value.getAllocationByteCount();}
    };
    private volatile long generation=0;
    public void clear(){synchronized(cache){generation++;cache.evictAll();}}
    public void show(ImageView view,String url){
        try{ImageUrl.allow(url);}catch(Exception e){view.setVisibility(android.view.View.GONE);return;}
        Bitmap saved=cache.get(url);if(saved!=null){view.setImageBitmap(saved);return;}
        WeakReference<ImageView> target=new WeakReference<>(view);long current=generation;
        worker.execute(()->{
            if(current!=generation)return;
            Bitmap bitmap=null;try{
                bitmap=cache.get(url);if(bitmap==null)bitmap=fetch(url);
            }catch(Exception ignored){}
            final Bitmap result=bitmap;
            main.post(()->{
                synchronized(cache){
                    if(current!=generation)return;
                    if(result!=null)cache.put(url,result);
                }
                ImageView image=target.get();if(image==null||!image.isAttachedToWindow())return;
                if(result==null)image.setVisibility(android.view.View.GONE);else image.setImageBitmap(result);
            });
        });
    }
    private Bitmap fetch(String url) throws Exception {
        ImageUrl.allow(url);
        for(InetAddress address:InetAddress.getAllByName(new URL(url).getHost()))ImageUrl.publicAddress(address);
        HttpsURLConnection c=(HttpsURLConnection)new URL(url).openConnection();
        try{
            c.setRequestMethod("GET");c.setInstanceFollowRedirects(false);c.setUseCaches(false);
            c.setConnectTimeout(10000);c.setReadTimeout(15000);
            c.setRequestProperty("Accept","image/*");c.setRequestProperty("User-Agent","CouponPocket/0.3.0 (Android)");
            // No bearer/client authorization, identifiers, referrer or cookie headers.
            if(c.getResponseCode()!=200)throw new IllegalArgumentException("Image unavailable.");
            String type=c.getContentType();if(type==null||!type.toLowerCase(java.util.Locale.ROOT).startsWith("image/"))throw new IllegalArgumentException("Not an image.");
            if(c.getContentLengthLong()>2*1024*1024)throw new IllegalArgumentException("Image too large.");
            byte[] data;try(InputStream in=c.getInputStream()){data=Transport.read(in,2*1024*1024);}
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(data,0,data.length,bounds);
            if(bounds.outWidth<=0||bounds.outHeight<=0||(long)bounds.outWidth*bounds.outHeight>40000000)throw new IllegalArgumentException("Invalid image dimensions.");
            BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=1;
            while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>1024)options.inSampleSize*=2;
            Bitmap bitmap=BitmapFactory.decodeByteArray(data,0,data.length,options);
            if(bitmap==null)throw new IllegalArgumentException("Unsupported image.");return bitmap;
        }finally{c.disconnect();}
    }
}
