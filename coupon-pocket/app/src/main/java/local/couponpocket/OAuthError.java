package local.couponpocket;

import org.json.JSONObject;

/** Show only recognized protocol codes, never server descriptions or response bodies. */
public final class OAuthError {
    public static String message(String stage,int status,String body){
        String code="",help="Start a new login. This separate client may not be accepted.";
        try{Object error=new JSONObject(body).opt("error");if(error instanceof String)code=(String)error;}
        catch(Exception ignored){}
        switch(code){
            case "invalid_client":help="The account service rejected this client's authentication.";break;
            case "invalid_grant":help="The login code or refresh token was rejected. Codes may expire or be used only once; start a new login.";break;
            case "invalid_request":help="The account service rejected the request parameters.";break;
            case "invalid_scope":help="The account service rejected the requested permissions.";break;
            case "unauthorized_client":help="The account service does not permit this client to use this login flow.";break;
            case "unsupported_grant_type":help="The account service does not support this token request type.";break;
            case "access_denied":help="Login access was denied.";break;
            case "temporarily_unavailable":case "server_error":help="The account service reported a temporary problem. Try a new login later.";break;
            default:code="";
        }
        return stage+" failed (HTTP "+status+(code.isEmpty()?"":" · "+code)+"). "+help;
    }
    private OAuthError(){}
}
