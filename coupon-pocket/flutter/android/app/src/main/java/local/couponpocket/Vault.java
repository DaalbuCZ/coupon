package local.couponpocket;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import org.json.JSONObject;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import java.io.File;
import java.nio.file.Files;
import java.security.KeyStore;
import java.util.Arrays;

/** Private files protected with a non-exportable Android Keystore AES key. */
public final class Vault implements Storage {
    private final File directory;
    private static final String ALIAS="coupon-pocket-storage-v1";
    public Vault(Context context) { directory=context.getNoBackupFilesDir(); }
    private SecretKey key() throws Exception {
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        if (ks.containsAlias(ALIAS)) return (SecretKey)ks.getKey(ALIAS,null);
        KeyGenerator gen=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        gen.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return gen.generateKey();
    }
    public synchronized byte[] read(String name) throws Exception {
        File f=new File(directory,name);
        if (!f.exists()) return null;
        byte[] b=Files.readAllBytes(f.toPath());
        if (b.length<28) throw new SecurityException("Saved data is damaged. Clear local data to reset it.");
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Arrays.copyOf(b,12)));
        c.updateAAD(name.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        return c.doFinal(Arrays.copyOfRange(b,12,b.length));
    }
    public synchronized void write(String name, byte[] data) throws Exception {
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE,key());
        c.updateAAD(name.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        byte[] enc=c.doFinal(data), iv=c.getIV(), all=new byte[iv.length+enc.length];
        System.arraycopy(iv,0,all,0,iv.length);System.arraycopy(enc,0,all,iv.length,enc.length);
        File temp=new File(directory,name+".tmp");
        Files.write(temp.toPath(),all);
        Files.move(temp.toPath(),new File(directory,name).toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    }
    public JSONObject json(String name) throws Exception {
        byte[] b=read(name);return b==null?new JSONObject():new JSONObject(new String(b,java.nio.charset.StandardCharsets.UTF_8));
    }
    public void json(String name,JSONObject data) throws Exception {
        write(name,data.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
    public synchronized void delete(String name) { new File(directory,name).delete();new File(directory,name+".tmp").delete(); }
    public synchronized void clear() throws Exception {
        for (String n:new String[]{"session","pending","card-image","card-text","coupons","settings","loyalty","accounts","import","view","favourites"}) delete(n);
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);ks.deleteEntry(ALIAS);
    }
}
