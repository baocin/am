package red.steele.loom.wearable.data.sources

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import red.steele.loom.wearable.data.models.PowerEvent
import java.time.Instant

class PowerEventMonitor(
    private val context: Context,
    private val deviceId: String
) {
    companion object {
        private const val TAG = "PowerEventMonitor"
    }

    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

    fun observePowerEvents(): Flow<PowerEvent> = callbackFlow {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_ON -> {
                        Log.d(TAG, "Screen turned on (device wake)")
                        val event = PowerEvent(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            eventType = "wake",
                            batteryLevel = getBatteryLevel(),
                            isCharging = isCharging()
                        )
                        trySend(event)
                    }

                    Intent.ACTION_SCREEN_OFF -> {
                        Log.d(TAG, "Screen turned off (device sleep)")
                        val event = PowerEvent(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            eventType = "sleep",
                            batteryLevel = getBatteryLevel(),
                            isCharging = isCharging()
                        )
                        trySend(event)
                    }

                    Intent.ACTION_POWER_CONNECTED -> {
                        Log.d(TAG, "Charger connected")
                        val event = PowerEvent(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            eventType = "charging_started",
                            batteryLevel = getBatteryLevel(),
                            isCharging = true
                        )
                        trySend(event)
                    }

                    Intent.ACTION_POWER_DISCONNECTED -> {
                        Log.d(TAG, "Charger disconnected")
                        val event = PowerEvent(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            eventType = "charging_stopped",
                            batteryLevel = getBatteryLevel(),
                            isCharging = false
                        )
                        trySend(event)
                    }

                    Intent.ACTION_BATTERY_LOW -> {
                        Log.d(TAG, "Battery low")
                        val event = PowerEvent(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            eventType = "battery_low",
                            batteryLevel = getBatteryLevel(),
                            isCharging = isCharging()
                        )
                        trySend(event)
                    }

                    Intent.ACTION_BATTERY_OKAY -> {
                        Log.d(TAG, "Battery okay")
                        val event = PowerEvent(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            eventType = "battery_okay",
                            batteryLevel = getBatteryLevel(),
                            isCharging = isCharging()
                        )
                        trySend(event)
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_LOW)
            addAction(Intent.ACTION_BATTERY_OKAY)
        }

        Log.d(TAG, "Registering power event receiver")
        context.registerReceiver(receiver, filter)

        // Send initial state
        val initialEvent = PowerEvent(
            deviceId = deviceId,
            recordedAt = Instant.now().toString(),
            eventType = if (powerManager.isInteractive) "wake" else "sleep",
            batteryLevel = getBatteryLevel(),
            isCharging = isCharging()
        )
        trySend(initialEvent)

        awaitClose {
            Log.d(TAG, "Unregistering power event receiver")
            context.unregisterReceiver(receiver)
        }
    }

    private fun getBatteryLevel(): Int {
        return batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun isCharging(): Boolean {
        val batteryStatus = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
            context.registerReceiver(null, filter)
        }

        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
               status == BatteryManager.BATTERY_STATUS_FULL
    }
}
