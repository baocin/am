package red.steele.loom

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class NotificationMonitor : NotificationListenerService() {
    companion object {
        private var eventSink: EventChannel.EventSink? = null
        private var isMonitoring = false

        fun setupChannels(flutterEngine: FlutterEngine, context: Context) {
            // Method channel for control commands
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/notifications").setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkNotificationAccess" -> {
                        result.success(isNotificationAccessGranted(context))
                    }
                    "requestNotificationAccess" -> {
                        openNotificationAccessSettings(context)
                        result.success(null)
                    }
                    "startNotificationMonitoring" -> {
                        isMonitoring = true
                        result.success(true)
                    }
                    "stopNotificationMonitoring" -> {
                        isMonitoring = false
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

            // Event channel for notification events
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, "red.steele.loom/notifications_events").setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                }
            )
        }

        private fun isNotificationAccessGranted(context: Context): Boolean {
            val enabledListeners = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            )
            val componentName = ComponentName(context, NotificationMonitor::class.java)
            return enabledListeners != null && enabledListeners.contains(componentName.flattenToString())
        }

        private fun openNotificationAccessSettings(context: Context) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }

        fun sendNotificationEvent(notification: Map<String, Any?>) {
            if (isMonitoring) {
                eventSink?.success(notification)
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!isMonitoring) return

        // Skip ongoing notifications (e.g., persistent service notifications)
        if (sbn.isOngoing) return

        try {
            val notification = sbn.notification
            val extras = notification.extras

            val notificationData = mutableMapOf<String, Any?>(
                "action" to "posted",
                "id" to sbn.id.toString(),
                "key" to sbn.key,
                "package" to sbn.packageName,
                "tag" to sbn.tag,
                "group_key" to sbn.groupKey,
                "when" to sbn.postTime,
                "is_clearable" to sbn.isClearable,
                "is_ongoing" to sbn.isOngoing,
                "is_group" to sbn.isGroup
            )

            // Extract notification content
            extras?.let {
                notificationData["title"] = it.getString(Notification.EXTRA_TITLE)
                notificationData["text"] = it.getString(Notification.EXTRA_TEXT)
                notificationData["big_text"] = it.getString(Notification.EXTRA_BIG_TEXT)
                notificationData["sub_text"] = it.getString(Notification.EXTRA_SUB_TEXT)
                notificationData["info_text"] = it.getString(Notification.EXTRA_INFO_TEXT)
                notificationData["ticker_text"] = notification.tickerText?.toString()
            }

            // Notification metadata
            notificationData["flags"] = notification.flags
            notificationData["priority"] = notification.priority

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notificationData["channel_id"] = notification.channelId
                notificationData["category"] = notification.category
            }

            sendNotificationEvent(notificationData)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (!isMonitoring) return

        try {
            val notificationData = mapOf(
                "action" to "removed",
                "id" to sbn.id.toString(),
                "key" to sbn.key,
                "package" to sbn.packageName,
                "tag" to sbn.tag,
                "when" to sbn.postTime
            )

            sendNotificationEvent(notificationData)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        // Notification listener service is connected
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        // Notification listener service is disconnected
    }
}
