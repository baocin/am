#!/bin/bash

echo "Starting Loom Flutter app..."
echo ""
echo "Note: The app will work even though device registration returns 404."
echo "This is expected - the ingestion API doesn't have device management endpoints."
echo ""
echo "If the app crashes due to Google Play Services errors, this is a known"
echo "issue with Android emulators. The app works fine on real devices."
echo ""

# Run Flutter app
flutter run

# Alternative: Run without sound null safety for better error handling
# flutter run --no-sound-null-safety