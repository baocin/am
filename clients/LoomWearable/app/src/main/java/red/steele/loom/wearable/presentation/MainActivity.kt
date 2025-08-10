/* While this template provides a good starting point for using Wear Compose, you can always
 * take a look at https://github.com/android/wear-os-samples/tree/main/ComposeStarter to find the
 * most up to date changes to the libraries and their usages.
 */

package red.steele.loom.wearable.presentation

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.*
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import red.steele.loom.wearable.data.models.PollingFrequency
import red.steele.loom.wearable.data.models.SyncStatus
import red.steele.loom.wearable.presentation.theme.LoomWearableTheme

class MainActivity : ComponentActivity() {

    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        // Handle permission results
        permissions.entries.forEach {
            println("Permission ${it.key}: ${it.value}")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        setTheme(android.R.style.Theme_DeviceDefault)

        // Request permissions
        val permissions = mutableListOf(
            Manifest.permission.BODY_SENSORS,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACTIVITY_RECOGNITION
        )

        // Add notification permission for Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        requestPermissions.launch(permissions.toTypedArray())

        // Request to ignore battery optimizations for reliable background operation
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                // Fallback to general battery optimization settings
                try {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    startActivity(intent)
                } catch (e: Exception) {
                    // Battery optimization settings not available on this device
                }
            }
        }

        setContent {
            LoomWearableApp()
        }
    }
}

