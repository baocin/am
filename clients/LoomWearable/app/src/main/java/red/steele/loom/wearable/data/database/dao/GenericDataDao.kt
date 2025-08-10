package red.steele.loom.wearable.data.database.dao

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import red.steele.loom.wearable.data.database.entities.GenericDataEntity

@Dao
interface GenericDataDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(data: GenericDataEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(dataList: List<GenericDataEntity>)

    @Query("SELECT * FROM generic_data WHERE synced = 0 ORDER BY created_at ASC LIMIT :limit")
    suspend fun getUnsynced(limit: Int = 100): List<GenericDataEntity>

    @Query("UPDATE generic_data SET synced = 1 WHERE id IN (:ids)")
    suspend fun markAsSynced(ids: List<String>)

    @Query("DELETE FROM generic_data WHERE synced = 1 AND created_at < :timestamp")
    suspend fun deleteSyncedOlderThan(timestamp: Long)

    @Query("SELECT COUNT(*) FROM generic_data WHERE synced = 0")
    fun getUnsyncedCount(): Flow<Int>

    @Query("SELECT * FROM generic_data WHERE data_type = :dataType ORDER BY created_at DESC LIMIT :limit")
    fun getRecentByType(dataType: String, limit: Int = 50): Flow<List<GenericDataEntity>>
}
