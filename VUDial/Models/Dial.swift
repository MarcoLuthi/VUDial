//
//  Dial.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import Foundation
import SwiftData

@Model
final class Dial {
    // MARK: - Identity

    /// Unique hardware identifier (from device)
    var uid: String

    /// User-friendly name
    var name: String

    /// Position on I2C bus (0-N)
    var index: Int

    // MARK: - State

    /// Current dial value (0-100%)
    var currentValue: Double

    /// Red backlight channel (0-100%)
    var red: Double

    /// Green backlight channel (0-100%)
    var green: Double

    /// Blue backlight channel (0-100%)
    var blue: Double

    /// Last communication timestamp
    var lastSeen: Date

    /// Is dial currently reachable
    var isOnline: Bool

    // MARK: - Image

    /// Current image data (1-bit packed, 6000 bytes)
    var imageData: Data?

    /// Image thumbnail for preview
    var imageThumbnail: Data?

    // MARK: - Initialization

    init(
        uid: String,
        name: String,
        index: Int,
        currentValue: Double = 0,
        red: Double = 0,
        green: Double = 0,
        blue: Double = 0
    ) {
        self.uid = uid
        self.name = name
        self.index = index
        self.currentValue = currentValue
        self.red = red
        self.green = green
        self.blue = blue
        self.lastSeen = Date()
        self.isOnline = false
        self.imageData = nil
        self.imageThumbnail = nil
    }

    // MARK: - Convenience

    /// Update backlight colors
    func setBacklight(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Update dial value
    func setValue(_ value: Double) {
        self.currentValue = max(0, min(100, value))
    }

    /// Mark as seen (online)
    func markSeen() {
        self.lastSeen = Date()
        self.isOnline = true
    }

    /// Mark as offline
    func markOffline() {
        self.isOnline = false
    }
}
