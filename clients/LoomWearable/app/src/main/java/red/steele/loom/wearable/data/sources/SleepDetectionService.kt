package red.steele.loom.wearable.data.sources

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*
import red.steele.loom.wearable.data.models.SleepState
import java.time.Instant
import kotlin.math.sqrt

class SleepDetectionService(
    private val context: Context,
    private val deviceId: String
) {
    companion object {
        private const val TAG = "SleepDetectionService"
        private const val MOTION_THRESHOLD = 0.5f
        private const val SLEEP_DETECTION_WINDOW = 300000L // 5 minutes
        private const val DEEP_SLEEP_THRESHOLD = 0.1f
        private const val LIGHT_SLEEP_THRESHOLD = 0.3f
    }

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private var currentState = "awake"
    private var stateStartTime = System.currentTimeMillis()
    private val motionHistory = mutableListOf<Float>()

    fun observeSleepState(analysisIntervalMs: Long = 30000L): Flow<SleepState> = callbackFlow {
        if (accelerometer == null) {
            Log.e(TAG, "Accelerometer not available")
            close()
            return@callbackFlow
        }

        val sensorListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                    val magnitude = sqrt(
                        event.values[0] * event.values[0] +
                        event.values[1] * event.values[1] +
                        event.values[2] * event.values[2]
                    )

                    // Remove gravity component (approximately 9.8)
                    val motion = kotlin.math.abs(magnitude - 9.8f)
                    motionHistory.add(motion)

                    // Keep only recent history
                    if (motionHistory.size > 300) { // ~5 minutes at 1Hz
                        motionHistory.removeAt(0)
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                Log.d(TAG, "Sensor accuracy changed: $accuracy")
            }
        }

        // Register sensor listener
        sensorManager.registerListener(
            sensorListener,
            accelerometer,
            SensorManager.SENSOR_DELAY_NORMAL
        )

        // Launch coroutine to analyze motion and detect sleep states
        val analysisJob = launch {
            while (isActive) {
                delay(analysisIntervalMs) // Analyze at configured interval

                if (motionHistory.size >= 30) {
                    val averageMotion = motionHistory.takeLast(150).average().toFloat()
                    val newState = when {
                        averageMotion < DEEP_SLEEP_THRESHOLD -> "deep_sleep"
                        averageMotion < LIGHT_SLEEP_THRESHOLD -> "light_sleep"
                        averageMotion < MOTION_THRESHOLD -> "light_sleep"
                        else -> "awake"
                    }

                    if (newState != currentState) {
                        val duration = System.currentTimeMillis() - stateStartTime

                        val sleepState = SleepState(
                            deviceId = deviceId,
                            recordedAt = Instant.now().toString(),
                            state = newState,
                            confidence = calculateConfidence(averageMotion, newState),
                            duration = duration
                        )

                        Log.d(TAG, "Sleep state changed: $currentState -> $newState " +
                                "(motion: $averageMotion, duration: ${duration/1000}s)")

                        trySend(sleepState)
                        currentState = newState
                        stateStartTime = System.currentTimeMillis()
                    }
                }
            }
        }

        // Also use heart rate variability if available
        observeHeartRateForSleep()
            .onEach { hrState ->
                trySend(hrState)
            }
            .launchIn(this)

        awaitClose {
            Log.d(TAG, "Stopping sleep detection")
            analysisJob.cancel()
            sensorManager.unregisterListener(sensorListener)
        }
    }

    private fun calculateConfidence(motion: Float, state: String): Float {
        return when (state) {
            "deep_sleep" -> if (motion < 0.05f) 0.9f else 0.7f
            "light_sleep" -> if (motion < 0.2f) 0.8f else 0.6f
            "awake" -> if (motion > 0.4f) 0.9f else 0.7f
            else -> 0.5f
        }
    }

    private fun observeHeartRateForSleep(): Flow<SleepState> = flow {
        // This would integrate with HeartRateDataSource to analyze HRV
        // For now, we'll just emit empty flow
        // In a real implementation, we'd look at heart rate variability patterns
    }
}
