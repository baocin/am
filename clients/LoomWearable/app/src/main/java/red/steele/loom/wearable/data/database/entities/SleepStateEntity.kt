package red.steele.loom.wearable.data.database.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.ColumnInfo

@Entity(tableName = "sleep_states")
data class SleepStateEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "recorded_at")
    val recordedAt: String,

    @ColumnInfo(name = "state")
    val state: String, // "awake", "light_sleep", "deep_sleep", "rem"

    @ColumnInfo(name = "confidence")
    val confidence: Float?,

    @ColumnInfo(name = "duration")
    val duration: Long?, // duration in current state in milliseconds

    @ColumnInfo(name = "timestamp")
    val timestamp: String?,

    @ColumnInfo(name = "synced")
    val synced: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
