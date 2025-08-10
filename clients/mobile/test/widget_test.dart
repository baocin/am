// Basic Flutter widget test for Loom mobile app

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api/loom_api_client.dart';
import 'package:mobile/core/services/device_manager.dart';
import 'package:mobile/services/data_collection_service.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Loom app loads without crashing', (WidgetTester tester) async {
    // Create mock services for testing
    final apiClient = await LoomApiClient.createFromSettings();
    final deviceManager = DeviceManager(apiClient);
    final dataService = DataCollectionService(deviceManager, apiClient);
    await dataService.initialize();

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(dataService: dataService));

    // Verify that the app title is present
    expect(find.text('Loom'), findsOneWidget);
    
    // Verify that main sections are present
    expect(find.text('Data Collection'), findsOneWidget);
    expect(find.text('Background Service'), findsOneWidget);
  });
}
