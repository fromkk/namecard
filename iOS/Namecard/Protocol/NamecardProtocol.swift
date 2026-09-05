import Foundation

/// Frame types exchanged with the namecard firmware. Values match
/// `nc_frame_type_t` in `firmware/Core/Inc/nc_protocol.h`.
enum NamecardFrameType: UInt8 {
    case start = 0x01
    case data = 0x02
    case commit = 0x03
    case status = 0x04
    case execute = 0x05
    case pattern = 0x06
    case ndefWritePrepare = 0x07
    case ack = 0x80
    case error = 0x81
}

/// Firmware error codes (`nc_error_t`). Only the ones the client reacts to are
/// named; the rest fall through to `.protocolError`.
enum NamecardFirmwareError: Int {
    case none = 0
    case command = 6
    case transferId = 7
    case sequence = 8
    case offset = 9
    case notCommitted = 13
    case vddTimeout = 14
    case vddDroop = 15
    case epdTimeout = 16
    case epdIO = 17
    case nfcIO = 18
    case executeAckTimeout = 19
    case hardwareGate = 20
    case flashStore = 21

    var localizedName: String {
        switch self {
        case .none: return "なし"
        case .command: return "未対応コマンド"
        case .transferId: return "転送ID不一致"
        case .sequence: return "シーケンス不一致"
        case .offset: return "オフセット不一致"
        case .notCommitted: return "未COMMIT/保存不一致"
        case .vddTimeout: return "VDD充電タイムアウト"
        case .vddDroop: return "VDD低下"
        case .epdTimeout: return "EPD BUSYタイムアウト"
        case .epdIO: return "EPD I/O"
        case .nfcIO: return "STM32-ST25 I2C/Mailbox I/O"
        case .executeAckTimeout: return "EXECUTE ACKタイムアウト"
        case .hardwareGate: return "ハードウェアゲート"
        case .flashStore: return "表示Flash保存エラー"
        }
    }
}

enum NamecardProtocolError: Error, LocalizedError {
    case invalidAckFrame
    case ackCRCMismatch
    case firmware(NamecardFirmwareError, rawCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidAckFrame: return "ACKフレームが不正です"
        case .ackCRCMismatch: return "ACKのCRCが一致しません"
        case let .firmware(error, rawCode):
            return "FWエラー: \(error.localizedName)（code=\(rawCode)）"
        }
    }
}

/// Builds namecard protocol frames and computes the CRCs the firmware expects.
///
/// The 16-byte header is little-endian:
///
/// | off | size | field                    |
/// | --: | ---: | ------------------------ |
/// |   0 |    2 | Magic `NC`               |
/// |   2 |    1 | Version (1)              |
/// |   3 |    1 | Type                     |
/// |   4 |    2 | Transfer ID              |
/// |   6 |    2 | Sequence                 |
/// |   8 |    2 | Offset                   |
/// |  10 |    2 | Payload length           |
/// |  12 |    2 | Header CRC16 (excl. 12-13) |
/// |  14 |    2 | Payload CRC16            |
enum NamecardProtocol {
    static func frame(
        type: NamecardFrameType,
        transferId: UInt16,
        sequence: UInt16,
        offset: UInt16,
        payload: [UInt8]
    ) -> [UInt8] {
        var raw = [UInt8]()
        raw.reserveCapacity(16 + payload.count)
        raw.append(0x4E) // 'N'
        raw.append(0x43) // 'C'
        raw.append(1)
        raw.append(type.rawValue)
        appendLE16(&raw, transferId)
        appendLE16(&raw, sequence)
        appendLE16(&raw, offset)
        appendLE16(&raw, UInt16(payload.count))
        appendLE16(&raw, 0) // header CRC placeholder
        appendLE16(&raw, crc16(payload))
        raw.append(contentsOf: payload)

        let headerCRCInput = Array(raw[0..<12]) + Array(raw[14..<16])
        let headerCRC = crc16(headerCRCInput)
        raw[12] = UInt8(headerCRC & 0xff)
        raw[13] = UInt8(headerCRC >> 8)
        return raw
    }

    /// CRC-16/CCITT-FALSE: init `0xFFFF`, polynomial `0x1021`, no reflection.
    static func crc16(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}

func appendLE16(_ buffer: inout [UInt8], _ value: UInt16) {
    buffer.append(UInt8(value & 0xff))
    buffer.append(UInt8(value >> 8))
}
