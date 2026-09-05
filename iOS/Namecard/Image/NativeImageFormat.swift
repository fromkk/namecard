import Foundation

enum NativeImageFormatError: Error, LocalizedError {
    case invalidPixelCount
    case invalidByteCount(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPixelCount:
            return "ARGB ピクセル数がキャンバスと一致しません"
        case let .invalidByteCount(count):
            return "BIN は \(NativeImageFormat.byteCount) バイトである必要があります（現在 \(count)）"
        }
    }
}

/// Converts an ARGB canvas to SSD1680 native 1-bit display data and back.
///
/// Pixels are `0xAARRGGBB`, row-major, exactly as Android's `Color` ints. The
/// native result stores 16 bytes across the short axis for each of the 296
/// long-axis rows, MSB first, where 1 means white and 0 means black. This is
/// byte-compatible with the Android client's dot-density BIN format.
enum NativeImageFormat {
    static let width = 296
    static let height = 128
    static let byteCount = width * height / 8 // 4736

    private static let bayer4x4: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]

    /// Encodes a 296x128 ARGB image to native 1-bit data via 4x4 Bayer dither.
    static func encode(_ pixels: [UInt32]) throws -> [UInt8] {
        guard pixels.count == width * height else {
            throw NativeImageFormatError.invalidPixelCount
        }
        var native = [UInt8](repeating: 0xff, count: byteCount)
        for y in 0..<height {
            for x in 0..<width {
                let luminance = luminanceOnWhite(pixels[y * width + x])
                let threshold = bayer4x4[y & 3][x & 3] * 16 + 8
                if luminance < threshold {
                    clearNativeBit(&native, x: x, y: y)
                }
            }
        }
        return native
    }

    /// Decodes native 1-bit data back to ARGB pixels for previews.
    static func decode(_ image: [UInt8]) throws -> [UInt32] {
        guard image.count == byteCount else {
            throw NativeImageFormatError.invalidByteCount(image.count)
        }
        let white: UInt32 = 0xffff_ffff
        let black: UInt32 = 0xff00_0000
        var pixels = [UInt32](repeating: 0, count: width * height)
        for pixelIndex in 0..<(width * height) {
            let x = pixelIndex % width
            let y = pixelIndex / width
            let nativeIndex = x * (height / 8) + y / 8
            let mask = UInt8(0x80 >> (y & 7))
            pixels[pixelIndex] = (image[nativeIndex] & mask) != 0 ? white : black
        }
        return pixels
    }

    /// Composites a possibly translucent pixel onto white, then returns its
    /// perceptual luminance (0...255). Identical to the Android implementation.
    private static func luminanceOnWhite(_ color: UInt32) -> Int {
        let alpha = Int(color >> 24)
        let red = (Int((color >> 16) & 0xff) * alpha + 255 * (255 - alpha)) / 255
        let green = (Int((color >> 8) & 0xff) * alpha + 255 * (255 - alpha)) / 255
        let blue = (Int(color & 0xff) * alpha + 255 * (255 - alpha)) / 255
        return (299 * red + 587 * green + 114 * blue) / 1000
    }

    private static func clearNativeBit(_ image: inout [UInt8], x: Int, y: Int) {
        let index = x * (height / 8) + y / 8
        image[index] &= ~UInt8(0x80 >> (y & 7))
    }
}
