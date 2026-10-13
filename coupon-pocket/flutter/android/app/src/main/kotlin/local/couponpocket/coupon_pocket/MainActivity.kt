package local.couponpocket.coupon_pocket

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import local.couponpocket.Vault
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

class MainActivity : FlutterActivity() {
    private var pendingImage: MethodChannel.Result? = null
    companion object { private val worker = Executors.newSingleThreadExecutor() }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coupon_pocket/card_import")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick" || pendingImage != null) {
                    result.error("image", "Image picker unavailable.", null)
                } else {
                    pendingImage = result
                    try {
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE); type = "image/*"
                        }, 1993)
                    } catch (_: Exception) { pendingImage = null; result.error("image", "Could not open image picker.", null) }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coupon_pocket/loyalty")
            .setMethodCallHandler { call, result ->
                val country = call.argument<String>("country") ?: ""
                val language = call.argument<String>("language") ?: ""
                val url = call.argument<String>("url") ?: ""
                val authorization = call.argument<String>("authorization") ?: ""
                val paths = listOf("https://profile.lidlplus.com/api/v1/$country/loyalty", "https://profile.lidlplus.com/profile/api/v1/$country/loyalty")
                if (call.method != "get" || !country.matches(Regex("[A-Z]{2}")) || !language.matches(Regex("[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*")) || url !in paths || !authorization.startsWith("Bearer ") || authorization.length > 65536 || authorization.any { it.code < 32 || it.code > 126 }) {
                    result.error("card", "Unsupported account card request.", null)
                    return@setMethodCallHandler
                }
                worker.execute {
                    var connection: HttpsURLConnection? = null
                    try {
                        connection = URL(url).openConnection() as HttpsURLConnection
                        connection.instanceFollowRedirects = false
                        connection.requestMethod = "GET"
                        connection.connectTimeout = 15000
                        connection.readTimeout = 20000
                        connection.useCaches = false
                        connection.setRequestProperty("Accept", "application/json")
                        connection.setRequestProperty("User-Agent", "LidlPlusPlus/0.14.2 (Android)")
                        connection.setRequestProperty("Authorization", authorization)
                        connection.setRequestProperty("Country", country)
                        connection.setRequestProperty("Accept-Language", language)
                        val status = connection.responseCode
                        if (status in 300..399) throw IllegalArgumentException()
                        val bytes = ByteArrayOutputStream()
                        val stream = if (status >= 400) connection.errorStream else connection.inputStream
                        stream?.use { input ->
                            val chunk = ByteArray(8192)
                            while (true) {
                                val n = input.read(chunk); if (n < 0) break
                                if (bytes.size() + n > 4 * 1024 * 1024) throw IllegalArgumentException()
                                bytes.write(chunk, 0, n)
                            }
                        }
                        val response = bytes.toString("UTF-8")
                        runOnUiThread { result.success(mapOf("status" to status, "body" to response)) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("card", "Could not load the account card.", null) }
                    } finally { connection?.disconnect() }
                }
            }
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
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1993) return
        val result = pendingImage ?: return
        pendingImage = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        worker.execute {
            try {
                val source = ByteArrayOutputStream()
                contentResolver.openInputStream(uri)?.use { input ->
                    val chunk = ByteArray(8192)
                    while (true) {
                        val n = input.read(chunk); if (n < 0) break
                        if (source.size() + n > 4 * 1024 * 1024) throw IllegalArgumentException()
                        source.write(chunk, 0, n)
                    }
                } ?: throw IllegalArgumentException()
                val bytes = source.toByteArray()
                val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                if (opts.outWidth <= 0 || opts.outHeight <= 0 || opts.outWidth > 8192 || opts.outHeight > 8192 || opts.outWidth.toLong() * opts.outHeight > 16000000) throw IllegalArgumentException()
                opts.inSampleSize = 1
                while (opts.outWidth / opts.inSampleSize > 1024 || opts.outHeight / opts.inSampleSize > 1024) opts.inSampleSize *= 2
                opts.inJustDecodeBounds = false
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: throw IllegalArgumentException()
                val png = ByteArrayOutputStream()
                try { bitmap.compress(Bitmap.CompressFormat.PNG, 100, png) } finally { bitmap.recycle() }
                if (png.size() > 512 * 1024) throw IllegalArgumentException()
                runOnUiThread { result.success(png.toByteArray()) }
            } catch (_: Exception) { runOnUiThread { result.error("image", "Choose a smaller cropped QR image.", null) } }
        }
    }

}
