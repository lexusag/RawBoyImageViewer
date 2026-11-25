package app.rawboy.viewer.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.rawboy.viewer.core.PhotoSort
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "viewer_settings")

enum class StartupMode(val raw: String, val label: String) {
    LAST("last", "Last folder"),
    PICTURES("pictures", "Pictures & DCIM"),
    CUSTOM("custom", "Default folder");

    companion object {
        fun fromRaw(raw: String?): StartupMode = entries.firstOrNull { it.raw == raw } ?: LAST
    }
}

data class ViewerPrefs(
    val lastFolderUri: String? = null,
    val defaultFolderUri: String? = null,
    val startupMode: StartupMode = StartupMode.LAST,
    val sort: PhotoSort = PhotoSort.DATE,
    val autoAdvanceAfterRating: Boolean = true,
    val writeXmpBeforeSend: Boolean = false,
    val includeJpegsInBatch: Boolean = false,
    val enableBinOption: Boolean = true,
    val lastAutoMode: String = "looks",
)

class ViewerSettings(private val context: Context) {
    private object Keys {
        val LAST_FOLDER = stringPreferencesKey("last_folder_uri")
        val DEFAULT_FOLDER = stringPreferencesKey("default_folder_uri")
        val STARTUP_MODE = stringPreferencesKey("startup_mode")
        val SORT = stringPreferencesKey("sort")
        val AUTO_ADVANCE = booleanPreferencesKey("auto_advance")
        val WRITE_XMP_BEFORE_SEND = booleanPreferencesKey("write_xmp_before_send")
        val INCLUDE_JPEGS_IN_BATCH = booleanPreferencesKey("include_jpegs_in_batch")
        val ENABLE_BIN = booleanPreferencesKey("enable_bin")
        val LAST_AUTO_MODE = stringPreferencesKey("last_auto_mode")
    }

    val prefs: Flow<ViewerPrefs> = context.dataStore.data.map { p ->
        ViewerPrefs(
            lastFolderUri = p[Keys.LAST_FOLDER],
            defaultFolderUri = p[Keys.DEFAULT_FOLDER],
            startupMode = StartupMode.fromRaw(p[Keys.STARTUP_MODE]),
            sort = PhotoSort.fromRaw(p[Keys.SORT]),
            autoAdvanceAfterRating = p[Keys.AUTO_ADVANCE] ?: true,
            writeXmpBeforeSend = p[Keys.WRITE_XMP_BEFORE_SEND] ?: false,
            includeJpegsInBatch = p[Keys.INCLUDE_JPEGS_IN_BATCH] ?: false,
            enableBinOption = p[Keys.ENABLE_BIN] ?: true,
            lastAutoMode = p[Keys.LAST_AUTO_MODE] ?: "looks",
        )
    }

    suspend fun setLastFolder(uri: String?) = context.dataStore.edit {
        if (uri == null) it.remove(Keys.LAST_FOLDER) else it[Keys.LAST_FOLDER] = uri
    }

    suspend fun setDefaultFolder(uri: String?) = context.dataStore.edit {
        if (uri == null) it.remove(Keys.DEFAULT_FOLDER) else it[Keys.DEFAULT_FOLDER] = uri
    }

    suspend fun setStartupMode(mode: StartupMode) = context.dataStore.edit { it[Keys.STARTUP_MODE] = mode.raw }
    suspend fun setSort(sort: PhotoSort) = context.dataStore.edit { it[Keys.SORT] = sort.raw }
    suspend fun setAutoAdvance(v: Boolean) = context.dataStore.edit { it[Keys.AUTO_ADVANCE] = v }
    suspend fun setWriteXmpBeforeSend(v: Boolean) = context.dataStore.edit { it[Keys.WRITE_XMP_BEFORE_SEND] = v }
    suspend fun setIncludeJpegsInBatch(v: Boolean) = context.dataStore.edit { it[Keys.INCLUDE_JPEGS_IN_BATCH] = v }
    suspend fun setEnableBin(v: Boolean) = context.dataStore.edit { it[Keys.ENABLE_BIN] = v }
    suspend fun setLastAutoMode(mode: String) = context.dataStore.edit { it[Keys.LAST_AUTO_MODE] = mode }
}
