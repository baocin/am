package red.steele.loom.wearable.presentation

import android.app.Application
import android.content.Intent
import android.os.Build
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import red.steele.loom.wearable.data.DataStoreManager
import red.steele.loom.wearable.data.database.LoomDatabase
import red.steele.loom.wearable.data.models.PollingFrequency
import red.steele.loom.wearable.data.models.SyncStatus
import red.steele.loom.wearable.data.models.combineSyncStatus
import red.steele.loom.wearable.data.repository.SensorDataRepository
import red.steele.loom.wearable.data.sources.*
import red.steele.loom.wearable.services.DeviceRegistrationService
import red.steele.loom.wearable.services.LoomMonitoringService
import red.steele.loom.wearable.services.UnifiedWebSocketService
import java.util.UUID
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.Response
import java.util.concurrent.TimeUnit
import java.util.concurrent.CountDownLatch

class MainViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "MainViewModel"
        private val DEVICE_ID_KEY = stringPreferencesKey("device_id")
        private val SERVER_URL_KEY = stringPreferencesKey("server_url")
        private val POLLING_FREQUENCY_KEY = intPreferencesKey("polling_frequency")
        private const val DEFAULT_SERVER_URL = "" // User must configure server URL
    }

    private val dataStore = DataStoreManager.getDataStore(application)

    // State flows
    private val _isMonitoring = MutableStateFlow(false)
    val isMonitoring: StateFlow<Boolean> = _isMonitoring.asStateFlow()

    private val _connectionStatus = MutableStateFlow(false)
    val connectionStatus: StateFlow<Boolean> = _connectionStatus.asStateFlow()

    private val _heartRateEnabled = MutableStateFlow(true)
    val heartRateEnabled: StateFlow<Boolean> = _heartRateEnabled.asStateFlow()

    private val _gpsEnabled = MutableStateFlow(true)
    val gpsEnabled: StateFlow<Boolean> = _gpsEnabled.asStateFlow()

    private val _sleepDetectionEnabled = MutableStateFlow(true)
    val sleepDetectionEnabled: StateFlow<Boolean> = _sleepDetectionEnabled.asStateFlow()

    private val _lastHeartRate = MutableStateFlow<Int?>(null)
    val lastHeartRate: StateFlow<Int?> = _lastHeartRate.asStateFlow()

    private val _statusMessage = MutableStateFlow("Ready to start monitoring")
    val statusMessage: StateFlow<String> = _statusMessage.asStateFlow()

    private val _pollingFrequency = MutableStateFlow(PollingFrequency.BATTERY_SAVER)
    val pollingFrequency: StateFlow<PollingFrequency> = _pollingFrequency.asStateFlow()

    private val _deviceId = MutableStateFlow<String?>(null)
    val deviceIdFlow: StateFlow<String?> = _deviceId.asStateFlow()

    private val _serverUrl = MutableStateFlow(DEFAULT_SERVER_URL)
    val serverUrlFlow: StateFlow<String> = _serverUrl.asStateFlow()

    // Database and repository
    private val database = LoomDatabase.getInstance(application)
    private val repository = SensorDataRepository(database)

    // Sync status
    val syncStatus: StateFlow<SyncStatus> = combineSyncStatus(
        repository.getUnsyncedHeartRateCount(),
        repository.getUnsyncedGPSCount(),
        repository.getUnsyncedSleepStateCount(),
        repository.getUnsyncedPowerEventCount(),
        repository.getUnsyncedGenericDataCount()
    ).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = SyncStatus()
    )

    // Services
    private var webSocketService: UnifiedWebSocketService? = null
    private lateinit var heartRateDataSource: HeartRateDataSource
    private lateinit var gpsDataSource: GPSDataSource
    private lateinit var sleepDetectionService: SleepDetectionService
    private lateinit var powerEventMonitor: PowerEventMonitor

    private var deviceId: String? = null
    private var serverUrl: String = DEFAULT_SERVER_URL

    init {
        loadSettings()
    }

    private fun loadSettings() {
        viewModelScope.launch {
            dataStore.data.take(1).collect { preferences ->
                val storedDeviceId = preferences[DEVICE_ID_KEY]
                if (storedDeviceId == null) {
                    // Generate and store new device ID
                    deviceId = generateDeviceId()
                } else {
                    deviceId = storedDeviceId
                }

                serverUrl = preferences[SERVER_URL_KEY] ?: DEFAULT_SERVER_URL
                _serverUrl.value = serverUrl

                val frequencyOrdinal = preferences[POLLING_FREQUENCY_KEY] ?: PollingFrequency.BATTERY_SAVER.ordinal
                _pollingFrequency.value = PollingFrequency.fromOrdinal(frequencyOrdinal)

                // Initialize data sources with device ID
                deviceId?.let { id ->
                    _deviceId.value = id
                    Log.i(TAG, "=== LOOM WEARABLE DEVICE UUID ===")
                    Log.i(TAG, "Device UUID: $id")
                    Log.i(TAG, "=================================")
                    heartRateDataSource = HeartRateDataSource(getApplication(), id)
                    gpsDataSource = GPSDataSource(getApplication(), id)
                    sleepDetectionService = SleepDetectionService(getApplication(), id)
                    powerEventMonitor = PowerEventMonitor(getApplication(), id)
                }
            }
        }
    }

    private suspend fun generateDeviceId(): String {
        val newId = "wearable_${UUID.randomUUID()}"
        dataStore.edit { preferences ->
            preferences[DEVICE_ID_KEY] = newId
        }
        return newId
    }

    fun updateServerUrl(url: String) {
        viewModelScope.launch {
            serverUrl = url
            _serverUrl.value = url
            dataStore.edit { preferences ->
                preferences[SERVER_URL_KEY] = url
            }

            // Reconnect if monitoring
            if (_isMonitoring.value) {
                stopMonitoring()
                startMonitoring()
            }
        }
    }

    fun toggleHeartRate(enabled: Boolean) {
        _heartRateEnabled.value = enabled
    }

    fun toggleGPS(enabled: Boolean) {
        _gpsEnabled.value = enabled
    }

    fun toggleSleepDetection(enabled: Boolean) {
        _sleepDetectionEnabled.value = enabled
    }

    fun updatePollingFrequency(frequency: PollingFrequency) {
        viewModelScope.launch {
            _pollingFrequency.value = frequency
            dataStore.edit { preferences ->
                preferences[POLLING_FREQUENCY_KEY] = frequency.ordinal
            }

            // If monitoring is active, restart with new frequency
            if (_isMonitoring.value) {
                stopMonitoring()
                startMonitoring()
            }
        }
    }

    fun startMonitoring() {
        if (_isMonitoring.value) return

        _isMonitoring.value = true
        _statusMessage.value = "Starting monitoring services..."

        // Start the foreground service
        val intent = Intent(getApplication(), LoomMonitoringService::class.java).apply {
            action = LoomMonitoringService.ACTION_START_MONITORING
            putExtra(LoomMonitoringService.EXTRA_HEART_RATE_ENABLED, _heartRateEnabled.value)
            putExtra(LoomMonitoringService.EXTRA_GPS_ENABLED, _gpsEnabled.value)
            putExtra(LoomMonitoringService.EXTRA_SLEEP_DETECTION_ENABLED, _sleepDetectionEnabled.value)
            putExtra(LoomMonitoringService.EXTRA_POLLING_FREQUENCY, _pollingFrequency.value.ordinal)
            putExtra(LoomMonitoringService.EXTRA_SERVER_URL, serverUrl)
            putExtra(LoomMonitoringService.EXTRA_DEVICE_ID, deviceId)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getApplication<Application>().startForegroundService(intent)
        } else {
            getApplication<Application>().startService(intent)
        }

        _statusMessage.value = "Monitoring active"
        _connectionStatus.value = true // Will be updated by service via shared preferences or broadcast
    }

    fun stopMonitoring() {
        _isMonitoring.value = false
        _statusMessage.value = "Stopping monitoring..."

        // Stop the foreground service
        val intent = Intent(getApplication(), LoomMonitoringService::class.java).apply {
            action = LoomMonitoringService.ACTION_STOP_MONITORING
        }
        getApplication<Application>().startService(intent)

        _connectionStatus.value = false
        _lastHeartRate.value = null
        _statusMessage.value = "Monitoring stopped"
    }

    fun testConnection(callback: (Boolean, String) -> Unit) {
        viewModelScope.launch {
            try {
                if (serverUrl.isBlank()) {
                    callback(false, "No server URL configured")
                    return@launch
                }

                if (deviceId == null) {
                    callback(false, "No device ID available")
                    return@launch
                }

                // First try a simple health check
                val healthCheckSuccess = withContext(Dispatchers.IO) {
                    try {
                        Log.i(TAG, "Testing connection to $serverUrl/healthz")
                        val healthCheckUrl = "$serverUrl/healthz"
                        val client = OkHttpClient.Builder()
                            .connectTimeout(5, TimeUnit.SECONDS)
                            .readTimeout(5, TimeUnit.SECONDS)
                            .build()

                        val request = Request.Builder()
                            .url(healthCheckUrl)
                            .get()
                            .build()

                        val response = client.newCall(request).execute()
                        Log.i(TAG, "Health check response: ${response.code}")
                        response.code == 200
                    } catch (e: Exception) {
                        Log.e(TAG, "Health check failed", e)
                        false
                    }
                }

                if (!healthCheckSuccess) {
                    callback(false, "Cannot reach server")
                    return@launch
                }

                // Skip device registration and just test WebSocket connection
                Log.i(TAG, "Health check passed, testing WebSocket connection...")

                // Test WebSocket connection
                val wsTestSuccess = testWebSocketConnection(deviceId!!, serverUrl)

                if (wsTestSuccess) {
                    callback(true, "Success! WebSocket connection established")
                } else {
                    callback(false, "Server reachable but WebSocket connection failed")
                }
            } catch (e: Exception) {
                callback(false, "Connection error: ${e.message}")
            }
        }
    }

    private suspend fun testWebSocketConnection(deviceId: String, serverUrl: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val normalizedUrl = normalizeUrl(serverUrl)
                val wsUrl = normalizedUrl.replace("http://", "ws://").replace("https://", "wss://")
                val fullWsUrl = "$wsUrl/realtime/ws/$deviceId"

                Log.i(TAG, "Testing WebSocket connection to: $fullWsUrl")

                // Create a simple WebSocket test
                val client = OkHttpClient.Builder()
                    .connectTimeout(10, TimeUnit.SECONDS)
                    .readTimeout(10, TimeUnit.SECONDS)
                    .build()

                val request = Request.Builder()
                    .url(fullWsUrl)
                    .header("X-API-Key", "apikeyhere")
                    .build()

                var connected = false
                val latch = java.util.concurrent.CountDownLatch(1)

                val listener = object : okhttp3.WebSocketListener() {
                    override fun onOpen(webSocket: okhttp3.WebSocket, response: okhttp3.Response) {
                        Log.i(TAG, "WebSocket opened successfully")
                        connected = true
                        webSocket.close(1000, "Test complete")
                        latch.countDown()
                    }

                    override fun onFailure(webSocket: okhttp3.WebSocket, t: Throwable, response: okhttp3.Response?) {
                        Log.e(TAG, "WebSocket connection failed", t)
                        connected = false
                        latch.countDown()
                    }

                    override fun onClosed(webSocket: okhttp3.WebSocket, code: Int, reason: String) {
                        Log.i(TAG, "WebSocket closed: $code $reason")
                        latch.countDown()
                    }
                }

                client.newWebSocket(request, listener)

                // Wait for connection result (up to 10 seconds)
                latch.await(10, TimeUnit.SECONDS)

                Log.i(TAG, "WebSocket test result: ${if (connected) "SUCCESS" else "FAILED"}")
                connected

            } catch (e: Exception) {
                Log.e(TAG, "WebSocket test error", e)
                false
            }
        }
    }

    private fun normalizeUrl(url: String): String {
        return when {
            url.startsWith("http://") || url.startsWith("https://") -> url
            else -> "http://$url"
        }
    }

    fun testBluetoothConnection(callback: (Boolean, String) -> Unit) {
        // Bluetooth testing not implemented - using WebSocket directly
        callback(false, "Bluetooth relay not enabled - using direct WebSocket connection")
    }

    fun forceSyncNow() {
        viewModelScope.launch {
            try {
                val unsentStats = webSocketService?.getUnsentDataStats() ?: emptyMap()
                if (unsentStats.isNotEmpty()) {
                    _statusMessage.value = "Syncing ${unsentStats.values.sum()} items..."
                    webSocketService?.forceSyncNow()

                    // Update status message with details
                    val details = unsentStats.entries.joinToString(", ") {
                        "${it.key}: ${it.value}"
                    }
                    _statusMessage.value = "Syncing: $details"
                } else {
                    _statusMessage.value = "No data to sync"
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error forcing sync", e)
                _statusMessage.value = "Sync error: ${e.message}"
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // Service will handle its own cleanup
    }
}
