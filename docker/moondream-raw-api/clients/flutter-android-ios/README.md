# Moondream Vision - Flutter App

A cross-platform Flutter application for iOS and Android that interfaces with the Moondream API.

## Features

- Camera and gallery image selection
- Multiple analysis modes:
  - Caption generation
  - Visual question answering
  - Object detection
  - Object pointing
- Configurable API endpoint
- Clean Material 3 UI
- Works on both iOS and Android

## Setup

### Prerequisites
- Flutter SDK 3.0 or higher
- Xcode (for iOS development)
- Android Studio (for Android development)

### Installation

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. iOS specific setup:
```bash
cd ios
pod install
cd ..
```

### Permissions

Add these permissions to your platform-specific files:

#### iOS (ios/Runner/Info.plist)
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to capture images for analysis</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs photo library access to select images for analysis</string>
```

#### Android (android/app/src/main/AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.INTERNET" />
```

## Running the App

### iOS Simulator
```bash
flutter run -d ios
```

### Android Emulator
```bash
flutter run -d android
```

### Physical Device
```bash
flutter run
```

## Building for Release

### iOS
```bash
flutter build ios --release
```
Then open the Xcode project and archive for distribution.

### Android
```bash
flutter build apk --release
# or for App Bundle
flutter build appbundle --release
```

## Configuration

The app stores the API endpoint in SharedPreferences. Default is `http://localhost:8001`.

To connect to a remote server, update the endpoint in Settings.

## Features in Detail

### Caption Mode
Generates a detailed description of the selected image.

### Query Mode
Ask custom questions about the image and get AI-powered answers.

### Detect Mode
Identify and locate specific objects within the image.

### Point Mode
Get precise coordinates for objects mentioned in prompts.

## Troubleshooting

### Connection Issues
- Ensure the Moondream API is running
- Check the API endpoint in settings
- For local development, use:
  - iOS Simulator: `http://localhost:8001`
  - Android Emulator: `http://10.0.2.2:8001`
  - Physical device: Use your computer's IP address

### Permission Denied
- Check that camera and photo permissions are granted in device settings
- Reinstall the app if permissions were previously denied