package red.steele.loom.wearable.data.models

/**
 * Valid message types that map to server endpoints.
 * These must match the MESSAGE_TYPE_MAPPINGS in the server's unified_ingestion.py
 */
object MessageTypes {
    val VALID_MESSAGE_TYPES = setOf(
        "heartrate",
        "heart_rate",
        "gps", 
        "gps_reading",
        "accelerometer",
        "power_event",
        "power_state", 
        "sleep",
        "sleep_state",
        "wifi_state",
        "bluetooth_scan",
        "on_body_status",
        "temperature",
        "barometer",
        "light",
        "gyroscope", 
        "magnetometer",
        "steps",
        "blood_oxygen",
        "blood_pressure",
        "body_weight"
    )
    
    fun isValid(messageType: String?): Boolean {
        return messageType != null && messageType in VALID_MESSAGE_TYPES
    }
}