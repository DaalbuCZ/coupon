package local.couponpocket;

import java.net.URI;
import java.net.InetAddress;
import org.json.JSONObject;
import org.json.JSONArray;

/** Image URLs come only from coupon image fields, never user identifiers or HTML. */
public final class ImageUrl {
    public static String from(JSONObject object){
        JSONObject image=object.optJSONObject("image");
        if(image==null){JSONArray images=object.optJSONArray("images");if(images!=null)image=images.optJSONObject(0);}
        return image==null?"":image.optString("url");
    }
    public static void allow(String url){
        URI u=URI.create(url);String host=u.getHost();
        if(!"https".equals(u.getScheme())||host==null||u.getRawUserInfo()!=null||u.getFragment()!=null||
            (u.getPort()!=-1&&u.getPort()!=443)||url.length()>8192||host.equalsIgnoreCase("localhost")||
            host.endsWith(".localhost")||host.endsWith(".local")||!host.contains("."))
            throw new SecurityException("Unsupported coupon image URL.");
    }
    public static void publicAddress(InetAddress address){
        byte[] bytes=address.getAddress();
        boolean restricted=address.isAnyLocalAddress()||address.isLoopbackAddress()||address.isSiteLocalAddress()||address.isLinkLocalAddress()||address.isMulticastAddress();
        if(bytes.length==4){int a=bytes[0]&255,b=bytes[1]&255;restricted|=a==0||a>=240||(a==100&&b>=64&&b<=127)||(a==198&&(b==18||b==19));}
        else restricted|=(bytes[0]&254)==252;
        if(restricted)throw new SecurityException("Local network image address blocked.");
    }
    private ImageUrl(){}
}
