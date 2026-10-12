package local.couponpocket;
import org.json.JSONObject;
public interface Storage {
    JSONObject json(String name) throws Exception;
    void json(String name,JSONObject data) throws Exception;
    void delete(String name);
    void clear() throws Exception;
}
