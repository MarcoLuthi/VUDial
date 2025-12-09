//
//  ImageProcessor.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import AppKit
import CoreGraphics

/// Processes images for VUDial e-paper display
struct ImageProcessor {
    // MARK: - Constants
    static let displayWidth: Int = 200   // Display is 200 wide × 144 tall
    static let displayHeight: Int = 144
    static let threshold: UInt8 = 127  // Grayscale threshold for 1-bit conversion

    // MARK: - Image Processing

    /// Convert NSImage to VUDial 1-bit packed format
    /// - Parameter image: Source image
    /// - Returns: Packed image data (3600 bytes for 200×144 display) or nil on error
    static func convertImage(_ image: NSImage) -> Data? {
        print("🖼️ Converting image: \(image.size.width)x\(image.size.height)")

        // Resize to display dimensions
        guard let resized = resizeImage(image, width: displayWidth, height: displayHeight) else {
            print("❌ Failed to resize image")
            return nil
        }
        print("   Resized to: \(displayWidth)x\(displayHeight)")

        // Convert to grayscale bitmap
        guard let grayscaleBitmap = convertToGrayscale(resized) else {
            print("❌ Failed to convert to grayscale")
            return nil
        }
        print("   Grayscale pixels: \(grayscaleBitmap.count) (expected \(displayWidth * displayHeight) for \(displayWidth)×\(displayHeight))")

        // Apply threshold and pack into 1-bit format
        let packedData = packImageData(grayscaleBitmap)
        let expectedSize = displayHeight * (displayWidth / 8)
        print("   Packed data: \(packedData.count) bytes (expected \(expectedSize))")

        return packedData
    }

    // MARK: - Resizing

    /// Resize image to target dimensions (maintains aspect ratio, letterboxed)
    private static func resizeImage(_ image: NSImage, width: Int, height: Int) -> NSImage? {
        let targetSize = NSSize(width: width, height: height)
        let sourceSize = image.size

        // Calculate aspect-fit size
        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledSize = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        // Calculate centering offset
        let xOffset = (targetSize.width - scaledSize.width) / 2
        let yOffset = (targetSize.height - scaledSize.height) / 2

        // Create new image with black background
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Fill with black (will be letterbox background)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        // Draw resized image centered
        let drawRect = NSRect(
            x: xOffset,
            y: yOffset,
            width: scaledSize.width,
            height: scaledSize.height
        )
        image.draw(in: drawRect)

        newImage.unlockFocus()

        return newImage
    }

    // MARK: - Grayscale Conversion

    /// Convert image to grayscale bitmap
    private static func convertToGrayscale(_ image: NSImage) -> [UInt8]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        print("   CGImage dimensions: \(width)×\(height)")

        // Log dimensions
        if width != displayWidth || height != displayHeight {
            print("   ⚠️  WARNING: CGImage size \(width)×\(height) doesn't match display \(displayWidth)×\(displayHeight)!")
        }

