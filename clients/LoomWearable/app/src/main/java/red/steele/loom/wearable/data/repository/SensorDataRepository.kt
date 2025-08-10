package red.steele.loom.wearable.data.repository

import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import red.steele.loom.wearable.data.database.LoomDatabase
import red.steele.loom.wearable.data.database.entities.GenericDataEntity
import red.steele.loom.wearable.data.database.mappers.*
import red.steele.loom.wearable.data.models.*
import java.util.UUID

class SensorDataRepository(
    private val database: LoomDatabase
) {
    companion object {
        private const val TAG = "SensorDataRepository"
        private const val CLEANUP_THRESHOLD_DAYS = 7
    }

    private val gson = Gson()
    private val heartRateDao = database.heartRateDao()
    private val gpsDao = database.gpsDao()
    private val sleepStateDao = database.sleepStateDao()
    private val powerEventDao = database.powerEventDao()
    private val genericDataDao = database.genericDataDao()

    // Save operations
    suspend fun saveHeartRate(reading: HeartRateReading) {
        try {
            heartRateDao.insert(reading.toEntity())
            Log.d(TAG, "Saved heart rate reading: ${reading.bpm} bpm")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving heart rate", e)
        }
    }

    suspend fun saveGPS(reading: GPSReading) {
        try {
            gpsDao.insert(reading.toEntity())
            Log.d(TAG, "Saved GPS reading: ${reading.latitude}, ${reading.longitude}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving GPS", e)
        }
    }

    suspend fun saveSleepState(state: SleepState) {
        try {
            sleepStateDao.insert(state.toEntity())
            Log.d(TAG, "Saved sleep state: ${state.state}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving sleep state", e)
        }
    }

    suspend fun savePowerEvent(event: PowerEvent) {
        try {
            powerEventDao.insert(event.toEntity())
            Log.d(TAG, "Saved power event: ${event.eventType}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving power event", e)
        }
    }

    suspend fun saveGenericData(dataType: String, data: Any, deviceId: String, recordedAt: String) {
        try {
            // Validate dataType before saving
            if (dataType.isBlank()) {
                Log.e(TAG, "Cannot save generic data - dataType is blank")
                return
            }

            if (!MessageTypes.isValid(dataType)) {
                Log.w(TAG, "Saving generic data with potentially invalid dataType: $dataType")
            }

            val entity = GenericDataEntity(
                id = UUID.randomUUID().toString(),
                deviceId = deviceId,
                dataType = dataType,
                recordedAt = recordedAt,
                dataJson = gson.toJson(data),
                timestamp = recordedAt,
                synced = false
            )
            genericDataDao.insert(entity)
            Log.d(TAG, "Saved generic data: $dataType")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving generic data", e)
        }
    }

    // Get unsynced data
    suspend fun getUnsyncedHeartRates(limit: Int = 100): List<HeartRateReading> {
        return heartRateDao.getUnsynced(limit).map { it.toReading() }
    }

    suspend fun getUnsyncedGPS(limit: Int = 100): List<GPSReading> {
        return gpsDao.getUnsynced(limit).map { it.toReading() }
    }

    suspend fun getUnsyncedSleepStates(limit: Int = 100): List<SleepState> {
        return sleepStateDao.getUnsynced(limit).map { it.toSleepState() }
    }

    suspend fun getUnsyncedPowerEvents(limit: Int = 100): List<PowerEvent> {
        return powerEventDao.getUnsynced(limit).map { it.toPowerEvent() }
    }

    suspend fun getUnsyncedGenericData(limit: Int = 100): List<GenericDataEntity> {
        return genericDataDao.getUnsynced(limit)
    }

    // Mark as synced
    suspend fun markHeartRatesAsSynced(ids: List<String>) {
        heartRateDao.markAsSynced(ids)
    }

    suspend fun markGPSAsSynced(ids: List<String>) {
        gpsDao.markAsSynced(ids)
    }

    suspend fun markSleepStatesAsSynced(ids: List<String>) {
        sleepStateDao.markAsSynced(ids)
    }

    suspend fun markPowerEventsAsSynced(ids: List<String>) {
        powerEventDao.markAsSynced(ids)
    }

    suspend fun markGenericDataAsSynced(ids: List<String>) {
        genericDataDao.markAsSynced(ids)
    }

    // Get unsynced counts
    fun getUnsyncedHeartRateCount(): Flow<Int> = heartRateDao.getUnsyncedCount()
    fun getUnsyncedGPSCount(): Flow<Int> = gpsDao.getUnsyncedCount()
    fun getUnsyncedSleepStateCount(): Flow<Int> = sleepStateDao.getUnsyncedCount()
    fun getUnsyncedPowerEventCount(): Flow<Int> = powerEventDao.getUnsyncedCount()
    fun getUnsyncedGenericDataCount(): Flow<Int> = genericDataDao.getUnsyncedCount()

    // Get recent data for display
    fun getRecentHeartRates(limit: Int = 50): Flow<List<HeartRateReading>> {
        return heartRateDao.getRecent(limit).map { entities ->
            entities.map { it.toReading() }
        }
    }

    fun getRecentGPS(limit: Int = 50): Flow<List<GPSReading>> {
        return gpsDao.getRecent(limit).map { entities ->
            entities.map { it.toReading() }
        }
    }

    // Cleanup old synced data
    suspend fun cleanupOldData() {
        val cutoffTime = System.currentTimeMillis() - (CLEANUP_THRESHOLD_DAYS * 24 * 60 * 60 * 1000L)

        try {
            heartRateDao.deleteSyncedOlderThan(cutoffTime)
            gpsDao.deleteSyncedOlderThan(cutoffTime)
            sleepStateDao.deleteSyncedOlderThan(cutoffTime)
            powerEventDao.deleteSyncedOlderThan(cutoffTime)
            genericDataDao.deleteSyncedOlderThan(cutoffTime)

            Log.d(TAG, "Cleaned up old synced data older than $CLEANUP_THRESHOLD_DAYS days")
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up old data", e)
        }
    }

    // Get total unsynced count across all data types
    suspend fun getTotalUnsyncedCount(): Int {
        return try {
            val heartRateCount = heartRateDao.getUnsyncedCount().first()
            val gpsCount = gpsDao.getUnsyncedCount().first()
            val sleepStateCount = sleepStateDao.getUnsyncedCount().first()
            val powerEventCount = powerEventDao.getUnsyncedCount().first()
            val genericDataCount = genericDataDao.getUnsyncedCount().first()

            heartRateCount + gpsCount + sleepStateCount + powerEventCount + genericDataCount
        } catch (e: Exception) {
            Log.e(TAG, "Error getting unsynced count", e)
            0
        }
    }
}
