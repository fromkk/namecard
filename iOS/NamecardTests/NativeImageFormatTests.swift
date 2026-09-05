import Testing
@testable import Namecard

struct NativeImageFormatTests {
    private let pixelCount = NativeImageFormat.width * NativeImageFormat.height

    @Test func solidWhiteAndBlackEncodeToNativeBits() throws {
        let white = [UInt32](repeating: 0xffff_ffff, count: pixelCount)
        let black = [UInt32](repeating: 0xff00_0000, count: pixelCount)

        #expect(try NativeImageFormat.encode(white).allSatisfy { $0 == 0xff })
        #expect(try NativeImageFormat.encode(black).allSatisfy { $0 == 0x00 })
    }

    @Test func nativeCoordinatesUseControllerOrder() throws {
        var pixels = [UInt32](repeating: 0xffff_ffff, count: pixelCount)
        pixels[0] = 0xff00_0000
        pixels[127 * NativeImageFormat.width + 295] = 0xff00_0000

        let encoded = try NativeImageFormat.encode(pixels)

        #expect(encoded.count == NativeImageFormat.byteCount)
        #expect(encoded[0] & 0x80 == 0)
        #expect(encoded[295 * 16 + 15] & 0x01 == 0)
    }

    @Test func nativeImagesDecodeForPreview() throws {
        let blackAndWhite = (0..<pixelCount).map { $0 % 2 == 0 ? UInt32(0xff00_0000) : UInt32(0xffff_ffff) }

        #expect(try NativeImageFormat.decode(NativeImageFormat.encode(blackAndWhite)) == blackAndWhite)
    }

    @Test func decodeRejectsWrongByteCount() {
        #expect(throws: NativeImageFormatError.self) {
            try NativeImageFormat.decode([UInt8](repeating: 0, count: NativeImageFormat.byteCount + 1))
        }
    }
}
