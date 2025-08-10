# WebSocket "Unknown message type: None" Fix

## Problem
The Android wearable app was sending WebSocket messages that resulted in "Unknown message type: None" errors from the server. This occurred when syncing power events, generic data, and heart rate readings.

## Root Cause
The issue was in the `syncGenericDataIndividually()` method in `UnifiedWebSocketService.kt`. When generic data entities had null or invalid `dataType` values, the `sendData()` method would construct WebSocket messages with null `message_type_id` fields, causing server validation failures.

## Error Flow
1. Wearable calls `syncGenericDataIndividually()`
2. Method loops through `GenericDataEntity` objects
3. Some entities have null/invalid `dataType` values
4. `sendData(entity.dataType, parsedData)` called with null dataType
5. WebSocket message constructed with `"message_type_id" to null`
6. Server rejects message: "Unknown message type: None"

## Solution Implemented

### 1. Centralized Message Type Validation
Created `MessageTypes.kt` with centralized validation:
```kotlin
object MessageTypes {
    val VALID_MESSAGE_TYPES = setOf(
        "heartrate", "heart_rate", "gps", "gps_reading", "accelerometer",
        "power_event", "power_state", "sleep", "sleep_state",
        "wifi_state", "bluetooth_scan", "on_body_status",
        // ... additional types
    )
    
    fun isValid(messageType: String?): Boolean {
        return messageType != null && messageType in VALID_MESSAGE_TYPES
    }
}
```

### 2. Validation in syncGenericDataIndividually()
Added validation to skip invalid records:
```kotlin
private suspend fun syncGenericDataIndividually(data: List<GenericDataEntity>) {
    for (entity in data) {
        // Validate dataType before processing
        if (entity.dataType.isNullOrBlank()) {
            Log.w(TAG, "Skipping generic data ${entity.id} - dataType is null or empty")
            continue
        }

        if (!MessageTypes.isValid(entity.dataType)) {
            Log.w(TAG, "Skipping generic data ${entity.id} - invalid dataType: ${entity.dataType}")
            continue
        }
        
        // Process valid data
        val parsedData = gson.fromJson(entity.dataJson, Any::class.java)
        sendData(entity.dataType, parsedData)
    }
}
```

### 3. Validation in sendData()
Added defensive validation:
```kotlin
fun sendData(dataType: String?, data: Any) {
    // Validate dataType before sending
    if (dataType.isNullOrBlank()) {
        Log.e(TAG, "Cannot send data - dataType is null or empty")
        return
    }

    if (!MessageTypes.isValid(dataType)) {
        Log.e(TAG, "Cannot send data - invalid dataType: $dataType")
        return
    }
    
    // Construct and send valid message
}
```

### 4. Validation in saveGenericData()
Added preventive validation:
```kotlin
suspend fun saveGenericData(dataType: String, data: Any, deviceId: String, recordedAt: String) {
    // Validate dataType before saving
    if (dataType.isBlank()) {
        Log.e(TAG, "Cannot save generic data - dataType is blank")
        return
    }

    if (!MessageTypes.isValid(dataType)) {
        Log.w(TAG, "Saving generic data with potentially invalid dataType: $dataType")
    }
    
    // Save to database
}
```

## Files Modified
1. `UnifiedWebSocketService.kt` - Added validation in sync and send methods
2. `SensorDataRepository.kt` - Added validation when saving generic data
3. `MessageTypes.kt` - New centralized validation constants

## Expected Behavior After Fix
1. ✅ Invalid generic data records are skipped with warning logs
2. ✅ Only valid message types are sent to server
3. ✅ Sync continues with remaining valid data
4. ✅ No more "Unknown message type: None" errors
5. ✅ Clear logging of skipped invalid records for debugging

## Testing Recommendations
1. **Check logs** for warning messages about skipped invalid data
2. **Monitor server** for reduction in "Unknown message type" errors
3. **Verify sync** continues working for valid data types
4. **Review database** for any existing records with null/invalid dataType values

## Prevention
- Message type validation is now centralized and reused
- Defensive programming prevents null values from reaching the server
- Warning logs help identify sources of invalid data
- Server message type mappings are documented in wearable code