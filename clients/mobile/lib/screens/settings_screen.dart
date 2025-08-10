import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/loom_api_client.dart';
import '../services/data_collection_service.dart';
import '../core/config/data_collection_config.dart';

class SettingsScreen extends StatefulWidget {
  final DataCollectionService? dataService;

  const SettingsScreen({super.key, this.dataService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  String _currentUrl = LoomApiClient.defaultBaseUrl;
  String _currentApiKey = LoomApiClient.defaultApiKey;
  bool _isLoading = false;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('loom_api_base_url') ?? LoomApiClient.defaultBaseUrl;
    final apiKey = prefs.getString('loom_api_key') ?? LoomApiClient.defaultApiKey;
    setState(() {
      _currentUrl = url;
      _currentApiKey = apiKey;
      _urlController.text = url;
      _apiKeyController.text = apiKey;
    });
  }

  Future<void> _saveSettings() async {
    if (_urlController.text.trim().isEmpty) {
      _showSnackBar('URL cannot be empty', isError: true);
      return;
    }

    final url = _urlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    // Basic URL validation
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _showSnackBar('URL must start with http:// or https://', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loom_api_base_url', url);
      await prefs.setString('loom_api_key', apiKey.isEmpty ? LoomApiClient.defaultApiKey : apiKey);

      setState(() {
        _currentUrl = url;
        _currentApiKey = apiKey.isEmpty ? LoomApiClient.defaultApiKey : apiKey;
        _isLoading = false;
      });

      _showSnackBar('Settings updated successfully! Restart the app for changes to take effect.');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to save settings: $e', isError: true);
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _urlController.text = LoomApiClient.defaultBaseUrl;
      _apiKeyController.text = LoomApiClient.defaultApiKey;
    });
  }

  Future<void> _testConnection() async {
    if (_urlController.text.trim().isEmpty) {
      _showSnackBar('Please enter a URL first', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create a test API client with the new URL and API key
      final testClient = LoomApiClient(
        baseUrl: _urlController.text.trim(),
        apiKey: _apiKeyController.text.trim().isEmpty
          ? LoomApiClient.defaultApiKey
          : _apiKeyController.text.trim(),
      );

      // Use the health check endpoint which returns 200 when server is healthy
      final response = await testClient.getHealthz();

      if (response['status'] == 'healthy') {
        _showSnackBar('Connection test successful! Server is healthy.');
      } else {
        _showSnackBar('Server responded but is not healthy: ${response['status']}', isError: true);
      }
    } catch (e) {
      // Check for different types of connection errors
      if (e.toString().contains('connection') || e.toString().contains('timeout')) {
        _showSnackBar('Connection failed: Server unreachable', isError: true);
      } else if (e.toString().contains('invalid') || e.toString().contains('format')) {
        _showSnackBar('Invalid server response. Check the URL.', isError: true);
      } else {
        _showSnackBar('Connection test failed: ${e.toString()}', isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<void> _enableDevMode() async {
    if (widget.dataService == null) {
      _showSnackBar('Data service not available', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Get all available data sources
      final dataSources = widget.dataService!.availableDataSources;

      // Set all data sources to minimum collection interval and batch size 1
      for (final sourceId in dataSources.keys) {
        final config = widget.dataService!.config?.getConfig(sourceId) ?? const DataSourceConfigParams();

        // Create dev mode config: minimum collection interval, immediate transmission
        final devConfig = config.copyWith(
          collectionIntervalMs: sourceId == 'audio' ? 5000 : 1000, // Audio needs longer chunks
        );

        await widget.dataService!.updateDataSourceConfig(sourceId, devConfig);
      }

      setState(() {
        _isLoading = false;
      });

      _showSnackBar('Dev Mode enabled! All sources set to immediate upload.');

      // Show confirmation dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dev Mode Enabled'),
          content: const Text(
            'All data sources have been configured for immediate upload:\n\n'
            '• Upload batch size: 1\n'
            '• Collection interval: 1 second\n'
            '• Upload interval: 5 seconds\n\n'
            'This will increase battery usage but provides real-time data visibility.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to enable Dev Mode: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Loom Backend API Server',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure the URL for the Loom backend API server',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),

            // Current URL display
            Card(
              child: ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Current Server URL'),
                subtitle: Text(_currentUrl),
                trailing: Icon(
                  Icons.circle,
                  color: _currentUrl == LoomApiClient.defaultBaseUrl
                      ? Colors.blue
                      : Colors.orange,
                  size: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // URL input field
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://10.0.2.2:8000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
                helperText: 'Use 10.0.2.2 for Android emulator, localhost for real device on same network',
              ),
              keyboardType: TextInputType.url,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),

            // API Key input field
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'Enter API key (optional)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _showApiKey = !_showApiKey;
                    });
                  },
                ),
                helperText: 'Leave empty to use default key',
              ),
              obscureText: !_showApiKey,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testConnection,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Reset button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _resetToDefault,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset to Default'),
              ),
            ),
            const SizedBox(height: 24),

            // Settings Guide
            const Text(
              'Settings Guide',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'For local development:\n'
              '• Android Emulator: Use 10.0.2.2:8000\n'
              '• Real Device: Use your computer\'s IP address\n'
              '• iOS Simulator: Use localhost:8000',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),

            // Dev Mode button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _enableDevMode,
                icon: const Icon(Icons.developer_mode),
                label: const Text('Dev Mode'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const Spacer(),

            // App info
            Center(
              child: Text(
                'Loom Mobile v1.0.0\nred.steele.loom',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
