//
//  VUDialProtocol.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import Foundation

/// VUDial protocol command encoder/decoder
/// Command format: >CCTTLLLLDD...
/// Response format: <CCTTLLLLDD...
struct VUDialProtocol {
    // MARK: - Command Bytes
    enum Command: UInt8 {
        case setValue = 0x03           // Set dial percentage
        case getUID = 0x0B            // Get dial unique ID
        case displayClear = 0x0D      // Clear display
        case displayGotoXY = 0x0E     // Set display cursor position
        case displayImageData = 0x0F  // Upload image data chunk
        case displayShowImage = 0x10  // Show uploaded image on display
        case setBacklight = 0x13      // Set RGB backlight
        case rescanBus = 0x1F         // Scan I2C bus for dials
        case getFirmwareVersion = 0x04 // Get firmware info
    }

    // MARK: - Data Types
    enum DataType: UInt8 {
        case none = 0x00
        case uint8 = 0x01
        case singleValue = 0x02    // Single value data
        case multipleValue = 0x03  // Multiple values (e.g., RGBW backlight)
        case keyValuePair = 0x04   // Used for commands with dial index + value pairs
        case statusCode = 0x05     // Used in responses
        case int32 = 0x06
        case float = 0x07
        case string = 0x08
    }

    // MARK: - Command Building

    /// Build command string in VU protocol format
    /// - Parameters:
    ///   - command: Command byte
    ///   - dataType: Data type byte
    ///   - payload: Hex-encoded payload data
    /// - Returns: Complete command string
    static func buildCommand(command: Command, dataType: DataType, payload: String = "") -> String {
        let length = payload.count / 2  // Each byte is 2 hex chars
        let lengthHex = String(format: "%04X", length)
        return ">\(toHex(command.rawValue))\(toHex(dataType.rawValue))\(lengthHex)\(payload)"
    }

    // MARK: - Set Value Command

    /// Create command to set dial value
    /// - Parameters:
    ///   - dialIndex: I2C bus index of dial (0-N)
    ///   - percentage: Value 0-100%
    /// - Returns: Command string
    static func setValueCommand(dialIndex: UInt8, percentage: Double) -> String {
        let clampedValue = max(0, min(100, percentage))
        let value = UInt8(clampedValue)  // Send 0-100 directly (not scaled to 255)

        let payload = "\(toHex(dialIndex))\(toHex(value))"
        return buildCommand(command: .setValue, dataType: .keyValuePair, payload: payload)
    }

    // MARK: - Set Backlight Command

    /// Create command to set RGB backlight
    /// - Parameters:
    ///   - dialIndex: I2C bus index of dial
    ///   - red: Red channel 0-100%
    ///   - green: Green channel 0-100%
    ///   - blue: Blue channel 0-100%
    /// - Returns: Command string
    static func setBacklightCommand(
        dialIndex: UInt8,
        red: Double,
        green: Double,
        blue: Double
    ) -> String {
        // Send 0-100 directly (not scaled to 255)
        let r = UInt8(max(0, min(100, red)))
        let g = UInt8(max(0, min(100, green)))
        let b = UInt8(max(0, min(100, blue)))
        let w: UInt8 = 0  // White channel not used but protocol requires 5 bytes

        let payload = "\(toHex(dialIndex))\(toHex(r))\(toHex(g))\(toHex(b))\(toHex(w))"
        return buildCommand(command: .setBacklight, dataType: .multipleValue, payload: payload)
    }

    // MARK: - Get UID Command

    /// Create command to get dial UID
    /// - Parameter dialIndex: I2C bus index of dial
    /// - Returns: Command string
    static func getUIDCommand(dialIndex: UInt8) -> String {
        let payload = toHex(dialIndex)
        return buildCommand(command: .getUID, dataType: .uint8, payload: payload)
    }

    // MARK: - Rescan Bus Command

    /// Create command to rescan I2C bus
    /// - Returns: Command string
    static func rescanBusCommand() -> String {
        return buildCommand(command: .rescanBus, dataType: .none)
    }

    // MARK: - Display Image Commands

    /// Create command to clear display
    /// - Parameters:
    ///   - dialIndex: I2C bus index of dial
    ///   - whiteBackground: true for white background, false for black
    /// - Returns: Command string
    static func displayClearCommand(dialIndex: UInt8, whiteBackground: Bool) -> String {
        let backgroundValue: UInt8 = whiteBackground ? 0 : 1
        let payload = "\(toHex(dialIndex))\(toHex(backgroundValue))"
        return buildCommand(command: .displayClear, dataType: .singleValue, payload: payload)
    }

