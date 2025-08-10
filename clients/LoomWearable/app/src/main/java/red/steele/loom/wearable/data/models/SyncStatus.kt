package red.steele.loom.wearable.data.models

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine

data class SyncStatus(
    val heartRateUnsynced: Int = 0,
    val gpsUnsynced: Int = 0,
    val sleepStateUnsynced: Int = 0,
    val powerEventUnsynced: Int = 0,
    val genericDataUnsynced: Int = 0
) {
    val totalUnsynced: Int
        get() = heartRateUnsynced + gpsUnsynced + sleepStateUnsynced + 
                powerEventUnsynced + genericDataUnsynced
    
    val hasPendingData: Boolean
        get() = totalUnsynced > 0
}

fun combineSyncStatus(
    heartRateCount: Flow<Int>,
    gpsCount: Flow<Int>,
    sleepStateCount: Flow<Int>,
    powerEventCount: Flow<Int>,
    genericDataCount: Flow<Int>
): Flow<SyncStatus> {
    return combine(
        heartRateCount,
        gpsCount,
        sleepStateCount,
        powerEventCount,
        genericDataCount
    ) { hr, gps, sleep, power, generic ->
        SyncStatus(
            heartRateUnsynced = hr,
            gpsUnsynced = gps,
            sleepStateUnsynced = sleep,
            powerEventUnsynced = power,
            genericDataUnsynced = generic
        )
    }
}