package local.couponpocket.coupon_pocket

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import local.couponpocket.Vault
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    companion object { private val worker = Executors.newSingleThreadExecutor() }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val vault = Vault(applicationContext)
        val main = Handler(Looper.getMainLooper())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coupon_pocket/vault")
            .setMethodCallHandler { call, result ->
                val key = call.argument<String>("key")
                if (call.method != "clear" && (key == null || !key.matches(Regex("[a-z-]{1,32}")))) {
                    result.error("storage", "Invalid storage key.", null)
                    return@setMethodCallHandler
                }
                worker.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "read" -> vault.read(key!!)?.toString(Charsets.UTF_8)
                            "write" -> { vault.write(key!!, (call.argument<String>("value") ?: "").toByteArray(Charsets.UTF_8)); null }
                            "delete" -> { vault.delete(key!!); null }
                            "clear" -> { vault.delete("import"); vault.clear(); null }
                            else -> throw IllegalArgumentException()
                        }
                        main.post { result.success(value) }
                    } catch (_: Exception) { main.post { result.error("storage", "Could not access encrypted local data.", null) } }
                }
            }
    }
}