    /// Create command to set display cursor position
    /// - Parameters:
    ///   - dialIndex: I2C bus index of dial
    ///   - x: X coordinate
    ///   - y: Y coordinate
    /// - Returns: Command string
    static func displayGotoXYCommand(dialIndex: UInt8, x: UInt16, y: UInt16) -> String {
        // Payload: dialIndex + x (2 bytes) + y (2 bytes)
        var payload = toHex(dialIndex)
        payload += String(format: "%04X", x)
        payload += String(format: "%04X", y)
        return buildCommand(command: .displayGotoXY, dataType: .singleValue, payload: payload)
    }

    /// Create command to send image data chunk
    /// - Parameters:
    ///   - dialIndex: I2C bus index of dial
    ///   - data: Image data bytes (chunk)
    /// - Returns: Command string
    static func displayImageDataCommand(dialIndex: UInt8, data: Data) -> String {
        // Payload: dialIndex + image data (NO offset - data is streamed sequentially)
        var payload = toHex(dialIndex)
        payload += data.map { String(format: "%02X", $0) }.joined()

        return buildCommand(command: .displayImageData, dataType: .singleValue, payload: payload)
    }

    /// Create command to show uploaded image on display
    /// - Parameter dialIndex: I2C bus index of dial
    /// - Returns: Command string
    static func displayShowImageCommand(dialIndex: UInt8) -> String {
        let payload = toHex(dialIndex)
        return buildCommand(command: .displayShowImage, dataType: .singleValue, payload: payload)
    }

    // MARK: - Response Parsing

    /// Parse response data
    /// - Parameter responseData: Raw response data
    /// - Returns: Parsed response or nil if invalid
    static func parseResponse(_ responseData: Data) -> ParsedResponse? {
        guard let responseString = String(data: responseData, encoding: .ascii) else {
            return nil
        }

        return parseResponse(responseString)
    }

    /// Parse response string
    /// - Parameter response: Response string in format <CCTTLLLLDD...
    /// - Returns: Parsed response or nil if invalid
    static func parseResponse(_ response: String) -> ParsedResponse? {
        // Clean whitespace/newlines
        let clean = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard clean.hasPrefix("<") else {
            print("❌ Invalid response (missing '<'): \(clean)")
            return nil
        }

        guard clean.count >= 9 else {  // Minimum: <CCTTLLLL
            print("❌ Response too short: \(clean)")
            return nil
        }

        let startIndex = clean.index(after: clean.startIndex)

        // Extract components
        let ccIndex = clean.index(startIndex, offsetBy: 2)
        let ttIndex = clean.index(ccIndex, offsetBy: 2)
        let llIndex = clean.index(ttIndex, offsetBy: 4)

        let commandHex = String(clean[startIndex..<ccIndex])
        let dataTypeHex = String(clean[ccIndex..<ttIndex])
        let lengthHex = String(clean[ttIndex..<llIndex])

        guard let commandByte = UInt8(commandHex, radix: 16),
              let dataTypeByte = UInt8(dataTypeHex, radix: 16),
              let length = Int(lengthHex, radix: 16) else {
            print("❌ Failed to parse response header: \(clean)")
            return nil
        }

        // Extract payload
        var payload = ""
        if length > 0 && clean.count >= (9 + length * 2) {
            let payloadStart = llIndex
            let payloadEnd = clean.index(payloadStart, offsetBy: length * 2)
            payload = String(clean[payloadStart..<payloadEnd])
        }

        return ParsedResponse(
            command: commandByte,
            dataType: dataTypeByte,
            length: length,
            payload: payload
        )
    }

    // MARK: - Helper Functions

    /// Convert byte to 2-character hex string
    private static func toHex(_ byte: UInt8) -> String {
        return String(format: "%02X", byte)
    }

    /// Convert hex string to Data
    static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var hex = hex

        // Remove any whitespace
        hex = hex.replacingOccurrences(of: " ", with: "")

        guard hex.count % 2 == 0 else {
            return nil
        }

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = String(hex[index..<nextIndex])

            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }

            data.append(byte)
            index = nextIndex
        }

        return data
    }
}

// MARK: - Response Type

/// Parsed response from VU Hub
struct ParsedResponse {
    let command: UInt8
    let dataType: UInt8
    let length: Int
    let payload: String

    /// Get payload as Data
    var payloadData: Data? {
        return VUDialProtocol.hexToData(payload)
    }

    /// Get payload as hex string (for UIDs and binary data)
    var payloadHexString: String {
        return payload
    }

    /// Get payload as ASCII string (for text responses)
    var payloadString: String? {
        guard let data = payloadData else { return nil }
        return String(data: data, encoding: .ascii)
    }

    /// Get payload as UInt8 array
    var payloadBytes: [UInt8]? {
        return payloadData?.map { $0 }
    }
}
