//
//  SerialPortManager.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import Foundation
import Combine
@preconcurrency import ORSSerial

/// Manages USB/serial communication with VU Hub device
class SerialPortManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var connectionStatus: String = "Disconnected"

    // MARK: - Constants
    private let targetVendorID: UInt16 = 0x0403  // FTDI VID
    private let targetProductID: UInt16 = 0x6015  // VU Hub PID
    private let baudRate: UInt32 = 115200
    private let responseTimeout: TimeInterval = 2.0  // 2 seconds (VU Hub batches commands)

    // MARK: - Private Properties
    private var serialPort: ORSSerialPort?

    // Command queue system (fixes race conditions)
    private let commandQueue = DispatchQueue(label: "com.vudial.serial.command", qos: .userInitiated)
    private var currentCommand: PendingCommand?
    private var responseBuffer = Data()
    private let bufferLock = NSLock()

    // MARK: - Initialization
    override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        disconnect()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup
    private func setupNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(serialPortsWereConnected(_:)),
            name: NSNotification.Name.ORSSerialPortsWereConnected,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(serialPortsWereDisconnected(_:)),
            name: NSNotification.Name.ORSSerialPortsWereDisconnected,
            object: nil
        )
    }

    // MARK: - Connection Management

    /// Discover and connect to VU Hub device
    func connect() -> Bool {
        guard let port = findVUHub() else {
            connectionStatus = "VU Hub not found"
            return false
        }

        serialPort = port
        serialPort?.baudRate = NSNumber(value: baudRate)
        serialPort?.numberOfStopBits = 1
        serialPort?.parity = .none
        serialPort?.delegate = self

        serialPort?.open()

        if let isOpen = serialPort?.isOpen, isOpen {
            isConnected = true
            connectionStatus = "Connected to VU Hub"
            return true
        } else {
            connectionStatus = "Failed to open port"
            return false
        }
    }

    /// Disconnect from VU Hub
    func disconnect() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        serialPort?.close()
        serialPort = nil
        isConnected = false
        connectionStatus = "Disconnected"

        // Clear any pending command
        currentCommand = nil
        responseBuffer.removeAll()
    }

    /// Find VU Hub by port name pattern
    /// VU Hub uses FTDI chip which appears as /dev/cu.usbserial-*
    private func findVUHub() -> ORSSerialPort? {
        let availablePorts = ORSSerialPortManager.shared().availablePorts

        print("📍 Available ports:")
        for port in availablePorts {
            print("  - \(port.path)")
        }

        // Priority 1: Look for cu.usbserial (preferred for VU Hub)
        for port in availablePorts {
            let portPath = port.path.lowercased()
            if portPath.contains("cu.usbserial") {
                print("✅ Found VU Hub at: \(port.path)")
                return port
            }
        }

        // Priority 2: Look for any usbserial or usbmodem
        for port in availablePorts {
            let portPath = port.path.lowercased()
            if portPath.contains("usbserial") || portPath.contains("usbmodem") {
                print("✅ Found potential VU Hub at: \(port.path)")
                return port
            }
        }

        // No USB-serial found
        print("❌ No USB-serial device found")
        return nil
    }

    // MARK: - Communication

    /// Send command and wait for response (synchronous, blocking)
    /// - Parameter command: Command string to send
    /// - Returns: Response data or nil on timeout/error
    func sendCommand(_ command: String) -> Data? {
        guard isConnected, serialPort != nil else {
            print("❌ Not connected to VU Hub")
            return nil
        }

        // Use a synchronous wrapper around the async version
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?

        Task {
            result = await sendCommandAsync(command)
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    /// Send command and wait for response (async/await)
    /// - Parameter command: Command string to send
    /// - Returns: Response data or nil on timeout/error
    func sendCommandAsync(_ command: String) async -> Data? {
        guard isConnected, let port = serialPort else {
            print("❌ Not connected to VU Hub")
            return nil
        }

        return await withCheckedContinuation { continuation in
            commandQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                // Prepare command
                let commandWithSuffix = command + "\r\n"
                guard let commandData = commandWithSuffix.data(using: .ascii) else {
                    print("❌ Failed to encode command")
                    continuation.resume(returning: nil)
                    return
                }

                // Create pending command BEFORE sending
                let pendingCommand = PendingCommand(
                    command: command,
                    continuation: continuation
                )

                // Set as current command BEFORE sending (critical!)
                self.bufferLock.lock()
                self.currentCommand = pendingCommand
                self.responseBuffer.removeAll()
                self.bufferLock.unlock()

                // Send command
                port.send(commandData)
                print("→ Sent: \(command)")

                // Start timeout timer
                self.commandQueue.asyncAfter(deadline: .now() + self.responseTimeout) { [weak self] in
                    self?.handleCommandTimeout(for: command)
                }
            }
        }
    }

    /// Handle command timeout
    private func handleCommandTimeout(for command: String) {
        bufferLock.lock()
        guard let pending = currentCommand, pending.command == command, !pending.isCompleted else {
            bufferLock.unlock()
            return
        }

        // Mark as completed and clear
        currentCommand?.isCompleted = true
        let continuation = currentCommand?.continuation
        currentCommand = nil
        responseBuffer.removeAll()
        bufferLock.unlock()

        print("⏱️ Command timed out: \(command)")
        continuation?.resume(returning: nil)
    }

    /// Complete current command with response
    private func completeCurrentCommand(with data: Data) {
        bufferLock.lock()
        guard let pending = currentCommand, !pending.isCompleted else {
            bufferLock.unlock()
            return
        }

        // Mark as completed
        currentCommand?.isCompleted = true
        let continuation = currentCommand?.continuation
        currentCommand = nil
        bufferLock.unlock()

        print("✅ Complete response received for: \(pending.command)")
        continuation?.resume(returning: data)
    }

    /// Send command without waiting for response (fire and forget)
    func sendCommandFireAndForget(_ command: String) {
        guard isConnected, let port = serialPort else {
            print("❌ Not connected to VU Hub")
            return
        }

        bufferLock.lock()
        defer { bufferLock.unlock() }

        // Send command with CR+LF suffix (required by VU Hub protocol)
        let commandWithSuffix = command + "\r\n"
        guard let commandData = commandWithSuffix.data(using: .ascii) else {
            print("❌ Failed to encode command")
            return
        }

        port.send(commandData)
        print("→ Sent (fire-and-forget): \(command)")
    }

    // MARK: - Notifications

    @objc private func serialPortsWereConnected(_ notification: Notification) {
        // Check if VU Hub was connected
        if !isConnected {
            DispatchQueue.main.async {
                _ = self.connect()
            }
        }
    }

    @objc private func serialPortsWereDisconnected(_ notification: Notification) {
        if let disconnectedPort = notification.userInfo?[ORSDisconnectedSerialPortsKey] as? [ORSSerialPort],
           let currentPort = serialPort,
           disconnectedPort.contains(currentPort) {
            DispatchQueue.main.async {
                self.disconnect()
            }
        }
    }
}

