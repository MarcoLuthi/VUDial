//
//  DialManager.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import Foundation
import AppKit
import SwiftData
import Combine

/// Manages VUDial hardware communication and state
@MainActor
class DialManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isScanning: Bool = false
    @Published var lastError: String?
    @Published var uploadProgress: Double = 0.0

    // MARK: - Dependencies
    private let serialManager: SerialPortManager
    private let modelContext: ModelContext

    // MARK: - State Tracking
    private var pendingUpdates: [String: PendingUpdate] = [:]  // UID -> Update
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 0.2  // 200ms

    // MARK: - Initialization

    init(serialManager: SerialPortManager, modelContext: ModelContext) {
        self.serialManager = serialManager
        self.modelContext = modelContext

        setupUpdateTimer()
    }

    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Connection Management

    /// Connect to VU Hub
    func connect() -> Bool {
        return serialManager.connect()
    }

    /// Disconnect from VU Hub
    func disconnect() {
        serialManager.disconnect()
    }

    // MARK: - Dial Discovery

    /// Scan I2C bus for dials
    func scanForDials() async {
        guard serialManager.isConnected else {
            lastError = "Not connected to VU Hub"
            return
        }

        isScanning = true
        defer { isScanning = false }

        // Send rescan command (fire-and-forget, no response expected)
        let rescanCommand = VUDialProtocol.rescanBusCommand()
        serialManager.sendCommandFireAndForget(rescanCommand)

        // Wait for bus scan to complete (VU Hub needs time to scan I2C bus)
        print("⏳ Waiting for I2C bus scan to complete...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        // Track discovered UIDs to avoid duplicates (VU Hub responds on all indexes)
        var discoveredUIDs = Set<String>()

        // Query each possible dial index (0-7) SEQUENTIALLY
        // This prevents command queue overflow and ensures responses match commands
        for index in 0..<8 {
            print("🔍 Querying dial at index \(index)...")
            guard let uid = await getDialUID(at: UInt8(index)) else {
                print("❌ No dial found at index \(index)")
                continue
            }
            print("✅ Found dial at index \(index): \(uid)")

            // Skip if we've already found this UID (VU Hub responds on all indexes)
            if discoveredUIDs.contains(uid) {
                print("ℹ️ Skipping duplicate UID \(uid) at index \(index)")
                continue
            }
            discoveredUIDs.insert(uid)

            // Check if dial already exists
            let descriptor = FetchDescriptor<Dial>(
                predicate: #Predicate { $0.uid == uid }
            )

            let existingDials = try? modelContext.fetch(descriptor)

            if let existingDial = existingDials?.first {
                // Update existing dial - use FIRST index where we found it
                existingDial.index = index
                existingDial.markSeen()
                print("📝 Updated existing dial '\(existingDial.name)' at index \(index)")
            } else {
                // Create new dial - use FIRST index where we found it
                let newDial = Dial(
                    uid: uid,
                    name: "VU Hub",
                    index: index
                )
                newDial.markSeen()
                modelContext.insert(newDial)
                print("✨ Created new dial 'VU Hub' at index \(index)")
            }
        }

        // Save changes
        try? modelContext.save()
    }

    /// Get UID of dial at specific index
    private func getDialUID(at index: UInt8) async -> String? {
        let command = VUDialProtocol.getUIDCommand(dialIndex: index)

        // Use the new async API which properly queues commands
        guard let responseData = await serialManager.sendCommandAsync(command),
              let response = VUDialProtocol.parseResponse(responseData) else {
            return nil
        }

        // UID is returned as hex string in payload (e.g., "00000007")
        let uid = response.payloadHexString

        // Skip if UID is all zeros (no dial present)
        guard !uid.isEmpty && uid != "00000000" else {
            return nil
        }

        return uid
    }

    // MARK: - Dial Control

    /// Set dial value (queued update)
    func setDialValue(_ dial: Dial, value: Double) {
        dial.setValue(value)
        queueUpdate(for: dial, type: .value)
    }

    /// Set dial backlight (queued update)
    func setDialBacklight(_ dial: Dial, red: Double, green: Double, blue: Double, white: Double) {
        dial.setBacklight(red: red, green: green, blue: blue, white: white)
        queueUpdate(for: dial, type: .backlight)
    }

    /// Upload image to dial
    func uploadImage(_ dial: Dial, image: NSImage) async {
        guard let packedData = ImageProcessor.convertImage(image) else {
            lastError = "Failed to process image"
            return
        }

        // Store image data
        dial.imageData = packedData

        uploadProgress = 0.0

        print("📤 Uploading image: \(packedData.count) bytes")

        // Step 1: Clear display (white background)
        print("🧹 Clearing display...")
        let clearCommand = VUDialProtocol.displayClearCommand(
            dialIndex: UInt8(dial.index),
            whiteBackground: true
        )
        serialManager.sendCommandFireAndForget(clearCommand)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Step 2: Reset cursor to origin (0, 0)
        print("📍 Resetting cursor to (0, 0)...")
        let gotoCommand = VUDialProtocol.displayGotoXYCommand(
            dialIndex: UInt8(dial.index),
            x: 0,
            y: 0
        )
        serialManager.sendCommandFireAndForget(gotoCommand)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Step 3: Upload in chunks aligned to column boundaries
        // Each column is 18 bytes, so use 900 bytes = 50 columns
        let bytesPerColumn = 18
        let columnsPerChunk = 50
        let chunkSize = bytesPerColumn * columnsPerChunk  // 900 bytes
        let totalChunks = (packedData.count + chunkSize - 1) / chunkSize

        print("📦 Sending \(totalChunks) chunks (column-aligned: \(columnsPerChunk) columns/chunk)...")

        for chunkIndex in 0..<totalChunks {
            let offset = chunkIndex * chunkSize
            let remainingBytes = packedData.count - offset
            let currentChunkSize = min(chunkSize, remainingBytes)

            let chunkData = packedData.subdata(in: offset..<(offset + currentChunkSize))

            // Send chunk (fire-and-forget, image data is streamed sequentially)
            let command = VUDialProtocol.displayImageDataCommand(
                dialIndex: UInt8(dial.index),
                data: chunkData
            )

            serialManager.sendCommandFireAndForget(command)
            print("   Chunk \(chunkIndex + 1)/\(totalChunks) (\(chunkData.count) bytes, \(chunkData.count / bytesPerColumn) columns)")

            // Update progress
            uploadProgress = Double(chunkIndex + 1) / Double(totalChunks)

            // Delay between chunks to avoid overwhelming VU Hub
            // Slightly longer delay to ensure hardware can process each chunk
            try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
        }

        // Step 4: Send show command to display the uploaded image
        print("🖼️ Sending display show command...")
        let showCommand = VUDialProtocol.displayShowImageCommand(dialIndex: UInt8(dial.index))
        serialManager.sendCommandFireAndForget(showCommand)

        uploadProgress = 0.0
        print("✅ Image upload complete")
    }

    // MARK: - Update Queue

    private func queueUpdate(for dial: Dial, type: UpdateType) {
        var update = pendingUpdates[dial.uid] ?? PendingUpdate()

        switch type {
        case .value:
            update.valueChanged = true
        case .backlight:
            update.backlightChanged = true
        }

        pendingUpdates[dial.uid] = update
    }

    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processQueuedUpdates()
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func processQueuedUpdates() async {
        guard serialManager.isConnected else { return }

        // Get all dials
        let descriptor = FetchDescriptor<Dial>()
        guard let dials = try? modelContext.fetch(descriptor) else { return }

        let dialsByUID = Dictionary(uniqueKeysWithValues: dials.map { ($0.uid, $0) })

        // Process each pending update (fire-and-forget for real-time control)
        for (uid, update) in pendingUpdates {
            guard let dial = dialsByUID[uid] else { continue }

            if update.valueChanged {
                let command = VUDialProtocol.setValueCommand(
                    dialIndex: UInt8(dial.index),
                    percentage: dial.currentValue
                )
                print("🎯 Sending dial value: \(dial.currentValue)% to index \(dial.index)")
                print("   Command: \(command)")
                serialManager.sendCommandFireAndForget(command)
            }

            if update.backlightChanged {
                let command = VUDialProtocol.setBacklightCommand(
                    dialIndex: UInt8(dial.index),
                    red: dial.red,
                    green: dial.green,
                    blue: dial.blue,
                    white: dial.white
                )
                print("💡 Sending backlight: R=\(dial.red) G=\(dial.green) B=\(dial.blue) W=\(dial.white)")
                serialManager.sendCommandFireAndForget(command)
            }
        }

        // Clear queue
        pendingUpdates.removeAll()
    }

    // MARK: - Helper Types

    private struct PendingUpdate {
        var valueChanged: Bool = false
        var backlightChanged: Bool = false
    }

    private enum UpdateType {
        case value
        case backlight
    }
}