        // Create grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // CRITICAL: CGContext has origin at bottom-left, but PIL/images have origin at top-left
        // Flip Y-axis to match PIL's coordinate system
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw image into grayscale context
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: rect)

        // Extract pixel data
        guard let data = context.data else {
            return nil
        }

        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        let pixels = Array(UnsafeBufferPointer(start: buffer, count: width * height))
        print("   Extracted \(pixels.count) pixels from CGContext")

        return pixels
    }

    // MARK: - Bit Packing

    /// Pack grayscale bitmap into vertical bit-packed format
    /// Display: 200×144 pixels
    /// Python transposes (200,144) array → (144,200)T = (200,144) in different order
    /// Then iterates 200 times, each with 144 pixels
    /// VUDial format: 8 vertical pixels per byte, column-major order
    /// Total: 200 columns × 18 bytes/column = 3,600 bytes
    ///
    /// IMPORTANT: Match Python's exact iteration:
    /// - Numpy array (144,200) transposed → iterate over 200 columns
    /// - Each column has 144 pixels = 18 bytes (144/8)
    private static func packImageData(_ grayscale: [UInt8]) -> Data {
        var packed = Data()
        // Match Python: 200 columns × 18 bytes each = 3,600 bytes
        packed.reserveCapacity(displayWidth * (displayHeight / 8))

        // Debug: Check first few pixels
        print("   First 10 pixels (row 0): \(grayscale.prefix(10).map { String($0) }.joined(separator: ", "))")
        if grayscale.count > displayWidth {
            let row1Start = displayWidth
            let row1End = min(row1Start + 10, grayscale.count)
            print("   Pixels \(row1Start)-\(row1End-1) (row 1): \((row1Start..<row1End).map { String(grayscale[$0]) }.joined(separator: ", "))")
        }

        // Python iterates 200 times (after transpose), each with 144 pixels
        // grayscale buffer is row-major: pixel(x,y) at index y*width+x
        for x in 0..<displayWidth {  // 0 to 199 (Python's 200 iterations)
            // Process 8 vertical pixels at a time (144 pixels = 18 bytes)
            // Pack from TOP to BOTTOM (Python packs y=0 to y=143)
            for yStart in stride(from: 0, to: displayHeight, by: 8) {  // 0, 8, 16, ..., 136
                var byte: UInt8 = 0

                // Pack 8 vertical pixels into one byte
                // Python: "".join(map(str, bits[i:i+8])) creates "bit0bit1bit2..."
                // Then int(..., 2) makes bit0 the MSB
                for bit in 0..<8 {
                    let y = yStart + bit
                    guard y < displayHeight else { break }

                    // Pixel at (x, y) in row-major buffer: y * width + x
                    let pixelIndex = y * displayWidth + x
                    let pixelValue = grayscale[pixelIndex]

                    // Debug first column's first byte
                    if x == 0 && yStart == 0 {
                        print("      Column 0, byte 0, bit \(bit): y=\(y), pixel[\(pixelIndex)]=\(pixelValue), result=\(pixelValue > threshold ? "white(1)" : "black(0)")")
                    }

                    // Threshold: >127 = white (1), ≤127 = black (0)
                    // Python makes first bit the MSB: bit 0 → position 7, bit 1 → position 6, etc.
                    if pixelValue > threshold {
                        byte |= (1 << (7 - bit))
                    }
                }

                packed.append(byte)
            }
        }

        let expectedSize = displayWidth * (displayHeight / 8)
        print("   Packed bytes: \(packed.count) (expected \(expectedSize) for \(displayWidth) columns × \(displayHeight/8) bytes/column)")
        print("   Packing structure: \(displayWidth) columns × \(displayHeight/8) bytes/column")
        print("   First 18 bytes (column 0): \(packed.prefix(18).map { String(format: "%02X", $0) }.joined(separator: " "))")
        if packed.count >= 36 {
            let column1Start = 18
            let column1Bytes = packed[column1Start..<(column1Start + 18)]
            print("   Bytes 18-35 (column 1): \(column1Bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        print("   Last 10 bytes: \(packed.suffix(10).map { String(format: "%02X", $0) }.joined(separator: " "))")

        return packed
    }

    // MARK: - Preview

    /// Create preview image from packed data (for debugging)
    static func unpackImage(_ packedData: Data) -> NSImage? {
        let expectedSize = displayWidth * (displayHeight / 8)
        guard packedData.count == expectedSize else {
            print("❌ Invalid packed data size: \(packedData.count), expected \(expectedSize)")
            return nil
        }

        var grayscale = [UInt8](repeating: 0, count: displayWidth * displayHeight)

        var dataIndex = 0
        for x in 0..<displayWidth {  // 200 columns
            // Unpack from TOP to BOTTOM (matching packing order)
            for yStart in stride(from: 0, to: displayHeight, by: 8) {  // 0, 8, 16, ..., 136
                let byte = packedData[dataIndex]
                dataIndex += 1

                for bit in 0..<8 {
                    let y = yStart + bit
                    guard y < displayHeight else { break }

                    let pixelIndex = y * displayWidth + x

                    // Unpack bit (MSB first, so use 7 - bit)
                    let isWhite = (byte & (1 << (7 - bit))) != 0
                    grayscale[pixelIndex] = isWhite ? 255 : 0
                }
            }
        }

        // Convert back to NSImage
        return createImageFromGrayscale(grayscale, width: displayWidth, height: displayHeight)
    }

    /// Create NSImage from grayscale pixel array
    private static func createImageFromGrayscale(_ pixels: [UInt8], width: Int, height: Int) -> NSImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        guard let data = context.data else {
            return nil
        }

        // Copy pixel data
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        for i in 0..<pixels.count {
            buffer[i] = pixels[i]
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        let size = NSSize(width: width, height: height)
        let image = NSImage(cgImage: cgImage, size: size)

        return image
    }
}
