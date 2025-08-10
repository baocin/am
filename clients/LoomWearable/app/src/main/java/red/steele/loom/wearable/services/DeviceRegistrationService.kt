package red.steele.loom.wearable.services

import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

data class DeviceRegistration(
    @SerializedName("device_id") val deviceId: String,
    @SerializedName("name") val name: String = "Loom Wearable",
    @SerializedName("device_type") val deviceType: String = "other",  // API only accepts specific values
    @SerializedName("manufacturer") val manufacturer: String = android.os.Build.MANUFACTURER,
    @SerializedName("model") val model: String = android.os.Build.MODEL,
    @SerializedName("os_version") val osVersion: String = "Android ${android.os.Build.VERSION.RELEASE}",
    @SerializedName("app_version") val appVersion: String = "1.0.0",
    @SerializedName("platform") val platform: String = "android_wear",
    @SerializedName("metadata") val metadata: Map<String, Any> = mapOf(
        "device_subtype" to "wearable",
        "capabilities" to listOf("heart_rate", "gps", "sleep_detection", "power_monitoring", "on_body_detection")
    )
)

class DeviceRegistrationService {
    companion object {
        private const val TAG = "DeviceRegistration"
    }

    private val gson = Gson()
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    suspend fun registerDevice(
        deviceId: String,
        baseUrl: String
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Registering device $deviceId with server $baseUrl")

            val registration = DeviceRegistration(deviceId = deviceId)
            val jsonBody = gson.toJson(registration)

            val request = Request.Builder()
                .url("$baseUrl/devices/")
                .header("X-API-Key", "apikeyhere")
                .post(jsonBody.toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()

            if (response.isSuccessful) {
                Log.d(TAG, "Device registered successfully")
                true
            } else {
                val responseBody = response.body?.string() ?: "No response body"
                Log.e(TAG, "Device registration failed: ${response.code} ${response.message}")
                Log.e(TAG, "Response body: $responseBody")

                // If device already exists (409), consider it successful
                // Also handle 422 (validation error) and 401 (unauthorized)
                when (response.code) {
                    409 -> {
                        Log.d(TAG, "Device already exists, considering as success")
                        true
                    }
                    401 -> {
                        Log.e(TAG, "Unauthorized - API key may be required")
                        false
                    }
                    422 -> {
                        Log.e(TAG, "Validation error - check device_type and other fields")
                        false
                    }
                    else -> false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error registering device", e)
            false
        }
    }
}
