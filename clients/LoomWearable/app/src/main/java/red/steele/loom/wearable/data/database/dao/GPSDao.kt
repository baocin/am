package red.steele.loom.wearable.data.database.dao

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import red.steele.loom.wearable.data.database.entities.GPSEntity

@Dao
interface GPSDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(gps: GPSEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(gpsReadings: List<GPSEntity>)

    @Query("SELECT * FROM gps_readings WHERE synced = 0 ORDER BY created_at ASC LIMIT :limit")
    suspend fun getUnsynced(limit: Int = 100): List<GPSEntity>

    @Query("UPDATE gps_readings SET synced = 1 WHERE id IN (:ids)")
    suspend fun markAsSynced(ids: List<String>)

    @Query("DELETE FROM gps_readings WHERE synced = 1 AND created_at < :timestamp")
    suspend fun deleteSyncedOlderThan(timestamp: Long)

    @Query("SELECT COUNT(*) FROM gps_readings WHERE synced = 0")
    fun getUnsyncedCount(): Flow<Int>

    @Query("SELECT * FROM gps_readings ORDER BY created_at DESC LIMIT :limit")
    fun getRecent(limit: Int = 50): Flow<List<GPSEntity>>
}
