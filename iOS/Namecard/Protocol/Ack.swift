import Foundation

/// A decoded 32-byte firmware ACK/ERROR frame.
///
/// Layout matches `send_reply()` in `firmware/Core/Src/app.c`:
/// payload byte 0 echoes the request type, 1 is the ACK code, 2 the app state,
/// 3 the error, 4-5 expected sequence, 6-7 expected offset, 8-9 VDD, 10-11 the
/// minimum VDD seen, 12-13 the requested quiet time, 14 EH control, 15 caps.
struct Ack: Sendable {
    let code: Int
    let state: Int
    let error: Int
    let expectedSequence: Int
    let expectedOffset: Int
    let vddMv: Int
    let minimumVddMv: Int
    let quietMs: Int
    let capabilities: Int

    // Capability bits (payload[15]).
    var hasPendingImage: Bool { capabilities & 0x04 != 0 }
    var supportsBatchClean: Bool { capabilities & 0x08 != 0 }
    var batchCleanActive: Bool { capabilities & 0x10 != 0 }
    var supportsGray4: Bool { capabilities & 0x20 != 0 }
    var currentDisplayIsGray: Bool { capabilities & 0x40 != 0 }
    var hasGrayPlane0Pending: Bool { capabilities & 0x80 != 0 }

    /// Throws unless the firmware reported success (`code != ACK_ERROR` and no
    /// error code).
    func requireSuccess() throws {
        guard code != 0x80, error == 0 else {
            let named = NamecardFirmwareError(rawValue: error) ?? .none
            throw NamecardProtocolError.firmware(named, rawCode: error)
        }
    }

    static func decode(_ raw: [UInt8]) throws -> Ack {
        guard raw.count >= 32, raw[0] == 0x4E, raw[1] == 0x43 else {
            throw NamecardProtocolError.invalidAckFrame
        }
        var copy = raw
        let storedHeaderCRC = u16(copy, 12)
        copy[12] = 0
        copy[13] = 0
        let headerCheck = Array(copy[0..<12]) + Array(copy[14..<16])
        let payloadCRC = NamecardProtocol.crc16(Array(raw[16..<raw.count]))
        guard
            NamecardProtocol.crc16(headerCheck) == storedHeaderCRC,
            payloadCRC == u16(raw, 14)
        else {
            throw NamecardProtocolError.ackCRCMismatch
        }
        return Ack(
            code: Int(raw[17]),
            state: Int(raw[18]),
            error: Int(raw[19]),
            expectedSequence: u16(raw, 20),
            expectedOffset: u16(raw, 22),
            vddMv: u16(raw, 24),
            minimumVddMv: u16(raw, 26),
            quietMs: u16(raw, 28),
            capabilities: Int(raw[31])
        )
    }

    private static func u16(_ value: [UInt8], _ offset: Int) -> Int {
        Int(value[offset]) | (Int(value[offset + 1]) << 8)
    }
}
