package red.steele.loom.wearable.services

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import red.steele.loom.wearable.R
import red.steele.loom.wearable.data.DataStoreManager
import red.steele.loom.wearable.data.models.PollingFrequency
import red.steele.loom.wearable.data.sources.*
import red.steele.loom.wearable.presentation.MainActivity
import red.steele.loom.wearable.data.database.LoomDatabase
import red.steele.loom.wearable.data.repository.SensorDataRepository
import red.steele.loom.wearable.workers.CleanupWorker
import java.util.UUID

class LoomMonitoringService : Service() {
    companion object {
        private const val TAG = "LoomMonitoringService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "loom_monitoring_channel"
        private const val CHANNEL_NAME = "Loom Monitoring"

        const val ACTION_START_MONITORING = "red.steele.loom.wearable.action.START_MONITORING"
        const val ACTION_STOP_MONITORING = "red.steele.loom.wearable.action.STOP_MONITORING"

        const val EXTRA_HEART_RATE_ENABLED = "heart_rate_enabled"
        const val EXTRA_GPS_ENABLED = "gps_enabled"
        const val EXTRA_SLEEP_DETECTION_ENABLED = "sleep_detection_enabled"
        const val EXTRA_POLLING_FREQUENCY = "polling_frequency"
        const val EXTRA_SERVER_URL = "server_url"
        const val EXTRA_DEVICE_ID = "device_id"

        private val DEVICE_ID_KEY = stringPreferencesKey("device_id")
        private val SERVER_URL_KEY = stringPreferencesKey("server_url")
    }

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var webSocketService: UnifiedWebSocketService? = null
    private lateinit var repository: SensorDataRepository
    private lateinit var heartRateDataSource: HeartRateDataSource
    private lateinit var gpsDataSource: GPSDataSource
    private lateinit var sleepDetectionService: SleepDetectionService
    private lateinit var powerEventMonitor: PowerEventMonitor

    private var deviceId: String? = null
    private var serverUrl: String = "http://10.0.2.2:8000"

    private var heartRateEnabled = true
    private var gpsEnabled = true
    private var sleepDetectionEnabled = true
    private var pollingFrequency = PollingFrequency.BATTERY_SAVER

    private val _lastHeartRate = MutableStateFlow<Int?>(null)
    private val _connectionStatus = MutableStateFlow(false)

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        createNotificationChannel()

        // Initialize database and repository
        val database = LoomDatabase.getInstance(applicationContext)
        repository = SensorDataRepository(database)

        loadSettings()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service onStartCommand: ${intent?.action}")

