package local.couponpocket;
import android.app.Application;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
/** One serial queue across activity recreation prevents session/logout races. */
public final class App extends Application {
    public final ExecutorService worker=Executors.newSingleThreadExecutor();
    public Vault vault;public Api api;public final Images images=new Images();
    @Override public void onCreate(){super.onCreate();vault=new Vault(this);api=new Api(vault);}
}
