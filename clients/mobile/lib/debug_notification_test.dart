import 'package:flutter/material.dart';
import 'package:mobile/services/device_websocket_service.dart';

class DebugNotificationTest extends StatelessWidget {
  const DebugNotificationTest({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final deviceWebSocketService = DeviceWebSocketService();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Notification Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                // Test showing a notification with actions
                await deviceWebSocketService.testNotificationWithActions();
              },
              child: const Text('Show Test Notification'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // Test manual response for notification 105
                await deviceWebSocketService.testManualResponse(105);
              },
              child: const Text('Send Manual Response (ID: 105)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // Test manual response for notification 106
                await deviceWebSocketService.testManualResponse(106);
              },
              child: const Text('Send Manual Response (ID: 106)'),
            ),
            const SizedBox(height: 20),
            StreamBuilder<bool>(
              stream: deviceWebSocketService.connectionStatusStream,
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? false;
                return Text(
                  'WebSocket: ${isConnected ? "Connected" : "Disconnected"}',
                  style: TextStyle(
                    color: isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}