package red.steele.loom.wearable.data.database.dao

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import red.steele.loom.wearable.data.database.entities.HeartRateEntity

@Dao
interface HeartRateDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(heartRate: HeartRateEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(heartRates: List<HeartRateEntity>)

    @Query("SELECT * FROM heart_rate_readings WHERE synced = 0 ORDER BY created_at ASC LIMIT :limit")
    suspend fun getUnsynced(limit: Int = 100): List<HeartRateEntity>

    @Query("UPDATE heart_rate_readings SET synced = 1 WHERE id IN (:ids)")
    suspend fun markAsSynced(ids: List<String>)

    @Query("DELETE FROM heart_rate_readings WHERE synced = 1 AND created_at < :timestamp")
    suspend fun deleteSyncedOlderThan(timestamp: Long)

    @Query("SELECT COUNT(*) FROM heart_rate_readings WHERE synced = 0")
    fun getUnsyncedCount(): Flow<Int>

    @Query("SELECT * FROM heart_rate_readings ORDER BY created_at DESC LIMIT :limit")
    fun getRecent(limit: Int = 50): Flow<List<HeartRateEntity>>
}
