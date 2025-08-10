package red.steele.loom.wearable.data.database.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.ColumnInfo

@Entity(tableName = "gps_readings")
data class GPSEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "recorded_at")
    val recordedAt: String,

    @ColumnInfo(name = "latitude")
    val latitude: Double,

    @ColumnInfo(name = "longitude")
    val longitude: Double,

    @ColumnInfo(name = "altitude")
    val altitude: Double?,

    @ColumnInfo(name = "accuracy")
    val accuracy: Float?,

    @ColumnInfo(name = "heading")
    val heading: Float?,

    @ColumnInfo(name = "speed")
    val speed: Float?,

    @ColumnInfo(name = "timestamp")
    val timestamp: String?,

    @ColumnInfo(name = "synced")
    val synced: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
