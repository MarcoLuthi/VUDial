//
//  DialControlView.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DialControlView: View {
    // MARK: - Properties
    @Bindable var dial: Dial
    @ObservedObject var dialManager: DialManager

    @State private var isUploadingImage = false
    @State private var showingImagePicker = false

    // MARK: - Body

    var body: some View {
        Form {
            // Dial Value Section
            Section("Dial Value") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Value:")
                        Spacer()
                        Text("\(Int(dial.currentValue))%")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $dial.currentValue, in: 0...100, step: 1) {
                        Text("Value")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    }
                    .onChange(of: dial.currentValue) { _, newValue in
                        dialManager.setDialValue(dial, value: newValue)
                    }
                }
            }

            // Backlight Section
            Section("Backlight (RGB)") {
                ColorSlider(
                    label: "Red",
                    value: $dial.red,
                    color: .red
                )
                .onChange(of: dial.red) { _, _ in
                    updateBacklight()
                }

                ColorSlider(
                    label: "Green",
                    value: $dial.green,
                    color: .green
                )
                .onChange(of: dial.green) { _, _ in
                    updateBacklight()
                }

                ColorSlider(
                    label: "Blue",
                    value: $dial.blue,
                    color: .blue
                )
                .onChange(of: dial.blue) { _, _ in
                    updateBacklight()
                }

                // Color preview
                HStack {
                    Text("Preview:")
                    Spacer()
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backlightColor)
                        .frame(width: 60, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            // Image Section
            Section("Background Image") {
                if let imageData = dial.imageData,
                   let image = ImageProcessor.unpackImage(imageData) {
                    HStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .border(Color.gray.opacity(0.3), width: 1)

                        Spacer()
                    }
                } else {
                    Text("No image uploaded")
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    showingImagePicker = true
                }) {
                    Label("Upload Image", systemImage: "photo")
                }

                if isUploadingImage {
                    ProgressView(value: dialManager.uploadProgress) {
                        Text("Uploading...")
                    }
                }
            }

            // Info Section
            Section("Information") {
                LabeledContent("Name", value: dial.name)
                LabeledContent("UID", value: dial.uid)
                LabeledContent("Index", value: "\(dial.index)")
                LabeledContent("Status", value: dial.isOnline ? "Online" : "Offline")
                LabeledContent("Last Seen", value: dial.lastSeen.formatted())
            }
        }
        .formStyle(.grouped)
        .navigationTitle(dial.name)
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.png, .jpeg, .heic],
            allowsMultipleSelection: false
        ) { result in
            handleImageSelection(result)
        }
    }

    // MARK: - Computed Properties

    private var backlightColor: Color {
        // Mix RGB colors (simplified - doesn't account for white channel in display)
        Color(
            red: dial.red / 100.0,
            green: dial.green / 100.0,
            blue: dial.blue / 100.0
        )
    }

    // MARK: - Methods

    private func updateBacklight() {
        dialManager.setDialBacklight(
            dial,
            red: dial.red,
            green: dial.green,
            blue: dial.blue
        )
    }

    private func handleImageSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start security-scoped access (required for sandboxed apps)
            let hasAccess = url.startAccessingSecurityScopedResource()
            if !hasAccess {
                print("⚠️ Could not get security-scoped access, trying direct load...")
            }

            // Load image data synchronously while we have access
            let imageData: Data?
            do {
                imageData = try Data(contentsOf: url)
            } catch {
                print("❌ Failed to read image data: \(error)")
                if hasAccess { url.stopAccessingSecurityScopedResource() }
                return
            }

            // Stop security-scoped access now that we have the data
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }

            // Create image from data
            guard let data = imageData, let nsImage = NSImage(data: data) else {
                print("❌ Failed to create image from data")
                return
            }

            print("✅ Loaded image: \(nsImage.size.width)x\(nsImage.size.height)")

            // Upload image
            isUploadingImage = true
            Task {
                await dialManager.uploadImage(dial, image: nsImage)
                isUploadingImage = false
            }

        case .failure(let error):
            print("❌ Image picker error: \(error)")
        }
    }
}

// MARK: - Color Slider Component

struct ColorSlider: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value))%")
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(value: $value, in: 0...100, step: 1)
                .tint(color)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var dial = Dial(
        uid: "ABC123",
        name: "Test Dial",
        index: 0,
        currentValue: 50,
        red: 80,
        green: 40,
        blue: 20
    )

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Dial.self, configurations: config)
    let serialManager = SerialPortManager()
    let dialManager = DialManager(serialManager: serialManager, modelContext: container.mainContext)

    NavigationStack {
        DialControlView(dial: dial, dialManager: dialManager)
    }
    .modelContainer(container)
}
