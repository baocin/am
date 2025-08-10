package red.steele.loom.wearable.data.sources

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import red.steele.loom.wearable.data.models.GPSReading
import java.time.Instant

class GPSDataSource(
    private val context: Context,
    private val deviceId: String
) {
    companion object {
        private const val TAG = "GPSDataSource"
        private const val MIN_DISTANCE = 5f // 5 meters
    }

    private val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)

    fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun observeLocation(
        intervalMs: Long = 10000L,
        highAccuracy: Boolean = true
    ): Flow<GPSReading> = callbackFlow {
        if (!hasLocationPermission()) {
            Log.e(TAG, "Location permission not granted")
            close(SecurityException("Location permission not granted"))
            return@callbackFlow
        }

        val locationRequest = LocationRequest.Builder(
            if (highAccuracy) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY,
            intervalMs
        ).apply {
            setMinUpdateIntervalMillis(intervalMs / 2) // Fastest interval is half the requested interval
            setMinUpdateDistanceMeters(MIN_DISTANCE)
            setWaitForAccurateLocation(false)
        }.build()

        val locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.locations.forEach { location ->
                    val reading = locationToReading(location)
                    Log.d(TAG, "Location update: ${reading.latitude}, ${reading.longitude} " +
                            "(accuracy: ${reading.accuracy}m)")
                    trySend(reading)
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                Log.d(TAG, "Location availability: ${availability.isLocationAvailable}")
            }
        }

        try {
            Log.d(TAG, "Starting location updates (highAccuracy: $highAccuracy)")
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )

            // Get last known location immediately
            fusedLocationClient.lastLocation.addOnSuccessListener { location ->
                location?.let {
                    val reading = locationToReading(it)
                    Log.d(TAG, "Last known location: ${reading.latitude}, ${reading.longitude}")
                    trySend(reading)
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception requesting location updates", e)
            close(e)
        }

        awaitClose {
            Log.d(TAG, "Stopping location updates")
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
    }

    private fun locationToReading(location: Location): GPSReading {
        return GPSReading(
            deviceId = deviceId,
            recordedAt = Instant.now().toString(),
            latitude = location.latitude,
            longitude = location.longitude,
            altitude = if (location.hasAltitude()) location.altitude else null,
            accuracy = if (location.hasAccuracy()) location.accuracy else null,
            heading = if (location.hasBearing()) location.bearing else null,
            speed = if (location.hasSpeed()) location.speed else null
        )
    }
}
