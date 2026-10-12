package local.couponpocket;

import org.json.JSONArray;

/** Ordinary native loyalty QR, with payment basket and eTicket suffix disabled. */
public final class LoyaltyCard {
    public static String parse(String body) throws Exception {
        String text=body.trim(),id;
        if(text.startsWith("\"")){
            JSONArray scalar=new JSONArray("["+text+"]");
            if(scalar.length()!=1||!(scalar.get(0) instanceof String))throw new IllegalArgumentException("Unsupported loyalty response.");
            id=scalar.getString(0);
        }else {
            // Preserve leading zeroes: do not parse loyalty identifiers as numbers.
            if(!text.matches("[0-9]+"))throw new IllegalArgumentException("Unsupported loyalty response. Import your existing card instead.");
            id=text;
        }
        if(id.isEmpty()||id.length()>256||!id.matches("[\\x21-\\x7E]+"))throw new IllegalArgumentException("Invalid loyalty identifier.");
        return id;
    }
    private LoyaltyCard(){}
}
