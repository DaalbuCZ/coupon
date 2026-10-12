package local.couponpocket;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.View;
import io.nayuki.qrcodegen.QrCode;
/** Offline renderer with integer-sized modules and a four-module quiet zone. */
public final class QrView extends View {
    private final QrCode qr;private final Paint paint=new Paint();
    public QrView(Context c,String payload){super(c);qr=QrCode.encodeText(payload,QrCode.Ecc.MEDIUM);setContentDescription("Your imported checkout card QR code");}
    @Override protected void onDraw(Canvas canvas){
        canvas.drawColor(Color.WHITE);
        int modules=qr.size+8,step=Math.max(1,Math.min(getWidth(),getHeight())/modules);
        int left=(getWidth()-modules*step)/2,top=(getHeight()-modules*step)/2;
        paint.setColor(Color.BLACK);paint.setAntiAlias(false);
        for(int y=0;y<qr.size;y++)for(int x=0;x<qr.size;x++)if(qr.getModule(x,y))
            canvas.drawRect(left+(x+4)*step,top+(y+4)*step,left+(x+5)*step,top+(y+5)*step,paint);
    }
}
