package red.steele.loom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.app.KeyguardManager
import io.flutter.plugin.common.EventChannel

class ScreenStateReceiver(private val events: EventChannel.EventSink?) : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val timestamp = System.currentTimeMillis()

        when (action) {
            Intent.ACTION_SCREEN_ON -> {
                println("WARNING: Screen state event detected - SCREEN_ON")
                events?.success(mapOf(
                    "type" to "screen_on",
                    "timestamp" to timestamp
                ))
            }
            Intent.ACTION_SCREEN_OFF -> {
                println("WARNING: Screen state event detected - SCREEN_OFF")
                events?.success(mapOf(
                    "type" to "screen_off",
                    "timestamp" to timestamp
                ))
            }
            Intent.ACTION_USER_PRESENT -> {
                // Device unlocked
                println("WARNING: Screen state event detected - DEVICE_UNLOCK")
                events?.success(mapOf(
                    "type" to "device_unlock",
                    "timestamp" to timestamp
                ))
            }
            Intent.ACTION_POWER_CONNECTED -> {
                println("WARNING: Screen state event detected - POWER_CONNECTED")
                events?.success(mapOf(
                    "type" to "power_connected",
                    "timestamp" to timestamp
                ))
            }
            Intent.ACTION_POWER_DISCONNECTED -> {
                println("WARNING: Screen state event detected - POWER_DISCONNECTED")
                events?.success(mapOf(
                    "type" to "power_disconnected",
                    "timestamp" to timestamp
                ))
            }
        }

        // Also check lock state
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (keyguardManager.isKeyguardLocked && action == Intent.ACTION_SCREEN_ON) {
            println("WARNING: Screen state event detected - DEVICE_LOCK")
            events?.success(mapOf(
                "type" to "device_lock",
                "timestamp" to timestamp
            ))
        }
    }

    companion object {
        fun getScreenState(context: Context): Map<String, Any> {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

            return mapOf(
                "isScreenOn" to powerManager.isInteractive,
                "isLocked" to keyguardManager.isKeyguardLocked
            )
        }
    }
}
