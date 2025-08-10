package red.steele.loom.wearable.data.database.mappers

import red.steele.loom.wearable.data.database.entities.*
import red.steele.loom.wearable.data.models.*

// HeartRate mappers
fun HeartRateReading.toEntity(): HeartRateEntity {
    return HeartRateEntity(
        id = messageId,
        deviceId = deviceId,
        recordedAt = recordedAt,
        bpm = bpm,
        confidence = confidence,
        source = source,
        timestamp = timestamp,
        synced = false
    )
}

fun HeartRateEntity.toReading(): HeartRateReading {
    return HeartRateReading(
        deviceId = deviceId,
        recordedAt = recordedAt,
        bpm = bpm,
        confidence = confidence,
        source = source,
        timestamp = timestamp,
        messageId = id
    )
}

// GPS mappers
fun GPSReading.toEntity(): GPSEntity {
    return GPSEntity(
        id = messageId,
        deviceId = deviceId,
        recordedAt = recordedAt,
        latitude = latitude,
        longitude = longitude,
        altitude = altitude,
        accuracy = accuracy,
        heading = heading,
        speed = speed,
        timestamp = timestamp,
        synced = false
    )
}

fun GPSEntity.toReading(): GPSReading {
    return GPSReading(
        deviceId = deviceId,
        recordedAt = recordedAt,
        latitude = latitude,
        longitude = longitude,
        altitude = altitude,
        accuracy = accuracy,
        heading = heading,
        speed = speed,
        timestamp = timestamp,
        messageId = id
    )
}

// SleepState mappers
fun SleepState.toEntity(): SleepStateEntity {
    return SleepStateEntity(
        id = messageId,
        deviceId = deviceId,
        recordedAt = recordedAt,
        state = state,
        confidence = confidence,
        duration = duration,
        timestamp = timestamp,
        synced = false
    )
}

fun SleepStateEntity.toSleepState(): SleepState {
    return SleepState(
        deviceId = deviceId,
        recordedAt = recordedAt,
        state = state,
        confidence = confidence,
        duration = duration,
        timestamp = timestamp,
        messageId = id
    )
}

// PowerEvent mappers
fun PowerEvent.toEntity(): PowerEventEntity {
    return PowerEventEntity(
        id = messageId,
        deviceId = deviceId,
        recordedAt = recordedAt,
        eventType = eventType,
        batteryLevel = batteryLevel,
        isCharging = isCharging,
        timestamp = timestamp,
        synced = false
    )
}

fun PowerEventEntity.toPowerEvent(): PowerEvent {
    return PowerEvent(
        deviceId = deviceId,
        recordedAt = recordedAt,
        eventType = eventType,
        batteryLevel = batteryLevel,
        isCharging = isCharging,
        timestamp = timestamp,
        messageId = id
    )
}
