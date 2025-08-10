import Cocoa
import SwiftUI
import AVFoundation

@main
struct MoondreamRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var apiService = MoondreamAPIService()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupPopover()
        registerGlobalHotkey()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Moondream")
            button.action = #selector(togglePopover)
        }
    }
    
    func setupPopover() {
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.behavior = .transient
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    func registerGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+M for Moondream capture
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 46 {
                self.captureScreen()
            }
        }
    }
    
    func captureScreen() {
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-c"] // Interactive mode, to clipboard
        
        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.processClipboardImage()
            }
        }
        
        task.launch()
    }
    
    func processClipboardImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return
        }
        
        if let imageData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: imageData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            
            let base64String = pngData.base64EncodedString()
            apiService.sendImage(base64String) { result in
                DispatchQueue.main.async {
                    self.showNotification(result: result)
                }
            }
        }
    }
    
    func showNotification(result: String) {
        let notification = NSUserNotification()
        notification.title = "Moondream Analysis"
        notification.informativeText = result
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}

struct ContentView: View {
    @State private var apiEndpoint = "http://localhost:8001"
    @State private var captureMode = "caption"
    @State private var customQuestion = ""
    @State private var lastResult = ""
    @AppStorage("apiEndpoint") private var savedEndpoint = "http://localhost:8001"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Moondream Recorder")
                .font(.headline)
            
            Divider()
            
            // API Endpoint
            HStack {
                Text("API:")
                TextField("Endpoint", text: $apiEndpoint)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onAppear { apiEndpoint = savedEndpoint }
                    .onChange(of: apiEndpoint) { newValue in
                        savedEndpoint = newValue
                    }
            }
            
            // Capture Mode
            Picker("Mode:", selection: $captureMode) {
                Text("Caption").tag("caption")
                Text("Query").tag("query")
                Text("Detect").tag("detect")
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Custom Question for Query mode
            if captureMode == "query" {
                TextField("Question", text: $customQuestion)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Capture Button
            Button(action: captureNow) {
                Label("Capture Screen", systemImage: "camera")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            
            // Last Result
            if !lastResult.isEmpty {
                Divider()
                Text("Last Result:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(lastResult)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
            }
            
            Divider()
            
            // Shortcuts
            Text("Shortcuts:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("⌘⇧M - Quick Capture")
                .font(.caption)
            
            // Quit Button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 300)
    }
    
    func captureNow() {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.captureScreen()
    }
}

struct SettingsView: View {
    @AppStorage("apiEndpoint") private var apiEndpoint = "http://localhost:8001"
    @AppStorage("defaultMode") private var defaultMode = "caption"
    
    var body: some View {
        Form {
            TextField("API Endpoint:", text: $apiEndpoint)
            Picker("Default Mode:", selection: $defaultMode) {
                Text("Caption").tag("caption")
                Text("Query").tag("query")
                Text("Detect").tag("detect")
            }
        }
        .padding()
        .frame(width: 400, height: 150)
    }
}

class MoondreamAPIService {
    var endpoint = "http://localhost:8001"
    
    func sendImage(_ base64Image: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "\(endpoint)/caption") else {
            completion("Invalid API endpoint")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["image": "data:image/png;base64,\(base64Image)"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion("Error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let caption = json["caption"] as? String else {
                completion("Failed to parse response")
                return
            }
            
            completion(caption)
        }.resume()
    }
    
    func queryImage(_ base64Image: String, question: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "\(endpoint)/query") else {
            completion("Invalid API endpoint")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "image": "data:image/png;base64,\(base64Image)",
            "question": question
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion("Error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answer = json["answer"] as? String else {
                completion("Failed to parse response")
                return
            }
            
            completion(answer)
        }.resume()
    }
}