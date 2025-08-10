package red.steele.loom.wearable.workers

import android.content.Context
import android.util.Log
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import red.steele.loom.wearable.data.database.LoomDatabase
import red.steele.loom.wearable.data.repository.SensorDataRepository
import java.util.concurrent.TimeUnit

class CleanupWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "CleanupWorker"
        private const val WORK_NAME = "loom_cleanup_work"

        fun enqueuePeriodicWork(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .setRequiresBatteryNotLow(true)
                .build()

            val cleanupRequest = PeriodicWorkRequestBuilder<CleanupWorker>(
                1, TimeUnit.DAYS // Run once per day
            )
                .setConstraints(constraints)
                .setInitialDelay(1, TimeUnit.HOURS) // Initial delay of 1 hour
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                cleanupRequest
            )

            Log.d(TAG, "Cleanup work scheduled")
        }

        fun cancelWork(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "Cleanup work cancelled")
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Starting cleanup work")

            val database = LoomDatabase.getInstance(applicationContext)
            val repository = SensorDataRepository(database)

            // Perform cleanup
            repository.cleanupOldData()

            Log.d(TAG, "Cleanup work completed successfully")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Cleanup work failed", e)
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }
}
