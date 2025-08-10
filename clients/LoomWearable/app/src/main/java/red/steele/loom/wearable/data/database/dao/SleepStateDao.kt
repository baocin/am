package red.steele.loom.wearable.data.database.dao

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import red.steele.loom.wearable.data.database.entities.SleepStateEntity

@Dao
interface SleepStateDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(sleepState: SleepStateEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(sleepStates: List<SleepStateEntity>)

    @Query("SELECT * FROM sleep_states WHERE synced = 0 ORDER BY created_at ASC LIMIT :limit")
    suspend fun getUnsynced(limit: Int = 100): List<SleepStateEntity>

    @Query("UPDATE sleep_states SET synced = 1 WHERE id IN (:ids)")
    suspend fun markAsSynced(ids: List<String>)

    @Query("DELETE FROM sleep_states WHERE synced = 1 AND created_at < :timestamp")
    suspend fun deleteSyncedOlderThan(timestamp: Long)

    @Query("SELECT COUNT(*) FROM sleep_states WHERE synced = 0")
    fun getUnsyncedCount(): Flow<Int>

    @Query("SELECT * FROM sleep_states ORDER BY created_at DESC LIMIT :limit")
    fun getRecent(limit: Int = 50): Flow<List<SleepStateEntity>>
}
