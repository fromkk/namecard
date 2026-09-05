import Testing
import UIKit
@testable import Namecard

@MainActor
struct CanvasRendererTests {
    @Test func solidColorKeepsChannelOrder() throws {
        let red = solidImage(.red)
        let pixels = try #require(CanvasRenderer.canvasPixels(from: red))

        let center = pixels[(NativeImageFormat.height / 2) * NativeImageFormat.width + NativeImageFormat.width / 2]
        let a = (center >> 24) & 0xff
        let r = (center >> 16) & 0xff
        let g = (center >> 8) & 0xff
        let b = center & 0xff

        #expect(a == 0xff)
        #expect(r > 0xe0)
        #expect(g < 0x20)
        #expect(b < 0x20)
    }

    @Test func darkImageProducesNonWhiteNativeBytes() throws {
        let black = solidImage(.black)
        let pixels = try #require(CanvasRenderer.canvasPixels(from: black))
        let encoded = try NativeImageFormat.encode(pixels)
        // A black source must set (clear) plenty of bits, not stay all-white.
        #expect(encoded.contains { $0 != 0xff })
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
