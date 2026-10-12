package local.couponpocket;
import android.content.Context;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
import android.widget.ScrollView;

/** Intercept a downward drag only at the top; normal scrolling and button taps stay native. */
public final class RefreshScroll extends ScrollView {
    public interface Listener {boolean allowed();void pull(float distance);void refresh();}
    private final Listener listener;private final int slop;private float start;private boolean dragging;
    public RefreshScroll(Context context,Listener listener){super(context);this.listener=listener;slop=ViewConfiguration.get(context).getScaledTouchSlop();}
    @Override public boolean onInterceptTouchEvent(MotionEvent e){
        if(e.getActionMasked()==MotionEvent.ACTION_DOWN){start=e.getY();dragging=false;}
        if(e.getPointerCount()>1){reset();return super.onInterceptTouchEvent(e);}
        if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&listener.allowed()&&getScrollY()==0&&e.getY()-start>slop){dragging=true;return true;}
        return super.onInterceptTouchEvent(e);
    }
    @Override public boolean onTouchEvent(MotionEvent e){
        if(!dragging)return super.onTouchEvent(e);
        if(e.getPointerCount()>1){reset();return true;}
        float distance=Math.max(0,e.getY()-start);
        if(e.getActionMasked()==MotionEvent.ACTION_MOVE){listener.pull(distance);return true;}
        if(e.getActionMasked()==MotionEvent.ACTION_UP){boolean refresh=distance>=72*getResources().getDisplayMetrics().density;reset();if(refresh&&listener.allowed())listener.refresh();return true;}
        if(e.getActionMasked()==MotionEvent.ACTION_CANCEL){reset();return true;}
        return true;
    }
    private void reset(){dragging=false;listener.pull(0);}
}
