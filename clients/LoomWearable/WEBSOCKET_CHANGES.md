# WebSocket Changes Summary

## Changes Made to Fix WebSocket Communication

### 1. Removed Batching (Per User Request)
- **Removed all batch sending functionality**
- Now sends each data item individually with a 50ms delay between messages
- Updated `syncPendingData()` to send items one by one instead of in batches

### 2. Fixed WebSocket Message Format
- Added required `id` field to `WebSocketMessage` data class
- Updated all message creation to include unique IDs (format: `${timestamp}_${type}`)
- Fixed compilation errors related to missing `id` parameter

### 3. Fixed Ping/Pong Health Check
- **Removed application-level ping messages** that were causing server errors
- Now only responds to server-initiated health check pings
- Fixed health check to properly track server pings instead of sending client pings

### 4. Updated Message Type Mappings
- Server now accepts both long and short versions of message types:
  - `gps` → `device.sensor.gps.raw`
  - `heart_rate` or `heartrate` → `device.health.heartrate.raw`
  - `power_event` → `device.state.power.raw`
  - `sleep_state` → `device.health.sleep.raw`
  - `on_body_status` → `device.sensor.on_body.raw`

### 5. Fixed Repository Methods
- Changed `syncedIds` from `MutableList<Long>` to `MutableList<String>` to match database schema
- Updated all `markAsSynced` methods to accept String IDs

### 6. Connection Improvements
- Increased timeout settings (30 seconds for connect/read/write)
- Added exponential backoff for reconnection attempts
- Better error handling and logging for connection failures

## Server-Side Changes

### Ingestion API
- Enhanced WebSocket logging to show connection details
- Fixed error handling for normal WebSocket closures (code 1000)
- Added connection counting and timestamp logging

### Voice API
- Fixed port configuration (8257 → 8000)
- Fixed model loading from Docker volume

## Current Message Flow

1. **Data Collection**: Sensors collect data (heart rate, GPS, etc.)
2. **Local Storage**: Data saved to Room database with `synced = false`
3. **WebSocket Connection**: Establishes connection to `/realtime/ws/{device_id}`
4. **Device Registration**: Sends device info on connection
5. **Individual Sending**: Each data item sent as separate WebSocket message
6. **Acknowledgment**: Server responds with `data_ack` containing message ID
7. **Mark Synced**: Update database to set `synced = true` for acknowledged items
8. **Periodic Sync**: Every 30 seconds, check for unsynced data and send

## Message Format Example

```json
{
  "id": "1234567890_heartrate",
  "type": "data",
  "payload": {
    "message_type_id": "heartrate",
    "data": {
      "bpm": 72,
      "device_id": "wearable_123",
      "timestamp": "2024-01-15T10:30:00Z"
    }
  },
  "metadata": {
    "device_id": "wearable_123",
    "source": "wearable"
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## Debugging Tips

1. Check logs for "Syncing X items individually" messages
2. Look for "Data acknowledged" messages with message IDs
3. Monitor "WebSocket connected" and connection status
4. Check for "Unknown message type" errors (indicates mapping issues)
5. Verify no "ping" errors in server logs
