# VUDial

A native Swift package for controlling [VU1 Dials](https://vu1.io) — physical analog gauge displays featuring e-paper screens and RGB backlighting. Built with SwiftUI, SwiftData, and modern Swift concurrency.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.0+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **USB Auto-Discovery** — Automatically detects VU Hub devices
- **Real-time Control** — Smooth dial value updates with command batching
- **RGB Backlighting** — Full control over red, green, and blue LED channels
- **E-Paper Display** — Upload custom 1-bit images to the 200×144 pixel display
- **SwiftData Integration** — Persistent storage of dial configurations
- **Ready-to-Use Views** — Drop-in SwiftUI components for dial control

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0+
- VU Hub hardware connected via USB

## Installation

### Swift Package Manager

Add VUDial to your Xcode project:

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the repository URL:
   ```
   https://github.com/YOUR_USERNAME/VUDial
   ```
4. Select **Up to Next Major Version** from `1.0.0`
5. Click **Add Package**

Or add it directly to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_USERNAME/VUDial", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["VUDial"]
    )
]
```

## Quick Start

### Basic Setup

```swift
import SwiftUI
import SwiftData
import VUDial

@main
struct MyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Dial.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

### Using the Built-in Views

VUDial includes ready-to-use SwiftUI views for common tasks:

```swift
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var dials: [Dial]

    @StateObject private var serialManager = SerialPortManager()
    @State private var dialManager: DialManager?

    var body: some View {
        NavigationSplitView {
            if let manager = dialManager {
                DialDiscoveryView(
                    serialManager: serialManager,
                    dialManager: manager
                )
            }
        } detail: {
            if let dial = dials.first, let manager = dialManager {
                DialControlView(dial: dial, dialManager: manager)
            } else {
                Text("Select a dial")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            dialManager = DialManager(
                serialManager: serialManager,
                modelContext: modelContext
            )
        }
    }
}
```

### Headless / Programmatic Control

For scripts, CLI tools, or apps without SwiftData, use `VUDialClient`:

```swift
import VUDial

let client = VUDialClient()

if client.connect() {
    // Set dial to 75%
    client.setValue(dialIndex: 0, percentage: 75.0)

    // Set RGB backlight
    client.setBacklight(dialIndex: 0, red: 100, green: 0, blue: 50)

    // Upload an image
    if let image = NSImage(named: "gauge") {
        await client.uploadImage(dialIndex: 0, image: image)
    }
}
```

### With SwiftData

For apps that need persistence, use `DialManager`:

```swift
// Initialize managers
let serialManager = SerialPortManager()
let dialManager = DialManager(serialManager: serialManager, modelContext: context)

// Connect to VU Hub
if serialManager.connect() {
    // Scan for connected dials
    await dialManager.scanForDials()
}

// Control a dial
dialManager.setDialValue(dial, value: 75.0)  // 0-100%

// Set backlight color (RGB)
dialManager.setDialBacklight(
    dial,
    red: 100,    // 0-100%
    green: 0,
    blue: 50
)

// Upload custom image
if let image = NSImage(named: "gauge-face") {
    await dialManager.uploadImage(dial, image: image)
}
```

## API Reference

### Core Components

| Component | Description |
|-----------|-------------|
| `VUDialClient` | Lightweight client for headless/programmatic control (no SwiftData) |
| `SerialPortManager` | Handles USB device discovery and serial communication |
| `DialManager` | Manages dial state with SwiftData persistence |
| `Dial` | SwiftData model representing a dial's configuration |
| `ImageProcessor` | Converts images to the e-paper display format |
| `VUDialProtocol` | Low-level protocol encoder/decoder for custom implementations |

### SwiftUI Views

| View | Description |
|------|-------------|
| `DialDiscoveryView` | Connection status, device scanning, and dial list |
| `DialControlView` | Value slider, RGB controls, and image upload |

### Dial Model Properties

```swift
@Model
public class Dial {
    public var uid: String           // Unique hardware identifier
    public var name: String          // User-friendly name
    public var index: Int            // I2C bus position (0-7)
    public var currentValue: Double  // Dial value (0-100%)
    public var red: Double           // Red backlight (0-100%)
    public var green: Double         // Green backlight (0-100%)
    public var blue: Double          // Blue backlight (0-100%)
    public var isOnline: Bool        // Connection status
    public var imageData: Data?      // Current display image
}
```

### ImageProcessor

```swift
// Convert any image to VUDial format
let packedData = ImageProcessor.convertImage(nsImage)

// Create preview from packed data
let previewImage = ImageProcessor.unpackImage(packedData)

// Display dimensions
ImageProcessor.displayWidth   // 200 pixels
ImageProcessor.displayHeight  // 144 pixels
```

## Hardware Specifications

| Specification | Value |
|--------------|-------|
| Connection | USB (VID: 0x0403, PID: 0x6015) |
| Baud Rate | 115200 |
| Display | 200×144 pixels, 1-bit e-paper |
| Backlight | RGB LED, 0-100% per channel |
| Bus | I2C (up to 8 dials per hub) |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Your App                         │
├─────────────────────────────────────────────────────┤
│  DialDiscoveryView    │    DialControlView          │  ← SwiftUI Views
├─────────────────────────────────────────────────────┤
│                    DialManager                      │  ← Business Logic
├─────────────────────────────────────────────────────┤
│  SerialPortManager    │    ImageProcessor           │  ← Hardware Layer
├─────────────────────────────────────────────────────┤
│                  ORSSerialPort                      │  ← USB/Serial
└─────────────────────────────────────────────────────┘
```

## Examples

### Monitor CPU Usage

```swift
import VUDial

func updateCPUDial(_ dial: Dial, dialManager: DialManager) {
    let cpuUsage = getCurrentCPUUsage()  // Your implementation

    // Update dial value
    dialManager.setDialValue(dial, value: cpuUsage)

    // Color code: green → yellow → red based on usage
    if cpuUsage < 50 {
        dialManager.setDialBacklight(dial, red: 0, green: 100, blue: 0)
    } else if cpuUsage < 80 {
        dialManager.setDialBacklight(dial, red: 100, green: 100, blue: 0)
    } else {
        dialManager.setDialBacklight(dial, red: 100, green: 0, blue: 0)
    }
}
```

### Custom Gauge Face

```swift
import VUDial

func setCustomGaugeFace(_ dial: Dial, dialManager: DialManager) async {
    guard let image = NSImage(named: "speedometer") else { return }
    await dialManager.uploadImage(dial, image: image)
}
```

## Troubleshooting

### VU Hub Not Detected

1. Ensure the VU Hub is connected via USB
2. Check System Settings → Privacy & Security → USB for permissions
3. Try disconnecting and reconnecting the device

### Dial Not Responding

1. Verify the dial is powered and connected to the hub
2. Use `scanForDials()` to refresh the device list
3. Check the dial's `isOnline` status

### Image Upload Issues

- Images are automatically resized to 200×144 pixels
- Use high-contrast images for best results on e-paper
- Upload takes ~1-2 seconds due to hardware limitations

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [ORSSerialPort](https://github.com/armadsen/ORSSerialPort) for USB serial communication
- [VU1](https://vu1.io) for creating amazing hardware
