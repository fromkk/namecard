import CoreGraphics
import UIKit

/// Rasterises source images onto the fixed 296x128 namecard canvas and reads
/// them back as ARGB pixels for `NativeImageFormat`.
///
/// Pixels are packed as `0xAARRGGBB` to match Android's `Color` ints. To stay
/// free of byte-order surprises, the CoreGraphics buffer is always treated as a
/// plain RGBA byte stream (`premultipliedLast`) and packed/unpacked by hand.
enum CanvasRenderer {
    static let width = NativeImageFormat.width
    static let height = NativeImageFormat.height

    /// Draws `image` aspect-fit, centered, on a white background, then returns
    /// the canvas as `0xAARRGGBB` pixels (row-major, fully opaque).
    static func canvasPixels(from image: UIImage) -> [UInt32]? {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: aspectFitRect(for: image.size, in: size))
        }
        guard let cgImage = rendered.cgImage else { return nil }
        return pixels(from: cgImage)
    }

    /// Reads any CGImage into `0xAARRGGBB` pixels through a known RGBA context.
    static func pixels(from cgImage: CGImage) -> [UInt32]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue // RGBA, byte order
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var pixels = [UInt32](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let r = UInt32(bytes[base])
            let g = UInt32(bytes[base + 1])
            let b = UInt32(bytes[base + 2])
            let a = UInt32(bytes[base + 3])
            pixels[index] = (a << 24) | (r << 16) | (g << 8) | b
        }
        return pixels
    }

    /// Builds a `UIImage` preview from decoded native pixels, for previews and
    /// library thumbnails.
    static func image(fromCanvasPixels pixels: [UInt32]) -> UIImage? {
        guard pixels.count == width * height else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<pixels.count {
            let color = pixels[index]
            let base = index * 4
            bytes[base] = UInt8((color >> 16) & 0xff)     // R
            bytes[base + 1] = UInt8((color >> 8) & 0xff)  // G
            bytes[base + 2] = UInt8(color & 0xff)         // B
            bytes[base + 3] = UInt8((color >> 24) & 0xff) // A
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let cgImage: CGImage? = bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return nil }
            return context.makeImage()
        }
        return cgImage.map { UIImage(cgImage: $0) }
    }

    private static func aspectFitRect(for imageSize: CGSize, in target: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: target)
        }
        let scale = min(target.width / imageSize.width, target.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (target.width - scaled.width) / 2,
            y: (target.height - scaled.height) / 2,
            width: scaled.width,
            height: scaled.height
        )
    }
}