@Composable
fun LoomWearableApp(
    viewModel: MainViewModel = viewModel()
) {
    LoomWearableTheme {
        val listState = rememberScalingLazyListState()

        Scaffold(
            timeText = {
                TimeText()
            },
            vignette = {
                Vignette(vignettePosition = VignettePosition.TopAndBottom)
            },
            positionIndicator = {
                PositionIndicator(
                    scalingLazyListState = listState
                )
            }
        ) {
            val isMonitoring by viewModel.isMonitoring.collectAsStateWithLifecycle()
            val connectionStatus by viewModel.connectionStatus.collectAsStateWithLifecycle()
            val heartRateEnabled by viewModel.heartRateEnabled.collectAsStateWithLifecycle()
            val gpsEnabled by viewModel.gpsEnabled.collectAsStateWithLifecycle()
            val sleepDetectionEnabled by viewModel.sleepDetectionEnabled.collectAsStateWithLifecycle()
            val lastHeartRate by viewModel.lastHeartRate.collectAsStateWithLifecycle()
            val statusMessage by viewModel.statusMessage.collectAsStateWithLifecycle()
            val pollingFrequency by viewModel.pollingFrequency.collectAsStateWithLifecycle()
            val deviceId by viewModel.deviceIdFlow.collectAsStateWithLifecycle()
            val serverUrl by viewModel.serverUrlFlow.collectAsStateWithLifecycle()
            val syncStatus by viewModel.syncStatus.collectAsStateWithLifecycle()

            ScalingLazyColumn(
                modifier = Modifier.fillMaxSize(),
                state = listState,
                contentPadding = PaddingValues(
                    top = 40.dp,
                    start = 8.dp,
                    end = 8.dp,
                    bottom = 40.dp
                ),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                autoCentering = AutoCenteringParams(itemIndex = 0)
            ) {
                // Header
                item {
                    Text(
                        text = "Loom Wearable",
                        style = MaterialTheme.typography.title2,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                // Device ID Display
                item {
                    Text(
                        text = "Device: ${deviceId?.takeLast(8) ?: "Generating..."}",
                        style = MaterialTheme.typography.caption3,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                // Full Device UUID (for manual registration)
                if (deviceId != null) {
                    item {
                        Card(
                            onClick = { /* Could add copy to clipboard here */ },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp),
                            backgroundPainter = CardDefaults.cardBackgroundPainter(
                                startBackgroundColor = MaterialTheme.colors.surface,
                                endBackgroundColor = MaterialTheme.colors.surface
                            )
                        ) {
                            Column(
                                modifier = Modifier.padding(8.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = "Full UUID:",
                                    style = MaterialTheme.typography.caption2,
                                    color = MaterialTheme.colors.onSurfaceVariant
                                )
                                Text(
                                    text = deviceId ?: "",
                                    style = MaterialTheme.typography.caption3,
                                    textAlign = TextAlign.Center,
                                    maxLines = 2
                                )
                            }
                        }
                    }
                }

                // Connection Status
                item {
                    Chip(
                        onClick = { /* No action for status display */ },
                        label = {
                            Text(
                                text = if (connectionStatus) "Connected" else "Disconnected",
                                style = MaterialTheme.typography.body2
                            )
                        },
                        secondaryLabel = {
                            Text(
                                text = statusMessage,
                                style = MaterialTheme.typography.caption3
                            )
                        },
                        icon = {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(
                                        color = if (connectionStatus) Color.Green else Color.Red,
                                        shape = MaterialTheme.shapes.small
                                    )
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = false
                    )
                }

                // Sync Status
                if (syncStatus.hasPendingData) {
                    item {
                        Chip(
                            onClick = { viewModel.forceSyncNow() },
                            label = {
                                Text(
                                    text = "Unsynced Data",
                                    style = MaterialTheme.typography.body2
                                )
                            },
                            secondaryLabel = {
                                Text(
                                    text = "${syncStatus.totalUnsynced} items pending - Tap to sync",
                                    style = MaterialTheme.typography.caption3
                                )
                            },
                            icon = {
                                Box(
                                    modifier = Modifier
                                        .size(8.dp)
                                        .background(
                                            color = Color.Yellow,
                                            shape = MaterialTheme.shapes.small
                                        )
                                )
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = connectionStatus // Only allow sync when connected
                        )
                    }
                }

                // Start/Stop Button
                item {
                    Button(
                        onClick = {
                            if (isMonitoring) {
                                viewModel.stopMonitoring()
                            } else {
                                viewModel.startMonitoring()
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(
                            backgroundColor = if (isMonitoring)
                                MaterialTheme.colors.error
                            else
                                MaterialTheme.colors.primary
                        ),
                        enabled = serverUrl.isNotBlank()
                    ) {
                        Text(
                            text = if (isMonitoring) "Stop Monitoring" else "Start Monitoring"
                        )
                    }
                }

                // Heart Rate Toggle
                item {
                    ToggleChip(
                        label = {
                            Text("Heart Rate")
                        },
                        secondaryLabel = {
                            Text(
                                text = lastHeartRate?.let { "$it bpm" } ?: "No data",
                                style = MaterialTheme.typography.caption3
                            )
                        },
                        checked = heartRateEnabled,
                        onCheckedChange = { viewModel.toggleHeartRate(it) },
                        toggleControl = {
                            Switch(
                                checked = heartRateEnabled,
                                enabled = !isMonitoring
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isMonitoring
                    )
                }

                // GPS Toggle
                item {
                    ToggleChip(
                        label = {
                            Text("GPS Location")
                        },
                        checked = gpsEnabled,
                        onCheckedChange = { viewModel.toggleGPS(it) },
                        toggleControl = {
                            Switch(
                                checked = gpsEnabled,
                                enabled = !isMonitoring
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isMonitoring
                    )
                }

                // Sleep Detection Toggle
                item {
                    ToggleChip(
                        label = {
                            Text("Sleep Detection")
                        },
                        checked = sleepDetectionEnabled,
                        onCheckedChange = { viewModel.toggleSleepDetection(it) },
                        toggleControl = {
                            Switch(
                                checked = sleepDetectionEnabled,
                                enabled = !isMonitoring
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isMonitoring
                    )
                }

                // Polling Frequency Selector
                item {
                    Text(
                        text = "Polling Frequency",
                        style = MaterialTheme.typography.caption1,
                        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                    )
                }

                // Frequency Options
                items(PollingFrequency.values()) { frequency ->
                    Chip(
                        label = {
                            Text(
                                text = frequency.displayName,
                                style = MaterialTheme.typography.body2
                            )
                        },
                        secondaryLabel = {
                            Text(
                                text = "HR: ${frequency.heartRateIntervalMs/1000}s, " +
                                      "GPS: ${frequency.gpsIntervalMs/1000}s",
                                style = MaterialTheme.typography.caption3
                            )
                        },
                        onClick = {
                            viewModel.updatePollingFrequency(frequency)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isMonitoring,
                        colors = ChipDefaults.chipColors(
                            backgroundColor = if (pollingFrequency == frequency)
                                MaterialTheme.colors.primary
                            else
                                MaterialTheme.colors.surface
                        )
                    )
                }

                // Server Configuration
                item {
                    Text(
                        text = "Server Configuration",
                        style = MaterialTheme.typography.caption1,
                        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                    )
                }

                // Current Server Display
                item {
                    Chip(
                        onClick = { /* Display only */ },
                        label = {
                            Text(
                                text = "Server",
                                style = MaterialTheme.typography.caption2
                            )
                        },
                        secondaryLabel = {
                            Text(
                                text = if (serverUrl.isBlank()) "Not configured" else serverUrl,
                                style = MaterialTheme.typography.caption3,
                                maxLines = 1
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = false
                    )
                }

                // Server Update Button
                item {
                    var showServerDialog by remember { mutableStateOf(false) }

                    CompactChip(
                        onClick = {
                            showServerDialog = true
                        },
                        label = {
                            Text(
                                text = "Change Server",
                                style = MaterialTheme.typography.caption2
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isMonitoring
                    )

                    // Server URL Input Dialog
                    if (showServerDialog) {
                        ServerInputDialog(
                            initialUrl = serverUrl,
                            onConfirm = { newUrl ->
                                viewModel.updateServerUrl(newUrl)
                                showServerDialog = false
                            },
                            onDismiss = {
                                showServerDialog = false
                            }
                        )
                    }
                }

                // Test Connection Button
                item {
                    var testingConnection by remember { mutableStateOf(false) }
                    var testResult by remember { mutableStateOf<String?>(null) }

                    CompactChip(
                        onClick = {
                            testingConnection = true
                            testResult = null
                            viewModel.testConnection { success, message ->
                                testingConnection = false
                                testResult = message
                            }
                        },
                        label = {
                            Text(
                                text = if (testingConnection) "Testing..." else "Test Connection",
                                style = MaterialTheme.typography.caption2
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isMonitoring && !testingConnection && serverUrl.isNotBlank()
                    )

                    // Show test result if available
                    testResult?.let { result ->
                        Text(
                            text = result,
                            style = MaterialTheme.typography.caption3,
                            color = if (result.contains("Success")) Color.Green else Color.Red,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun ServerInputDialog(
    initialUrl: String,
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var textFieldValue by remember { mutableStateOf(TextFieldValue(initialUrl)) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            onClick = { /* No action */ }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "Server URL",
                    style = MaterialTheme.typography.title3,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center
                )

                // Text input field
                BasicTextField(
                    value = textFieldValue,
                    onValueChange = { textFieldValue = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            MaterialTheme.colors.surface,
                            MaterialTheme.shapes.small
                        )
                        .padding(8.dp),
                    textStyle = MaterialTheme.typography.body2.copy(
                        color = MaterialTheme.colors.onSurface
                    ),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri
                    ),
                    singleLine = true
                )


                // Action buttons
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.secondaryButtonColors()
                    ) {
                        Text("Cancel")
                    }

                    Button(
                        onClick = {
                            onConfirm(textFieldValue.text)
                        },
                        modifier = Modifier.weight(1f),
                        enabled = textFieldValue.text.isNotBlank()
                    ) {
                        Text("OK")
                    }
                }
            }
        }
    }
}
