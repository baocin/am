package red.steele.loom.wearable.data.sources

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import red.steele.loom.wearable.data.models.HeartRateReading
import java.time.Instant

class HeartRateDataSource(
    private val context: Context,
    private val deviceId: String
) {
    companion object {
        private const val TAG = "HeartRateDataSource"
    }

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val heartRateSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)

    // For detecting if watch is on wrist - Android Wear uses TYPE_LOW_LATENCY_OFFBODY_DETECT
    private val offBodySensor = sensorManager.getDefaultSensor(Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT)
    private var isOnBody = true // Default to true, update based on sensor

    // Callback for on-body status changes
    var onBodyStatusCallback: ((Boolean) -> Unit)? = null

    suspend fun isHeartRateAvailable(): Boolean {
        val available = heartRateSensor != null
        Log.d(TAG, "Heart rate sensor available: $available")
        return available
    }

    fun observeHeartRate(intervalMs: Long = 5000L): Flow<HeartRateReading> = callbackFlow {
        if (heartRateSensor == null) {
            Log.e(TAG, "Heart rate sensor not available on this device")
            close(IllegalStateException("Heart rate sensor not available"))
            return@callbackFlow
        }

        Log.d(TAG, "Starting heart rate monitoring using TYPE_HEART_RATE sensor")
        Log.d(TAG, "Off-body detection sensor available: ${offBodySensor != null}")

        val sensorListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                when (event.sensor.type) {
                    Sensor.TYPE_LOW_LATENCY_OFFBODY_DETECT -> {
                        // 1.0 = on body, 0.0 = off body
                        val newOnBodyStatus = event.values[0] > 0.5f
                        if (newOnBodyStatus != isOnBody) {
                            isOnBody = newOnBodyStatus
                            Log.d(TAG, "Off-body sensor changed: isOnBody=$isOnBody (value=${event.values[0]})")
                            // Notify about on-body status change
                            onBodyStatusCallback?.invoke(isOnBody)
                        }
                    }

                    Sensor.TYPE_HEART_RATE -> {
                        // Only process heart rate if watch is on body
                        if (!isOnBody) {
                            Log.d(TAG, "Ignoring heart rate reading - watch is not on wrist")
                            return
                        }

                        val bpm = event.values[0].toInt()

                        // Calculate confidence based on sensor accuracy and whether watch is on body
                        val confidence = when (event.accuracy) {
                            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 1.0f
                            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 0.75f
                            SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 0.5f
                            else -> 0.25f
                        }

                        val reading = HeartRateReading(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            bpm = bpm,
                            confidence = confidence,
                            source = "sensor_api",
                            metadata = mapOf("on_body" to isOnBody.toString())
                        )

                        Log.d(TAG, "Heart rate: $bpm bpm (accuracy: ${event.accuracy}, confidence: $confidence, on_body: $isOnBody)")
                        trySend(reading)
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                Log.d(TAG, "Sensor accuracy changed: ${sensor?.name} -> $accuracy")
            }
        }

        try {
            // Register heart rate sensor
            val heartRateRegistered = sensorManager.registerListener(
                sensorListener,
                heartRateSensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )

            if (!heartRateRegistered) {
                Log.e(TAG, "Failed to register heart rate sensor listener")
                close(IllegalStateException("Failed to register heart rate sensor"))
                return@callbackFlow
            } else {
                Log.d(TAG, "Heart rate sensor listener registered successfully")
            }

            // Register off-body detection sensor if available
            if (offBodySensor != null) {
                val offBodyRegistered = sensorManager.registerListener(
                    sensorListener,
                    offBodySensor,
                    SensorManager.SENSOR_DELAY_NORMAL
                )

                if (offBodyRegistered) {
                    Log.d(TAG, "Off-body detection sensor registered successfully")
                } else {
                    Log.w(TAG, "Failed to register off-body detection sensor - will always assume on-body")
                }
            } else {
                Log.w(TAG, "Off-body detection sensor not available - will always assume on-body")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception registering sensor listeners", e)
            close(e)
        }

        awaitClose {
            Log.d(TAG, "Unregistering heart rate sensor listener")
            sensorManager.unregisterListener(sensorListener)
        }
    }
}
