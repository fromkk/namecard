import Foundation

/// Image formats understood by the namecard firmware (SSD1680 controller).
///
/// Mirrors the Android `NativeImageFormat` constants so BIN files are byte
/// compatible between the two clients and the firmware.
enum NamecardImageFormat: Int, CaseIterable, Sendable {
    case dotDensity = 1
    case gray4 = 2

    var byteCount: Int {
        switch self {
        case .dotDensity: return NativeImageFormat.byteCount
        case .gray4: return NativeImageFormat.gray4ByteCount
        }
    }

    var displayName: String {
        switch self {
        case .dotDensity: return "ドット密度"
        case .gray4: return "4階調"
        }
    }
}

enum NativeImageFormatError: Error, LocalizedError {
    case invalidCanvasSize(width: Int, height: Int)
    case invalidPixelCount
    case invalidByteCount(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidCanvasSize(width, height):
            return "キャンバスは \(NativeImageFormat.width)x\(NativeImageFormat.height) である必要があります（現在 \(width)x\(height)）"
        case .invalidPixelCount:
            return "ARGB ピクセル数がキャンバスと一致しません"
        case let .invalidByteCount(count):
            return "BIN は \(NativeImageFormat.byteCount) または \(NativeImageFormat.gray4ByteCount) バイトである必要があります（現在 \(count)）"
        }
    }
}

/// Converts an ARGB canvas to SSD1680 native display data and back.
///
/// Pixels are `0xAARRGGBB`, row-major, exactly as Android's `Color` ints.
/// The native result stores 16 bytes across the short axis for each of the
/// 296 long-axis rows, MSB first, where 1 means white and 0 means black.
enum NativeImageFormat {
    static let width = 296
    static let height = 128
    static let byteCount = width * height / 8
    static let gray4ByteCount = byteCount * 2

    private static let bayer4x4: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]

    // MARK: - Encoding

    static func encode(_ pixels: [UInt32], format: NamecardImageFormat) throws -> [UInt8] {
        switch format {
        case .dotDensity: return try encodeDotDensity(pixels)
        case .gray4: return try encodeGray4(pixels)
        }
    }

    static func encodeDotDensity(_ pixels: [UInt32]) throws -> [UInt8] {
        try validate(pixels)
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

    static func encodeGray4(_ pixels: [UInt32]) throws -> [UInt8] {
        try validate(pixels)
        var native = [UInt8](repeating: 0, count: gray4ByteCount)
        for y in 0..<height {
            for x in 0..<width {
                let grayCode = min(3, luminanceOnWhite(pixels[y * width + x]) / 64)
                let index = x * (height / 8) + y / 8
                let mask = UInt8(0x80 >> (y & 7))
                if grayCode & 0x01 == 0 {
                    native[index] |= mask
                }
                if grayCode & 0x02 == 0 {
                    native[byteCount + index] |= mask
                }
            }
        }
        return native
    }

    // MARK: - Decoding (for previews)

    static func decode(_ image: [UInt8], format: NamecardImageFormat) throws -> [UInt32] {
        guard image.count == format.byteCount else {
            throw NativeImageFormatError.invalidByteCount(image.count)
        }
        let shades: [UInt32] = [0xff00_0000, 0xff55_5555, 0xffaa_aaaa, 0xffff_ffff]
        var pixels = [UInt32](repeating: 0, count: width * height)
        for pixelIndex in 0..<(width * height) {
            let x = pixelIndex % width
            let y = pixelIndex / width
            let nativeIndex = x * (height / 8) + y / 8
            let mask = UInt8(0x80 >> (y & 7))
            switch format {
            case .dotDensity:
                pixels[pixelIndex] = (image[nativeIndex] & mask) != 0 ? shades[3] : shades[0]
            case .gray4:
                let low = (image[nativeIndex] & mask) != 0 ? 0 : 1
                let high = (image[byteCount + nativeIndex] & mask) != 0 ? 0 : 2
                pixels[pixelIndex] = shades[low + high]
            }
        }
        return pixels
    }

    // MARK: - Format helpers

    static func format(forByteCount count: Int) throws -> NamecardImageFormat {
        switch count {
        case byteCount: return .dotDensity
        case gray4ByteCount: return .gray4
        default: throw NativeImageFormatError.invalidByteCount(count)
        }
    }

    // MARK: - Private

    private static func validate(_ pixels: [UInt32]) throws {
        guard pixels.count == width * height else {
            throw NativeImageFormatError.invalidPixelCount
        }
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