// MARK: - ORSSerialPortDelegate
extension SerialPortManager: ORSSerialPortDelegate {
    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        // Debug: Log raw data
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("📥 Received \(data.count) bytes: \(hexString)")

        // Try to decode as ASCII
        if let response = String(data: data, encoding: .ascii) {
            print("← Received (ASCII): \(response.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        // Accumulate data in buffer (thread-safe)
        bufferLock.lock()
        responseBuffer.append(data)

        // Check if response is complete (ends with \r\n)
        // VU Hub responses end with 0D 0A (\r\n)
        let isComplete = responseBuffer.count >= 2 &&
                        responseBuffer[responseBuffer.count - 2] == 0x0D &&
                        responseBuffer[responseBuffer.count - 1] == 0x0A

        if isComplete {
            // Make a copy of the complete response
            let completeResponse = responseBuffer
            bufferLock.unlock()

            // Complete the current command (outside lock)
            completeCurrentCommand(with: completeResponse)
        } else {
            bufferLock.unlock()
        }
    }

    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        DispatchQueue.main.async {
            self.disconnect()
        }
    }

    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        print("❌ Serial port error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.connectionStatus = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Types

/// Represents a command waiting for response
private class PendingCommand {
    let command: String
    let continuation: CheckedContinuation<Data?, Never>
    var isCompleted: Bool = false

    init(command: String, continuation: CheckedContinuation<Data?, Never>) {
        self.command = command
        self.continuation = continuation
    }
}
