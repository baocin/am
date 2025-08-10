package red.steele.loom.wearable.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore

/**
 * Singleton DataStore manager to prevent multiple DataStore instances
 * accessing the same file, which causes crashes.
 */

// Define the extension property at the top level, outside any class or object
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "loom_settings")

object DataStoreManager {
    fun getDataStore(context: Context): DataStore<Preferences> {
        return context.dataStore
    }
}
