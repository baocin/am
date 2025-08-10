package red.steele.loom.wearable.data.database.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.ColumnInfo

@Entity(tableName = "heart_rate_readings")
data class HeartRateEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "recorded_at")
    val recordedAt: String,

    @ColumnInfo(name = "bpm")
    val bpm: Int,

    @ColumnInfo(name = "confidence")
    val confidence: Float?,

    @ColumnInfo(name = "source")
    val source: String,

    @ColumnInfo(name = "timestamp")
    val timestamp: String?,

    @ColumnInfo(name = "synced")
    val synced: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
