package red.steele.loom.wearable.data.database.dao

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import red.steele.loom.wearable.data.database.entities.PowerEventEntity

@Dao
interface PowerEventDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(powerEvent: PowerEventEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(powerEvents: List<PowerEventEntity>)

    @Query("SELECT * FROM power_events WHERE synced = 0 ORDER BY created_at ASC LIMIT :limit")
    suspend fun getUnsynced(limit: Int = 100): List<PowerEventEntity>

    @Query("UPDATE power_events SET synced = 1 WHERE id IN (:ids)")
    suspend fun markAsSynced(ids: List<String>)

    @Query("DELETE FROM power_events WHERE synced = 1 AND created_at < :timestamp")
    suspend fun deleteSyncedOlderThan(timestamp: Long)

    @Query("SELECT COUNT(*) FROM power_events WHERE synced = 0")
    fun getUnsyncedCount(): Flow<Int>

    @Query("SELECT * FROM power_events ORDER BY created_at DESC LIMIT :limit")
    fun getRecent(limit: Int = 50): Flow<List<PowerEventEntity>>
}
