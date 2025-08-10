import 'package:flutter/material.dart';
import '../core/config/websocket_config.dart';
import '../services/unified_websocket_service.dart';

class WebSocketSettingsWidget extends StatefulWidget {
  const WebSocketSettingsWidget({Key? key}) : super(key: key);

  @override
  State<WebSocketSettingsWidget> createState() => _WebSocketSettingsWidgetState();
}

class _WebSocketSettingsWidgetState extends State<WebSocketSettingsWidget> {
  bool _useWebSocket = true;
  int _batchSize = 10;
  int _batchTimeoutMs = 5000;
  bool _isConnected = false;
  Map<String, dynamic>? _statistics;
  
  final UnifiedWebSocketService _webSocketService = UnifiedWebSocketService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    
    // Listen to connection status
    _webSocketService.connectionStatusStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          if (connected) {
            _statistics = _webSocketService.statistics;
          }
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    final config = await WebSocketConfig.getConfiguration();
    if (mounted) {
      setState(() {
        _useWebSocket = config['useWebSocket'];
        _batchSize = config['batchSize'];
        _batchTimeoutMs = config['batchTimeoutMs'];
        _isConnected = _webSocketService.isConnected;
        _statistics = _webSocketService.statistics;
      });
    }
  }

  Future<void> _saveSettings() async {
    await WebSocketConfig.setUseWebSocket(_useWebSocket);
    await WebSocketConfig.setBatchSize(_batchSize);
    await WebSocketConfig.setBatchTimeoutMs(_batchTimeoutMs);
    
    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WebSocket settings saved. Restart app to apply changes.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Data Upload Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Connected',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // WebSocket toggle
            SwitchListTile(
              title: const Text('Use WebSocket'),
              subtitle: const Text('Real-time data streaming (recommended)'),
              value: _useWebSocket,
              onChanged: (value) {
                setState(() {
                  _useWebSocket = value;
                });
              },
            ),
            
            if (_useWebSocket) ...[
              const SizedBox(height: 16),
              
              // Batch size
              ListTile(
                title: const Text('Batch Size'),
                subtitle: Text('Upload data in batches of $_batchSize items'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _batchSize > 1
                          ? () => setState(() => _batchSize--)
                          : null,
                    ),
                    Text('$_batchSize'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _batchSize < 100
                          ? () => setState(() => _batchSize++)
                          : null,
                    ),
                  ],
                ),
              ),
              
              // Batch timeout
              ListTile(
                title: const Text('Batch Timeout'),
                subtitle: Text('Upload after ${_batchTimeoutMs / 1000} seconds'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _batchTimeoutMs > 1000
                          ? () => setState(() => _batchTimeoutMs -= 1000)
                          : null,
                    ),
                    Text('${_batchTimeoutMs / 1000}s'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _batchTimeoutMs < 60000
                          ? () => setState(() => _batchTimeoutMs += 1000)
                          : null,
                    ),
                  ],
                ),
              ),
              
              // Statistics
              if (_statistics != null) ...[
                const Divider(),
                const Text(
                  'WebSocket Statistics',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Messages Sent: ${_statistics!['messagesSent']}'),
                Text('Messages Received: ${_statistics!['messagesReceived']}'),
                Text('Reconnect Attempts: ${_statistics!['reconnectAttempts']}'),
              ],
            ],
            
            const SizedBox(height: 16),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await WebSocketConfig.resetToDefaults();
                    await _loadSettings();
                  },
                  child: const Text('Reset to Defaults'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}