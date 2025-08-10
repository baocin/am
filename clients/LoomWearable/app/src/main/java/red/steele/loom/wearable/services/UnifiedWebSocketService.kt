package red.steele.loom.wearable.services

import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import okhttp3.*
import red.steele.loom.wearable.data.database.entities.GenericDataEntity
import red.steele.loom.wearable.data.models.*
import red.steele.loom.wearable.data.repository.SensorDataRepository
import java.time.Instant
import java.util.concurrent.TimeUnit

class UnifiedWebSocketService(
    private val deviceId: String,
    private val baseUrl: String,
    private val repository: SensorDataRepository
) {
    companion object {
        private const val TAG = "UnifiedWebSocketService"
        private const val RECONNECT_INTERVAL = 15 * 60 * 1000L // 15 minutes
        private const val HEALTH_CHECK_INTERVAL = 5000L // 5 seconds
        private const val HEALTH_CHECK_TIMEOUT = 15000L // 15 seconds
        private const val SYNC_BATCH_SIZE = 50
        private const val INITIAL_SYNC_DELAY = 5000L // 5 seconds after connection
        private const val SYNC_INTERVAL = 30000L // 30 seconds
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val RETRY_DELAY = 5000L // 5 seconds between retries
    }

    private val gson = Gson()
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)  // Increase from default 10s to 30s
        .readTimeout(30, TimeUnit.SECONDS)     // Set a reasonable read timeout
        .writeTimeout(30, TimeUnit.SECONDS)    // Set a reasonable write timeout
        .pingInterval(30, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private var webSocket: WebSocket? = null
    private var lastPongReceived: Instant? = null

    private val _connectionStatus = MutableStateFlow(false)
    val connectionStatus: StateFlow<Boolean> = _connectionStatus.asStateFlow()

    private val _messages = MutableSharedFlow<WebSocketMessage>()
    val messages: SharedFlow<WebSocketMessage> = _messages.asSharedFlow()

    private val messageQueue = Channel<String>(Channel.UNLIMITED)

    private var healthCheckJob: Job? = null
    private var messageProcessorJob: Job? = null
    private var syncJob: Job? = null
    private var reconnectJob: Job? = null
    private var heartbeatJob: Job? = null

    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Track retry attempts for failed messages
    private val retryAttempts = mutableMapOf<String, Int>()

    fun connect() {
        Log.d(TAG, "Connecting to WebSocket at $baseUrl")

        val wsUrl = baseUrl
            .replace("http://", "ws://")
            .replace("https://", "wss://")

        val fullUrl = "$wsUrl/realtime/ws/$deviceId"
        Log.d(TAG, "Full WebSocket URL: $fullUrl")

        val request = Request.Builder()
            .url(fullUrl)
            .addHeader("X-Device-ID", deviceId)
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WebSocket connected")
                _connectionStatus.value = true
                cancelReconnectJob()
                startHealthCheck()
                startHeartbeat()
                startMessageProcessor()
                startDataSync()

                // Register device via WebSocket
                registerDevice()

                // Trigger immediate sync of pending data after a short delay
                coroutineScope.launch {
                    delay(INITIAL_SYNC_DELAY)
                    Log.d(TAG, "Performing initial sync of pending data")
                    syncPendingData()
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "Received message: $text")
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WebSocket failure: ${t.message}", t)
                Log.e(TAG, "Response: ${response?.code} ${response?.message}")
                Log.e(TAG, "URL was: $fullUrl")
                _connectionStatus.value = false
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "WebSocket closed: $code - $reason")
                _connectionStatus.value = false
                scheduleReconnect()
            }
        })
    }

    private fun handleMessage(text: String) {
        try {
            val message = gson.fromJson(text, Map::class.java)
            when (message["type"]) {
                "connection_established" -> {
                    Log.d(TAG, "Connection established with server")
                    val payload = message["payload"] as? Map<*, *>
                    val features = payload?.get("features") as? List<*>
                    Log.d(TAG, "Server features: $features")
                }
                "health_check_ping" -> {
                    // Update last received time when we get a ping from server
                    lastPongReceived = Instant.now()
                    // Respond to health check ping with pong
                    val pingId = (message["payload"] as? Map<*, *>)?.get("ping_id")
                    sendPong(pingId)
                }
                "pong" -> {
                    lastPongReceived = Instant.now()
                    Log.d(TAG, "Pong received")
                }
                "data_ack", "audio_ack" -> {
                    Log.d(TAG, "Data acknowledged: ${message["payload"]}")
                    val payload = message["payload"] as? Map<*, *>
                    val messageId = payload?.get("message_id") as? String
                    if (messageId != null) {
                        // Reset retry attempts on successful acknowledgment
                        retryAttempts.remove(messageId)
                    }
                }
                "error", "data_error" -> {
                    Log.e(TAG, "Server error: ${message["payload"]}")
                }
                "notification" -> {
                    coroutineScope.launch {
                        _messages.emit(WebSocketMessage(
                            id = message["id"] as? String ?: "${System.currentTimeMillis()}_notification",
                            type = "notification",
                            payload = message["payload"] ?: mapOf<String, Any>(),
                            metadata = message["metadata"] as? Map<String, Any>,
                            timestamp = Instant.now().toString()
                        ))
                    }
                }
                "heartbeat_ack" -> {
                    Log.d(TAG, "Heartbeat acknowledged")
                }
                "device_registered" -> {
                    Log.d(TAG, "Device registered successfully via WebSocket")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling message", e)
        }
    }

    private fun startHealthCheck() {
        healthCheckJob?.cancel()
        healthCheckJob = coroutineScope.launch {
            while (isActive) {
                delay(HEALTH_CHECK_INTERVAL)
                // The server sends health_check_ping messages, we respond with pongs
                // We don't need to send our own pings

                // Check if we've received any message recently (server sends pings every 5s)
                val lastPong = lastPongReceived
                if (lastPong != null &&
                    Instant.now().toEpochMilli() - lastPong.toEpochMilli() > HEALTH_CHECK_TIMEOUT) {
                    Log.w(TAG, "Health check timeout - no server pings received")
                    disconnect()
                    scheduleReconnect()
                }
            }
        }
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = coroutineScope.launch {
            while (isActive) {
                delay(1000) // Send heartbeat every second
                sendHeartbeat()
            }
        }
    }

    private fun startMessageProcessor() {
        messageProcessorJob?.cancel()
        messageProcessorJob = coroutineScope.launch {
            for (message in messageQueue) {
                val ws = webSocket
                if (_connectionStatus.value && ws != null) {
                    try {
                        val sent = ws.send(message)
                        if (!sent) {
                            Log.w(TAG, "Failed to send message through WebSocket")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending message", e)
                        _connectionStatus.value = false
                    }
                } else {
                    Log.d(TAG, "WebSocket not ready (connected=${_connectionStatus.value}, ws=${ws != null})")
                }
            }
        }
    }

    private fun startDataSync() {
        syncJob?.cancel()
        syncJob = coroutineScope.launch {
            while (isActive) {
                if (_connectionStatus.value) {
                    syncPendingData()
                }
                delay(SYNC_INTERVAL) // Check based on configured interval
            }
        }
    }

    private suspend fun syncPendingData() {
        try {
            Log.d(TAG, "Starting sync of pending data")
            var totalSynced = 0

            // Sync heart rate data - send individually
            val heartRates = repository.getUnsyncedHeartRates(SYNC_BATCH_SIZE)
            if (heartRates.isNotEmpty()) {
                Log.d(TAG, "Syncing ${heartRates.size} heart rate readings individually")
                val syncedIds = mutableListOf<String>()
                for (heartRate in heartRates) {
                    try {
                        sendData("heartrate", heartRate)
                        syncedIds.add(heartRate.messageId)
                        totalSynced++
                        delay(50) // Small delay between messages to avoid overwhelming
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending heart rate ${heartRate.messageId}", e)
                        break
                    }
                }
                if (syncedIds.isNotEmpty()) {
                    repository.markHeartRatesAsSynced(syncedIds)
                }
            }

            // Sync GPS data - send individually
            val gpsReadings = repository.getUnsyncedGPS(SYNC_BATCH_SIZE)
            if (gpsReadings.isNotEmpty()) {
                Log.d(TAG, "Syncing ${gpsReadings.size} GPS readings individually")
                val syncedIds = mutableListOf<String>()
                for (gps in gpsReadings) {
                    try {
                        sendData("gps", gps)
                        syncedIds.add(gps.messageId)
                        totalSynced++
                        delay(50) // Small delay between messages
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending GPS ${gps.messageId}", e)
                        break
                    }
                }
                if (syncedIds.isNotEmpty()) {
                    repository.markGPSAsSynced(syncedIds)
                }
            }

            // Sync sleep states - send individually
            val sleepStates = repository.getUnsyncedSleepStates(SYNC_BATCH_SIZE)
            if (sleepStates.isNotEmpty()) {
                Log.d(TAG, "Syncing ${sleepStates.size} sleep states individually")
                val syncedIds = mutableListOf<String>()
                for (sleep in sleepStates) {
                    try {
                        sendData("sleep_state", sleep)
                        syncedIds.add(sleep.messageId)
                        totalSynced++
                        delay(50) // Small delay between messages
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending sleep state ${sleep.messageId}", e)
                        break
                    }
                }
                if (syncedIds.isNotEmpty()) {
                    repository.markSleepStatesAsSynced(syncedIds)
                }
            }

            // Sync power events - send individually
            val powerEvents = repository.getUnsyncedPowerEvents(SYNC_BATCH_SIZE)
            if (powerEvents.isNotEmpty()) {
                Log.d(TAG, "Syncing ${powerEvents.size} power events individually")
                val syncedIds = mutableListOf<String>()
                for (power in powerEvents) {
                    try {
                        sendData("power_event", power)
                        syncedIds.add(power.messageId)
                        totalSynced++
                        delay(50) // Small delay between messages
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending power event ${power.messageId}", e)
                        break
                    }
                }
                if (syncedIds.isNotEmpty()) {
                    repository.markPowerEventsAsSynced(syncedIds)
                }
            }

            // Sync generic data - send individually
            val genericData = repository.getUnsyncedGenericData(SYNC_BATCH_SIZE)
            if (genericData.isNotEmpty()) {
                Log.d(TAG, "Syncing ${genericData.size} generic data items individually")
                syncGenericDataIndividually(genericData)
                totalSynced += genericData.size
            }

            if (totalSynced > 0) {
                Log.i(TAG, "Successfully synced $totalSynced data items individually")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error syncing pending data", e)
        }
    }

    private suspend fun syncGenericDataIndividually(data: List<GenericDataEntity>) {
        val syncedIds = mutableListOf<String>()

        for (entity in data) {
            try {
                // Validate dataType before processing
                if (entity.dataType.isNullOrBlank()) {
                    Log.w(TAG, "Skipping generic data ${entity.id} - dataType is null or empty")
                    continue
                }

                if (!MessageTypes.isValid(entity.dataType)) {
                    Log.w(TAG, "Skipping generic data ${entity.id} - invalid dataType: ${entity.dataType}")
                    continue
                }

                val parsedData = gson.fromJson(entity.dataJson, Any::class.java)
                sendData(entity.dataType, parsedData)
                syncedIds.add(entity.id)
                delay(50) // Small delay between messages
            } catch (e: Exception) {
                Log.e(TAG, "Error sending generic data ${entity.id} with dataType ${entity.dataType}", e)
            }
        }

        if (syncedIds.isNotEmpty()) {
            repository.markGenericDataAsSynced(syncedIds)
        }
    }

    // Removed sendPing() - server sends pings, we only respond with pongs

    private fun sendPong(pingId: Any?) {
        val message = WebSocketMessage(
            id = "${System.currentTimeMillis()}_health_check_pong",
            type = "health_check_pong",
            payload = mapOf(
                "ping_id" to pingId,
                "client_time_ms" to System.currentTimeMillis()
            ),
            metadata = mapOf(
                "device_id" to deviceId
            ),
            timestamp = Instant.now().toString()
        )
        coroutineScope.launch {
            messageQueue.send(gson.toJson(message))
        }
    }

    fun sendHeartRate(reading: HeartRateReading) {
        coroutineScope.launch {
            // Always save to database first
            repository.saveHeartRate(reading)

            // Try to send immediately if connected
            if (_connectionStatus.value) {
                sendData("heartrate", reading)
            }
        }
    }

    fun sendGPS(reading: GPSReading) {
        coroutineScope.launch {
            // Always save to database first
            repository.saveGPS(reading)

            // Try to send immediately if connected
            if (_connectionStatus.value) {
                sendData("gps", reading)
            }
        }
    }

    fun sendSleepState(state: SleepState) {
        coroutineScope.launch {
            // Always save to database first
            repository.saveSleepState(state)

            // Try to send immediately if connected
            if (_connectionStatus.value) {
                sendData("sleep_state", state)
            }
        }
    }

    fun sendPowerEvent(event: PowerEvent) {
        coroutineScope.launch {
            // Always save to database first
            repository.savePowerEvent(event)

            // Try to send immediately if connected
            if (_connectionStatus.value) {
                sendData("power_event", event)
            }
        }
    }

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

        val message = WebSocketMessage(
            id = "${System.currentTimeMillis()}_$dataType",
            type = "data",
            payload = mapOf(
                "message_type_id" to dataType,
                "data" to data
            ),
            metadata = mapOf(
                "device_id" to deviceId,
                "source" to "wearable"
            ),
            timestamp = Instant.now().toString()
        )

        coroutineScope.launch {
            messageQueue.send(gson.toJson(message))
        }
    }

    // Removed batch sending functions - now using individual messages only

    private fun scheduleReconnect() {
        cancelReconnectJob()

        // Use exponential backoff for reconnection attempts
        val reconnectDelay = if (_connectionStatus.value) {
            // If we were connected, use the normal interval
            RECONNECT_INTERVAL
        } else {
            // If we weren't connected yet, try again sooner
            minOf(RECONNECT_INTERVAL, 60000L) // Max 1 minute for initial attempts
        }

        Log.d(TAG, "Scheduling reconnect in ${reconnectDelay / 1000} seconds")

        reconnectJob = coroutineScope.launch {
            delay(reconnectDelay)
            connect()
        }
    }

    private fun cancelReconnectJob() {
        reconnectJob?.cancel()
        reconnectJob = null
    }

    private fun sendHeartbeat() {
        val message = WebSocketMessage(
            id = "${System.currentTimeMillis()}_heartbeat",
            type = "heartbeat",
            payload = mapOf(
                "timestamp" to Instant.now().toString()
            ),
            metadata = mapOf(
                "device_id" to deviceId
            ),
            timestamp = Instant.now().toString()
        )
        coroutineScope.launch {
            messageQueue.send(gson.toJson(message))
        }
    }

    private fun registerDevice() {
        val message = WebSocketMessage(
            id = "${System.currentTimeMillis()}_device_register",
            type = "device_register",
            payload = mapOf(
                "name" to "Loom Wearable",
                "device_type" to "other",
                "manufacturer" to android.os.Build.MANUFACTURER,
                "model" to android.os.Build.MODEL,
                "os_version" to "Android ${android.os.Build.VERSION.RELEASE}",
                "app_version" to "1.0.0",
                "platform" to "android_wear",
                "metadata" to mapOf(
                    "device_subtype" to "wearable",
                    "capabilities" to listOf("heart_rate", "gps", "sleep_detection", "power_monitoring", "on_body_detection")
                )
            ),
            metadata = mapOf(
                "device_id" to deviceId
            ),
            timestamp = Instant.now().toString()
        )
        coroutineScope.launch {
            messageQueue.send(gson.toJson(message))
        }
    }

    fun disconnect() {
        Log.d(TAG, "Disconnecting WebSocket")
        healthCheckJob?.cancel()
        heartbeatJob?.cancel()
        messageProcessorJob?.cancel()
        syncJob?.cancel()
        webSocket?.close(1000, "Normal closure")
        webSocket = null
        _connectionStatus.value = false
    }

    fun release() {
        disconnect()
        cancelReconnectJob()
        coroutineScope.cancel()
        messageQueue.close()
    }

    // Cleanup old synced data periodically
    fun performCleanup() {
        coroutineScope.launch {
            repository.cleanupOldData()
        }
    }

    // Get statistics about unsent data
    suspend fun getUnsentDataStats(): Map<String, Int> {
        return withContext(Dispatchers.IO) {
            try {
                val stats = mutableMapOf<String, Int>()

                val heartRateCount = repository.getUnsyncedHeartRates(Int.MAX_VALUE).size
                if (heartRateCount > 0) stats["heartrate"] = heartRateCount

                val gpsCount = repository.getUnsyncedGPS(Int.MAX_VALUE).size
                if (gpsCount > 0) stats["gps"] = gpsCount

                val sleepCount = repository.getUnsyncedSleepStates(Int.MAX_VALUE).size
                if (sleepCount > 0) stats["sleep"] = sleepCount

                val powerCount = repository.getUnsyncedPowerEvents(Int.MAX_VALUE).size
                if (powerCount > 0) stats["power"] = powerCount

                val genericCount = repository.getUnsyncedGenericData(Int.MAX_VALUE).size
                if (genericCount > 0) stats["generic"] = genericCount

                stats
            } catch (e: Exception) {
                Log.e(TAG, "Error getting unsent data stats", e)
                emptyMap()
            }
        }
    }

    // Force sync of all pending data
    fun forceSyncNow() {
        if (_connectionStatus.value) {
            coroutineScope.launch {
                Log.i(TAG, "Forcing immediate sync of all pending data")
                syncPendingData()
            }
        } else {
            Log.w(TAG, "Cannot force sync - not connected to server")
        }
    }
}
