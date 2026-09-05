import Testing
@testable import Namecard

struct NativeImageFormatTests {
    private let pixelCount = NativeImageFormat.width * NativeImageFormat.height

    @Test func solidWhiteAndBlackEncodeToNativeBits() throws {
        let white = [UInt32](repeating: 0xffff_ffff, count: pixelCount)
        let black = [UInt32](repeating: 0xff00_0000, count: pixelCount)

        #expect(try NativeImageFormat.encodeDotDensity(white).allSatisfy { $0 == 0xff })
        #expect(try NativeImageFormat.encodeDotDensity(black).allSatisfy { $0 == 0x00 })
    }

    @Test func nativeCoordinatesUseControllerOrder() throws {
        var pixels = [UInt32](repeating: 0xffff_ffff, count: pixelCount)
        pixels[0] = 0xff00_0000
        pixels[127 * NativeImageFormat.width + 295] = 0xff00_0000

        let encoded = try NativeImageFormat.encodeDotDensity(pixels)

        #expect(encoded.count == NativeImageFormat.byteCount)
        #expect(encoded[0] & 0x80 == 0)
        #expect(encoded[295 * 16 + 15] & 0x01 == 0)
    }

    @Test func grayLevelsMapToTwoControllerPlanes() throws {
        let white = [UInt32](repeating: 0xffff_ffff, count: pixelCount)
        let black = [UInt32](repeating: 0xff00_0000, count: pixelCount)

        #expect(try NativeImageFormat.encodeGray4(white).allSatisfy { $0 == 0x00 })
        #expect(try NativeImageFormat.encodeGray4(black).allSatisfy { $0 == 0xff })

        var levels = white
        levels[0] = 0xff40_4040
        levels[1] = 0xff80_8080
        let gray = try NativeImageFormat.encodeGray4(levels)

        #expect(gray.count == NativeImageFormat.gray4ByteCount)
        #expect(gray[0] & 0x80 == 0)
        #expect(gray[NativeImageFormat.byteCount] & 0x80 != 0)
        #expect(gray[16] & 0x80 != 0)
        #expect(gray[NativeImageFormat.byteCount + 16] & 0x80 == 0)
    }

    @Test func nativeImagesDecodeForLibraryPreview() throws {
        let blackAndWhite = (0..<pixelCount).map { $0 % 2 == 0 ? UInt32(0xff00_0000) : UInt32(0xffff_ffff) }
        let shades: [UInt32] = [0xff00_0000, 0xff55_5555, 0xffaa_aaaa, 0xffff_ffff]
        let gray = (0..<pixelCount).map { shades[$0 % shades.count] }

        #expect(
            try NativeImageFormat.decode(
                NativeImageFormat.encodeDotDensity(blackAndWhite),
                format: .dotDensity
            ) == blackAndWhite
        )
        #expect(
            try NativeImageFormat.decode(
                NativeImageFormat.encodeGray4(gray),
                format: .gray4
            ) == gray
        )
    }

    @Test func binSizeDeterminesImportedFormat() throws {
        #expect(try NativeImageFormat.format(forByteCount: NativeImageFormat.byteCount) == .dotDensity)
        #expect(try NativeImageFormat.format(forByteCount: NativeImageFormat.gray4ByteCount) == .gray4)
    }
}
