import Testing
@testable import Namecard

struct NamecardProtocolTests {
    @Test func frameUsesLittleEndianHeaderAndValidCRC() throws {
        let payload: [UInt8] = [0x10, 0x20, 0x30]
        let frame = NamecardProtocol.frame(
            type: .data,
            transferId: 0x1234,
            sequence: 7,
            offset: 240,
            payload: payload
        )

        #expect(frame.count == 19)
        #expect(frame[0] == 0x4E) // 'N'
        #expect(frame[1] == 0x43) // 'C'
        #expect(frame[2] == 1)
        #expect(frame[3] == 2) // DATA
        #expect(le16(frame, 4) == 0x1234)
        #expect(le16(frame, 6) == 7)
        #expect(le16(frame, 8) == 240)
        #expect(le16(frame, 10) == UInt16(payload.count))
        #expect(Array(frame[16..<frame.count]) == payload)
        #expect(le16(frame, 14) == NamecardProtocol.crc16(payload))
    }

    @Test func crc16MatchesCCITTFalseCheckVector() {
        #expect(NamecardProtocol.crc16(Array("123456789".utf8)) == 0x29b1)
    }

    @Test func ackDecodeValidatesCRCAndCapabilities() throws {
        var raw = [UInt8](repeating: 0, count: 32)
        raw[0] = 0x4E // 'N'
        raw[1] = 0x43 // 'C'
        raw[2] = 1
        raw[3] = 0x81
        raw[10] = 16
        raw[17] = 0
        raw[18] = 6
        raw[20] = 3
        raw[22] = 0x80
        raw[23] = 0x12
        raw[24] = 0x80
        raw[25] = 0x0c
        raw[31] = 0x60

        let payloadCRC = NamecardProtocol.crc16(Array(raw[16..<32]))
        raw[14] = UInt8(payloadCRC & 0xff)
        raw[15] = UInt8(payloadCRC >> 8)
        let header = Array(raw[0..<12]) + Array(raw[14..<16])
        let headerCRC = NamecardProtocol.crc16(header)
        raw[12] = UInt8(headerCRC & 0xff)
        raw[13] = UInt8(headerCRC >> 8)

        let ack = try Ack.decode(raw)

        #expect(ack.state == 6)
        #expect(ack.expectedSequence == 3)
        #expect(ack.expectedOffset == 0x1280)
        #expect(ack.vddMv == 3_200)
        #expect(ack.supportsGray4)
        #expect(ack.currentDisplayIsGray)
    }

    private func le16(_ value: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(value[offset]) | (UInt16(value[offset + 1]) << 8)
    }
}
