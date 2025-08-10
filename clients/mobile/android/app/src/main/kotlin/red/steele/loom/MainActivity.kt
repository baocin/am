package red.steele.loom

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var screenStateReceiver: ScreenStateReceiver
    private lateinit var appLifecycleMonitor: AppLifecycleMonitor
    private var screenStateEventSink: EventChannel.EventSink? = null
    private var appLifecycleEventSink: EventChannel.EventSink? = null
    private var screenshotEventSink: EventChannel.EventSink? = null
    private var screenshotReceiver: BroadcastReceiver? = null
    private var pendingScreenshotResult: MethodChannel.Result? = null
    private var lastResultCode: Int = -1
    private var lastResultData: Intent? = null

    companion object {
        private const val REQUEST_MEDIA_PROJECTION = 1001
        private const val REQUEST_SINGLE_SCREENSHOT = 1002
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        appLifecycleMonitor = AppLifecycleMonitor(this)

        // Setup notification monitoring channels
        NotificationMonitor.setupChannels(flutterEngine, this)

        // Screen Text Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/screen_text").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "captureScreenText" -> {
                    // This will trigger a capture that sends data via event channel
                    if (isAccessibilityServiceEnabled()) {
                        val textData = AppAccessibilityService.captureScreenText()
                        result.success(textData)
                    } else {
                        result.error("PERMISSION_DENIED", "Accessibility service not enabled", null)
                    }
                }
                "captureScreenTextNow" -> {
                    // This returns the data directly
                    if (isAccessibilityServiceEnabled()) {
                        val textData = AppAccessibilityService.captureScreenText()
                        result.success(textData)
                    } else {
                        result.error("PERMISSION_DENIED", "Accessibility service not enabled", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Screen Text Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/screen_text_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AppAccessibilityService.setScreenTextEventSink(events)
                    println("WARNING: Screen text event listener registered")
                }

                override fun onCancel(arguments: Any?) {
                    AppAccessibilityService.setScreenTextEventSink(null)
                }
            }
        )

        // Screen State Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/screen_state").setMethodCallHandler { call, result ->
            when (call.method) {
                "getScreenState" -> {
                    result.success(ScreenStateReceiver.getScreenState(this))
                }
                else -> result.notImplemented()
            }
        }

        // Screen State Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/screen_state_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    screenStateEventSink = events
                    registerScreenStateReceiver()
                    println("WARNING: Screen state event listener registered")
                }

                override fun onCancel(arguments: Any?) {
                    screenStateEventSink = null
                    unregisterScreenStateReceiver()
                }
            }
        )

        // App Lifecycle Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/app_lifecycle").setMethodCallHandler { call, result ->
            when (call.method) {
                "startAppMonitoring" -> {
                    appLifecycleMonitor.startMonitoring()
                    result.success(true)
                }
                "stopAppMonitoring" -> {
                    appLifecycleMonitor.stopMonitoring()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // App Lifecycle Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/app_lifecycle_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    appLifecycleEventSink = events

                    // Check if accessibility service is enabled
                    if (isAccessibilityServiceEnabled()) {
                        // Use accessibility service for comprehensive app monitoring
                        AppAccessibilityService.setEventSink(events)
                        println("WARNING: App lifecycle monitoring using Accessibility Service")
                    } else {
                        // Fall back to UsageStats-based monitoring
                        appLifecycleMonitor.setEventSink(events)
                        println("WARNING: App lifecycle monitoring using UsageStats (limited)")
                    }
                }

                override fun onCancel(arguments: Any?) {
                    appLifecycleEventSink = null
                    AppAccessibilityService.setEventSink(null)
                    appLifecycleMonitor.setEventSink(null)
                }
            }
        )

        // App Monitoring Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/app_monitoring").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageStatsPermission" -> {
                    result.success(appLifecycleMonitor.hasUsageStatsPermission())
                }
                "getRunningApps" -> {
                    result.success(appLifecycleMonitor.getRunningApps())
                }
                "getUsageStats" -> {
                    val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 60
                    result.success(appLifecycleMonitor.getUsageStats(intervalMinutes))
                }
                "requestUsageStatsPermission" -> {
                    // Open usage stats settings
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "hasAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    // Open accessibility settings
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Screenshot Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/screenshot").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestScreenshotPermission" -> {
                    requestMediaProjectionPermission()
                    result.success(true)
                }
                "hasScreenshotPermission" -> {
                    // Check if the screenshot service is running, which indicates we have permission
                    val hasPermission = ScreenshotService.isServiceRunning(this)
                    result.success(hasPermission)
                }
                "startAutomaticCapture" -> {
                    val intervalMillis = call.argument<Int>("intervalMillis")?.toLong() ?: 300000L
                    // This would need the media projection result from requestScreenshotPermission
                    result.success(false) // For now
                }
                "stopAutomaticCapture" -> {
                    val stopIntent = Intent(this, ScreenshotService::class.java)
                    stopIntent.action = ScreenshotService.ACTION_STOP_CAPTURE
                    startService(stopIntent)
                    result.success(true)
                }
                "takeScreenshot" -> {
                    // Store the result to be used after permission is granted
                    pendingScreenshotResult = result

                    // Check if we already have permission (service is running)
                    if (ScreenshotService.isServiceRunning(this)) {
                        // Take screenshot immediately
                        takeImmediateScreenshot()
                    } else {
                        // Request permission first
                        requestMediaProjectionPermission()
                    }
                }
                "isServiceRunning" -> {
                    // Check if screenshot service is running
                    result.success(false)
                }
                else -> result.notImplemented()
            }
        }

        // Screenshot Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/screenshot_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    screenshotEventSink = events
                    registerScreenshotReceiver()

                    // Also set the screenshot event sink on accessibility service if enabled
                    if (isAccessibilityServiceEnabled()) {
                        AppAccessibilityService.setScreenshotEventSink(events)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    screenshotEventSink = null
                    unregisterScreenshotReceiver()
                    AppAccessibilityService.setScreenshotEventSink(null)
                }
            }
        )
    }

    private fun registerScreenStateReceiver() {
        screenStateReceiver = ScreenStateReceiver(screenStateEventSink)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        registerReceiver(screenStateReceiver, filter)
    }

    private fun unregisterScreenStateReceiver() {
        try {
            unregisterReceiver(screenStateReceiver)
        } catch (e: IllegalArgumentException) {
            // Receiver not registered
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterScreenStateReceiver()
        unregisterScreenshotReceiver()
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val accessibilityManager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabledServices = accessibilityManager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)

        for (service in enabledServices) {
            val serviceInfo = service.resolveInfo.serviceInfo
            if (serviceInfo.packageName == packageName &&
                serviceInfo.name == "red.steele.loom.AppAccessibilityService") {
                return true
            }
        }

        return false
    }

    private fun requestMediaProjectionPermission() {
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val permissionIntent = mediaProjectionManager.createScreenCaptureIntent()

        // Check if we're requesting for a single screenshot
        val requestCode = if (pendingScreenshotResult != null) {
            REQUEST_SINGLE_SCREENSHOT
        } else {
            REQUEST_MEDIA_PROJECTION
        }

        startActivityForResult(permissionIntent, requestCode)
    }

    private fun takeImmediateScreenshot() {
        // Send a broadcast to the service to take a screenshot immediately
        val intent = Intent("red.steele.loom.TAKE_SCREENSHOT_NOW")
        sendBroadcast(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQUEST_MEDIA_PROJECTION -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    // Save the permission for later use
                    lastResultCode = resultCode
                    lastResultData = data

                    // Start the screenshot service with the permission result
                    val serviceIntent = Intent(this, ScreenshotService::class.java).apply {
                        action = ScreenshotService.ACTION_START_CAPTURE
                        putExtra(ScreenshotService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(ScreenshotService.EXTRA_RESULT_DATA, data)
                        putExtra(ScreenshotService.EXTRA_INTERVAL_MILLIS, 300000L) // 5 minutes default
                    }
                    startService(serviceIntent)
                }
            }
            REQUEST_SINGLE_SCREENSHOT -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    // Save the permission for later use
                    lastResultCode = resultCode
                    lastResultData = data

                    // Start the service temporarily for a single screenshot
                    val serviceIntent = Intent(this, ScreenshotService::class.java).apply {
                        action = ScreenshotService.ACTION_SINGLE_CAPTURE
                        putExtra(ScreenshotService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(ScreenshotService.EXTRA_RESULT_DATA, data)
                    }
                    startService(serviceIntent)
                } else {
                    // Permission denied
                    pendingScreenshotResult?.error("PERMISSION_DENIED", "Screenshot permission denied", null)
                    pendingScreenshotResult = null
                }
            }
        }
    }

    private fun registerScreenshotReceiver() {
        screenshotReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    "red.steele.loom.SCREENSHOT_CAPTURED" -> {
                        val screenshotData = intent.getByteArrayExtra("screenshot_data")
                        if (screenshotData != null) {
                            // Check if this is for a pending single screenshot
                            if (pendingScreenshotResult != null) {
                                pendingScreenshotResult?.success(screenshotData)
                                pendingScreenshotResult = null
                            } else {
                                // Regular screenshot event for streaming
                                screenshotEventSink?.success(screenshotData)
                            }
                        }
                    }
                    "red.steele.loom.SCREENSHOT_ERROR" -> {
                        val error = intent.getStringExtra("error") ?: "Unknown error"
                        if (pendingScreenshotResult != null) {
                            pendingScreenshotResult?.error("SCREENSHOT_ERROR", error, null)
                            pendingScreenshotResult = null
                        }
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction("red.steele.loom.SCREENSHOT_CAPTURED")
            addAction("red.steele.loom.SCREENSHOT_ERROR")
        }
        registerReceiver(screenshotReceiver, filter)
    }

    private fun unregisterScreenshotReceiver() {
        screenshotReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Receiver not registered
            }
        }
        screenshotReceiver = null
    }
}
