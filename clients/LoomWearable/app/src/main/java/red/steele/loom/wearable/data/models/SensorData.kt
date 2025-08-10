package red.steele.loom.wearable.data.models

import com.google.gson.annotations.SerializedName
import java.util.UUID

data class HeartRateReading(
    @SerializedName("device_id")
    val deviceId: String,
    @SerializedName("recorded_at")
    val recordedAt: String,
    val bpm: Int,
    val confidence: Float? = null,
    val source: String = "health_services",
    @SerializedName("timestamp")
    val timestamp: String? = null,
    @SerializedName("message_id")
    val messageId: String = UUID.randomUUID().toString(),
    @SerializedName("trace_id")
    val traceId: String? = null,
    @SerializedName("services_encountered")
    val servicesEncountered: List<String> = listOf("wearable-client"),
    @SerializedName("content_hash")
    val contentHash: String? = null,
    val metadata: Map<String, String>? = null
)

data class GPSReading(
    @SerializedName("device_id")
    val deviceId: String,
    @SerializedName("recorded_at")
    val recordedAt: String,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double? = null,
    val accuracy: Float? = null,
    val heading: Float? = null,
    val speed: Float? = null,
    @SerializedName("timestamp")
    val timestamp: String? = null,
    @SerializedName("message_id")
    val messageId: String = UUID.randomUUID().toString(),
    @SerializedName("trace_id")
    val traceId: String? = null,
    @SerializedName("services_encountered")
    val servicesEncountered: List<String> = listOf("wearable-client"),
    @SerializedName("content_hash")
    val contentHash: String? = null
)

data class SleepState(
    @SerializedName("device_id")
    val deviceId: String,
    @SerializedName("recorded_at")
    val recordedAt: String,
    val state: String, // "awake", "light_sleep", "deep_sleep", "rem"
    val confidence: Float? = null,
    val duration: Long? = null, // duration in current state in milliseconds
    @SerializedName("timestamp")
    val timestamp: String? = null,
    @SerializedName("message_id")
    val messageId: String = UUID.randomUUID().toString(),
    @SerializedName("trace_id")
    val traceId: String? = null,
    @SerializedName("services_encountered")
    val servicesEncountered: List<String> = listOf("wearable-client"),
    @SerializedName("content_hash")
    val contentHash: String? = null
)

data class PowerEvent(
    @SerializedName("device_id")
    val deviceId: String,
    @SerializedName("recorded_at")
    val recordedAt: String,
    @SerializedName("event_type")
    val eventType: String, // "wake", "sleep", "charging_started", "charging_stopped"
    @SerializedName("battery_level")
    val batteryLevel: Int? = null,
    @SerializedName("is_charging")
    val isCharging: Boolean? = null,
    @SerializedName("timestamp")
    val timestamp: String? = null,
    @SerializedName("message_id")
    val messageId: String = UUID.randomUUID().toString(),
    @SerializedName("trace_id")
    val traceId: String? = null,
    @SerializedName("services_encountered")
    val servicesEncountered: List<String> = listOf("wearable-client"),
    @SerializedName("content_hash")
    val contentHash: String? = null
)

data class WebSocketMessage(
    val id: String,
    @SerializedName("message_type")
    val type: String, // "data", "audio_chunk", "batch_data", "heartbeat"
    val payload: Any,
    val metadata: Map<String, Any>? = null,
    val timestamp: String
)

data class BatchData(
    @SerializedName("data_type")
    val dataType: String,
    val items: List<Any>,
    val count: Int
)
