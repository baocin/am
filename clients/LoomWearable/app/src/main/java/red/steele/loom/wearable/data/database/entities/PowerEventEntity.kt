package red.steele.loom.wearable.data.database.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.ColumnInfo

@Entity(tableName = "power_events")
data class PowerEventEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "recorded_at")
    val recordedAt: String,

    @ColumnInfo(name = "event_type")
    val eventType: String, // "wake", "sleep", "charging_started", "charging_stopped"

    @ColumnInfo(name = "battery_level")
    val batteryLevel: Int?,

    @ColumnInfo(name = "is_charging")
    val isCharging: Boolean?,

    @ColumnInfo(name = "timestamp")
    val timestamp: String?,

    @ColumnInfo(name = "synced")
    val synced: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
