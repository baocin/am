package red.steele.loom.wearable.data.models

enum class PollingFrequency(
    val displayName: String,
    val heartRateIntervalMs: Long,
    val gpsIntervalMs: Long,
    val sleepDetectionIntervalMs: Long
) {
    HIGH(
        displayName = "High (1s)",
        heartRateIntervalMs = 1000L,        // 1 second
        gpsIntervalMs = 5000L,              // 5 seconds
        sleepDetectionIntervalMs = 30000L   // 30 seconds
    ),
    MEDIUM(
        displayName = "Medium (5s)",
        heartRateIntervalMs = 5000L,        // 5 seconds
        gpsIntervalMs = 10000L,             // 10 seconds
        sleepDetectionIntervalMs = 60000L   // 1 minute
    ),
    LOW(
        displayName = "Low (10s)",
        heartRateIntervalMs = 10000L,       // 10 seconds
        gpsIntervalMs = 30000L,             // 30 seconds
        sleepDetectionIntervalMs = 120000L  // 2 minutes
    ),
    BATTERY_SAVER(
        displayName = "Battery Saver (30s)",
        heartRateIntervalMs = 30000L,       // 30 seconds
        gpsIntervalMs = 60000L,             // 1 minute
        sleepDetectionIntervalMs = 300000L  // 5 minutes
    );
    
    companion object {
        fun fromOrdinal(ordinal: Int): PollingFrequency {
            return values().getOrNull(ordinal) ?: MEDIUM
        }
    }
}