        when (intent?.action) {
            ACTION_START_MONITORING -> {
                heartRateEnabled = intent.getBooleanExtra(EXTRA_HEART_RATE_ENABLED, true)
                gpsEnabled = intent.getBooleanExtra(EXTRA_GPS_ENABLED, true)
                sleepDetectionEnabled = intent.getBooleanExtra(EXTRA_SLEEP_DETECTION_ENABLED, true)
                val frequencyOrdinal = intent.getIntExtra(EXTRA_POLLING_FREQUENCY, PollingFrequency.BATTERY_SAVER.ordinal)
                pollingFrequency = PollingFrequency.fromOrdinal(frequencyOrdinal)

                // Get server URL and device ID from intent if provided
                intent.getStringExtra(EXTRA_SERVER_URL)?.let { serverUrl = it }
                intent.getStringExtra(EXTRA_DEVICE_ID)?.let { deviceId = it }

                startForeground()
                startMonitoring()

                // Schedule periodic cleanup
                CleanupWorker.enqueuePeriodicWork(applicationContext)
            }
            ACTION_STOP_MONITORING -> {
                stopMonitoring()
                stopForeground(STOP_FOREGROUND_REMOVE)

                // Cancel periodic cleanup
                CleanupWorker.cancelWork(applicationContext)

                stopSelf()
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
        stopMonitoring()
        serviceScope.cancel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, importance).apply {
                description = "Shows when Loom is monitoring your health data"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForeground() {
        val notification = createNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotification(): Notification {
        val pendingIntent = Intent(this, MainActivity::class.java).let { notificationIntent ->
            PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val stopIntent = Intent(this, LoomMonitoringService::class.java).apply {
            action = ACTION_STOP_MONITORING
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = buildString {
            append("Monitoring: ")
            val features = mutableListOf<String>()
            if (heartRateEnabled) features.add("Heart Rate")
            if (gpsEnabled) features.add("GPS")
            if (sleepDetectionEnabled) features.add("Sleep")
            append(features.joinToString(", "))

            _lastHeartRate.value?.let { hr ->
                append(" • ❤️ $hr bpm")
            }

            if (_connectionStatus.value) {
                append(" • ✅ Connected")
            } else {
                append(" • ⚠️ Disconnected")
            }
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Loom Monitoring Active")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
            .build()
    }

    private fun updateNotification() {
        val notification = createNotification()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun loadSettings() {
        serviceScope.launch {
            val dataStore = DataStoreManager.getDataStore(applicationContext)
            dataStore.data.collect { preferences ->
                deviceId = preferences[DEVICE_ID_KEY] ?: generateDeviceId()
                serverUrl = preferences[SERVER_URL_KEY] ?: "http://10.0.2.2:8000"

                // Initialize data sources with device ID
                deviceId?.let { id ->
                    heartRateDataSource = HeartRateDataSource(applicationContext, id)
                    gpsDataSource = GPSDataSource(applicationContext, id)
                    sleepDetectionService = SleepDetectionService(applicationContext, id)
                    powerEventMonitor = PowerEventMonitor(applicationContext, id)
                }
            }
        }
    }

    private suspend fun generateDeviceId(): String {
        return "wearable_${UUID.randomUUID()}"
    }

    private fun startMonitoring() {
        if (deviceId == null) {
            Log.e(TAG, "Cannot start monitoring: no device ID")
            return
        }

        Log.d(TAG, "Starting monitoring with frequency: ${pollingFrequency.displayName}")

        // Initialize and connect WebSocket (it will handle device registration)
        serviceScope.launch {
            webSocketService = UnifiedWebSocketService(deviceId!!, serverUrl, repository).apply {
                connect()

                // Perform periodic cleanup
                serviceScope.launch {
                    while (isActive) {
                        delay(24 * 60 * 60 * 1000L) // Once per day
                        performCleanup()
                    }
                }

                // Monitor connection status
                serviceScope.launch {
                    connectionStatus.collect { connected ->
                        _connectionStatus.value = connected
                        updateNotification()
                    }
                }
            }
        }

        // Start heart rate monitoring
        if (heartRateEnabled) {
            // Set up on-body status callback
            heartRateDataSource.onBodyStatusCallback = { onBody ->
                serviceScope.launch {
                    val timestamp = java.time.Instant.now().toString()
                    val statusData = mapOf(
                        "device_id" to deviceId!!,
                        "on_body" to onBody,
                        "timestamp" to timestamp
                    )

                    Log.d(TAG, "On-body status changed: $onBody")

                    // Send via WebSocket as generic data
                    webSocketService?.let { ws ->
                        val message = red.steele.loom.wearable.data.models.WebSocketMessage(
                            id = "${System.currentTimeMillis()}_on_body_status",
                            type = "data",
                            payload = mapOf(
                                "message_type_id" to "on_body_status",
                                "data" to statusData
                            ),
                            metadata = mapOf(
                                "device_id" to deviceId!!,
                                "source" to "wearable"
                            ),
                            timestamp = timestamp
                        )

                        // Save to database as generic data
                        repository.saveGenericData(
                            dataType = "on_body_status",
                            data = statusData,
                            deviceId = deviceId!!,
                            recordedAt = timestamp
                        )

                        // Send immediately if connected
                        if (ws.connectionStatus.value) {
                            ws.sendData("on_body_status", statusData)
                        }
                    }
                }
            }

            serviceScope.launch {
                heartRateDataSource.observeHeartRate(
                    intervalMs = pollingFrequency.heartRateIntervalMs
                )
                    .catch { e ->
                        Log.e(TAG, "Heart rate error", e)
                    }
                    .collect { reading ->
                        _lastHeartRate.value = reading.bpm
                        webSocketService?.sendHeartRate(reading)
                        updateNotification()
                    }
            }
        }

        // Start GPS monitoring
        if (gpsEnabled && gpsDataSource.hasLocationPermission()) {
            serviceScope.launch {
                gpsDataSource.observeLocation(
                    intervalMs = pollingFrequency.gpsIntervalMs
                )
                    .catch { e ->
                        Log.e(TAG, "GPS error", e)
                    }
                    .collect { reading ->
                        webSocketService?.sendGPS(reading)
                    }
            }
        }

        // Start sleep detection
        if (sleepDetectionEnabled) {
            serviceScope.launch {
                sleepDetectionService.observeSleepState(
                    analysisIntervalMs = pollingFrequency.sleepDetectionIntervalMs
                )
                    .catch { e ->
                        Log.e(TAG, "Sleep detection error", e)
                    }
                    .collect { state ->
                        webSocketService?.sendSleepState(state)
                    }
            }
        }

        // Start power event monitoring
        serviceScope.launch {
            powerEventMonitor.observePowerEvents()
                .catch { e ->
                    Log.e(TAG, "Power monitor error", e)
                }
                .collect { event ->
                    webSocketService?.sendPowerEvent(event)
                }
        }
    }

    private fun stopMonitoring() {
        Log.d(TAG, "Stopping monitoring")
        webSocketService?.disconnect()
        webSocketService = null
        serviceScope.coroutineContext.cancelChildren()
    }
}
