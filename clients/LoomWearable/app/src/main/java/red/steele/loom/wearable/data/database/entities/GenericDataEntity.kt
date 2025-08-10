package red.steele.loom.wearable.data.database.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.ColumnInfo

@Entity(tableName = "generic_data")
data class GenericDataEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "data_type")
    val dataType: String,

    @ColumnInfo(name = "recorded_at")
    val recordedAt: String,

    @ColumnInfo(name = "data_json")
    val dataJson: String, // JSON serialized data

    @ColumnInfo(name = "timestamp")
    val timestamp: String?,

    @ColumnInfo(name = "synced")
    val synced: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
