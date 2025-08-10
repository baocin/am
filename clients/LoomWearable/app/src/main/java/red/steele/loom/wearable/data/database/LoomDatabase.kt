package red.steele.loom.wearable.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import red.steele.loom.wearable.data.database.dao.*
import red.steele.loom.wearable.data.database.entities.*

@Database(
    entities = [
        HeartRateEntity::class,
        GPSEntity::class,
        SleepStateEntity::class,
        PowerEventEntity::class,
        GenericDataEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class LoomDatabase : RoomDatabase() {
    abstract fun heartRateDao(): HeartRateDao
    abstract fun gpsDao(): GPSDao
    abstract fun sleepStateDao(): SleepStateDao
    abstract fun powerEventDao(): PowerEventDao
    abstract fun genericDataDao(): GenericDataDao

    companion object {
        @Volatile
        private var INSTANCE: LoomDatabase? = null

        fun getInstance(context: Context): LoomDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    LoomDatabase::class.java,
                    "loom_database"
                )
                    .fallbackToDestructiveMigration()
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
