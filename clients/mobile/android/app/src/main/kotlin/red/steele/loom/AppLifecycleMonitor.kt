package red.steele.loom

import android.app.ActivityManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.EventChannel
import java.util.*

class AppLifecycleMonitor(private val context: Context) {
    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    private val packageManager = context.packageManager
    private val usageStatsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    } else null

    private val trackedApps = mutableMapOf<String, AppState>()
    private var eventSink: EventChannel.EventSink? = null

    data class AppState(
        val packageName: String,
        val appName: String,
        var lastEventType: String,
        var lastEventTime: Long
    )

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun startMonitoring() {
        // Initial scan of running apps
        scanRunningApps()
    }

    fun stopMonitoring() {
        trackedApps.clear()
    }

    fun getRunningApps(): List<Map<String, Any>> {
        println("WARNING: App monitoring - collecting running apps data")
        val runningApps = mutableListOf<Map<String, Any>>()
        val processedPackages = mutableSetOf<String>()

        // First, get all running processes (works without UsageStats permission)
        val runningProcesses = activityManager.runningAppProcesses
        runningProcesses?.forEach { process ->
            try {
                // Skip if already processed
                if (processedPackages.contains(process.processName)) return@forEach

                // Skip Loom app itself
                if (process.processName == "red.steele.loom") return@forEach

                val appInfo = packageManager.getApplicationInfo(process.processName, 0)

                // Skip system apps unless they're user-visible
                if ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0) {
                    // Allow some system apps that users interact with
                    val allowedSystemApps = listOf("com.android.chrome", "com.google.android", "com.android.settings")
                    if (!allowedSystemApps.any { process.processName.startsWith(it) }) {
                        return@forEach
                    }
                }

                val appName = packageManager.getApplicationLabel(appInfo).toString()
                processedPackages.add(process.processName)

                runningApps.add(mapOf(
                    "packageName" to process.processName,
                    "appName" to appName,
                    "pid" to process.pid,
                    "isForeground" to (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND),
                    "launchTime" to 0L,
                    "versionCode" to getAppVersionCode(process.processName),
                    "versionName" to getAppVersionName(process.processName),
                    "isSystemApp" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0)
                ))
            } catch (e: PackageManager.NameNotFoundException) {
                // Process might be a service or sub-process, skip
            }
        }

        // If we have UsageStats permission, enhance with additional data
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && hasUsageStatsPermission()) {
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 1000 * 60 * 60 // Last hour for better coverage

            // Get usage stats for the period
            val usageStatsList = usageStatsManager?.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                startTime,
                endTime
            )

            // Add apps that have been used recently but might not have running processes
            usageStatsList?.forEach { stats ->
                if (stats.totalTimeInForeground > 0 && !processedPackages.contains(stats.packageName)) {
                    // Skip Loom app itself
                    if (stats.packageName == "red.steele.loom") return@forEach

                    try {
                        val appInfo = packageManager.getApplicationInfo(stats.packageName, 0)
                        val appName = packageManager.getApplicationLabel(appInfo).toString()

                        runningApps.add(mapOf(
                            "packageName" to stats.packageName,
                            "appName" to appName,
                            "pid" to 0, // No active process
                            "isForeground" to false,
                            "launchTime" to stats.lastTimeUsed,
                            "versionCode" to getAppVersionCode(stats.packageName),
                            "versionName" to getAppVersionName(stats.packageName),
                            "isSystemApp" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                            "lastUsed" to stats.lastTimeUsed
                        ))
                        processedPackages.add(stats.packageName)
                    } catch (e: PackageManager.NameNotFoundException) {
                        // Skip
                    }
                }
            }
        }

        // Skip including Loom itself in the running apps list
        // We're only interested in monitoring other apps

        return runningApps
    }

    fun getUsageStats(intervalMinutes: Int): Map<String, Any> {
        val stats = mutableMapOf<String, Any>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && hasUsageStatsPermission()) {
            val endTime = System.currentTimeMillis()
            val startTime = endTime - (intervalMinutes * 60 * 1000)

            val usageStatsList = usageStatsManager?.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                startTime,
                endTime
            )

            val appUsageList = mutableListOf<Map<String, Any>>()
            var totalScreenTime = 0L

            usageStatsList?.forEach { usageStats ->
                if (usageStats.totalTimeInForeground > 0) {
                    // Skip Loom app itself
                    if (usageStats.packageName == "red.steele.loom") return@forEach

                    try {
                        val appInfo = packageManager.getApplicationInfo(usageStats.packageName, 0)
                        val appName = packageManager.getApplicationLabel(appInfo).toString()

                        appUsageList.add(mapOf(
                            "packageName" to usageStats.packageName,
                            "appName" to appName,
                            "totalTimeInForeground" to usageStats.totalTimeInForeground,
                            "lastTimeUsed" to usageStats.lastTimeUsed,
                            "launchCount" to getAppLaunchCount(usageStats.packageName, startTime, endTime)
                        ))

                        totalScreenTime += usageStats.totalTimeInForeground
                    } catch (e: PackageManager.NameNotFoundException) {
                        // Skip
                    }
                }
            }

            stats["startTime"] = startTime
            stats["endTime"] = endTime
            stats["totalScreenTime"] = totalScreenTime
            stats["apps"] = appUsageList
        }

        return stats
    }

    fun hasUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false

        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            appOps.unsafeCheckOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            appOps.checkOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }

        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    private fun scanRunningApps() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && hasUsageStatsPermission()) {
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 1000 * 60 // Last minute

            val usageEvents = usageStatsManager?.queryEvents(startTime, endTime)

            while (usageEvents?.hasNextEvent() == true) {
                val event = UsageEvents.Event()
                usageEvents.getNextEvent(event)

                handleUsageEvent(event)
            }
        }
    }

    private fun handleUsageEvent(event: UsageEvents.Event) {
        val packageName = event.packageName
        val timestamp = event.timeStamp

        // Skip events from Loom app itself
        if (packageName == "red.steele.loom") {
            return
        }

        val eventType = when (event.eventType) {
            UsageEvents.Event.MOVE_TO_FOREGROUND -> "foreground"
            UsageEvents.Event.MOVE_TO_BACKGROUND -> "background"
            else -> return
        }

        // Get app name
        val appName = try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            packageName
        }

        // Check if this is a new event
        val lastState = trackedApps[packageName]
        if (lastState == null || lastState.lastEventType != eventType) {
            // Calculate duration for previous state
            val duration = if (lastState != null) {
                ((timestamp - lastState.lastEventTime) / 1000).toInt()
            } else null

            // Send event
            println("WARNING: App lifecycle event detected - app: $appName, event: $eventType, duration: ${duration ?: 0}s")
            eventSink?.success(mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "eventType" to eventType,
                "timestamp" to timestamp,
                "durationSeconds" to duration
            ))

            // Update tracked state
            trackedApps[packageName] = AppState(packageName, appName, eventType, timestamp)
        }
    }

    private fun isAppInForeground(packageName: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 1000 // Last second

            val usageEvents = usageStatsManager?.queryEvents(startTime, endTime)
            var lastEventType = ""

            while (usageEvents?.hasNextEvent() == true) {
                val event = UsageEvents.Event()
                usageEvents.getNextEvent(event)

                if (event.packageName == packageName) {
                    when (event.eventType) {
                        UsageEvents.Event.MOVE_TO_FOREGROUND -> lastEventType = "foreground"
                        UsageEvents.Event.MOVE_TO_BACKGROUND -> lastEventType = "background"
                    }
                }
            }

            return lastEventType == "foreground"
        }

        return false
    }

    private fun getProcessIdForPackage(packageName: String): Int? {
        val runningProcesses = activityManager.runningAppProcesses
        return runningProcesses?.find { it.processName == packageName }?.pid
    }

    private fun getAppLaunchTime(packageName: String): Long {
        // This is an approximation - actual launch time tracking requires more complex logic
        return 0L
    }

    private fun getAppVersionCode(packageName: String): Int {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode
            }
        } catch (e: PackageManager.NameNotFoundException) {
            0
        }
    }

    private fun getAppVersionName(packageName: String): String {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: ""
        } catch (e: PackageManager.NameNotFoundException) {
            ""
        }
    }

    private fun getAppLaunchCount(packageName: String, startTime: Long, endTime: Long): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return 0

        // Skip counting launches for Loom app itself
        if (packageName == "red.steele.loom") return 0

        var launchCount = 0
        val usageEvents = usageStatsManager?.queryEvents(startTime, endTime)

        while (usageEvents?.hasNextEvent() == true) {
            val event = UsageEvents.Event()
            usageEvents.getNextEvent(event)

            if (event.packageName == packageName &&
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                launchCount++
            }
        }

        return launchCount
    }
}
