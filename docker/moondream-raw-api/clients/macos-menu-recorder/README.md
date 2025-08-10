# Moondream macOS Menu Bar Recorder

A macOS menu bar application that captures screenshots and sends them to the Moondream API for analysis.

## Features

- Menu bar icon for quick access
- Global hotkey (⌘⇧M) for instant capture
- Interactive screen capture
- Support for caption, query, and detect modes
- Configurable API endpoint
- Native macOS notifications for results

## Building

### Using Xcode
1. Open `MoondreamRecorder.swift` in Xcode
2. Create a new macOS app project
3. Replace the default ContentView with the provided code
4. Build and run

### Using Swift Package Manager
```bash
swift build
swift run MoondreamRecorder
```

## Usage

1. Click the camera icon in the menu bar
2. Configure the API endpoint (default: http://localhost:8001)
3. Choose a capture mode:
   - **Caption**: Generate description of the image
   - **Query**: Ask a question about the image
   - **Detect**: Detect objects in the image
4. Press ⌘⇧M or click "Capture Screen" to take a screenshot
5. The result will appear as a notification

## Requirements

- macOS 12.0 or later
- Moondream API running locally or remotely
- Screen recording permissions (will be requested on first use)

## Configuration

The app stores settings in UserDefaults:
- API endpoint
- Default capture mode

Access settings through the menu bar popup or the Settings window.