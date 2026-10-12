package local.couponpocket;
import java.util.Map;
public interface RequestClient {
    Transport.Reply call(String method,String url,Map<String,String> headers,String body,String contentType) throws Exception;
}
