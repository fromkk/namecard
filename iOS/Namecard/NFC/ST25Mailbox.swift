import CoreNFC
import Foundation

enum ST25MailboxError: Error, LocalizedError {
    case vccNotReady(ehControl: Int)
    case mailboxEnableFailed(mbControl: Int)
    case ackTimeout
    case ackLengthMismatch(Int)
    case mailboxBusy
    case command(code: Int, paramCount: Int, underlying: String)

    var errorDescription: String? {
        switch self {
        case let .vccNotReady(ehControl):
            return "ST25のVCCが立ち上がっていません。端末のNFCアンテナへ近づけて固定してください（EH_CTRL=\(String(format: "%02X", ehControl))）"
        case let .mailboxEnableFailed(mbControl):
            return "MB_ENを有効化できませんでした（MB_CTRL=\(String(format: "%02X", mbControl))）"
        case .ackTimeout:
            return "MCUからのACKがタイムアウトしました"
        case let .ackLengthMismatch(size):
            return "ACK長が不正です（\(size)）"
        case .mailboxBusy:
            return "Mailboxがビジー状態です"
        case let .command(code, paramCount, underlying):
            return String(format: "STコマンド 0x%02X（%dバイト）失敗: %@", code, paramCount, underlying)
        }
    }
}

/// Drives the ST25DV FTM mailbox exactly as the Android `St25Mailbox` does,
/// using Core NFC custom commands instead of raw `NfcV.transceive`.
///
/// Core NFC assembles the ISO 15693 flags, command code and ST manufacturer
/// code itself, so `customRequestParameters` carries only the ST-specific
/// bytes (unlike Android's raw frame which prepends UID and manufacturer code).
nonisolated final class ST25Mailbox {
    private let tag: NFCISO15693Tag
    // Core NFC only supports non-addressed custom commands for the ST25DV
    // (flag 0x02 = high data rate); it inserts the ST manufacturer code and
    // addresses the connected tag itself. Setting `.address` here makes nfcd
    // reject the request with "Invalid Parameter".
    private let flags: NFCISO15693RequestFlag = [.highDataRate]

    init(tag: NFCISO15693Tag) {
        self.tag = tag
    }

    // MARK: - Mailbox lifecycle

    func enable() async throws {
        let deadline = Date().addingTimeInterval(Double(Constants.enableTimeoutMs) / 1000)
        var lastEH = -1
        var lastMB = -1

        while Date() < deadline {
            // RF discovery only needs the passive tag, but FTM needs harvested
            // SYS_VDD present on ST25 VCC. Poll slowly and stay quiet so VRES
            // can charge.
            if let eh = try? await readDynamic(0x02) {
                lastEH = Int(eh)
                if Int(eh) & Constants.ehVccOn == 0 {
                    try await quietDelay()
                    continue
                }
            }

            if let control = try? await readControl() {
                lastMB = Int(control)
                if Int(control) & Constants.mbEnable != 0 { return }
                _ = try? await command(0xAE, [0x0D, UInt8(Constants.mbEnable)])
                try await Task.sleep(for: .milliseconds(Constants.enableVerifyDelayMs))
                if let verify = try? await readControl() {
                    lastMB = Int(verify)
                    if Int(verify) & Constants.mbEnable != 0 { return }
                }
            }
            try await quietDelay()
        }

        if lastEH >= 0, lastEH & Constants.ehVccOn == 0 {
            throw ST25MailboxError.vccNotReady(ehControl: lastEH)
        }
        throw ST25MailboxError.mailboxEnableFailed(mbControl: lastMB)
    }

    func disable() async throws {
        guard let control = try? await readControl() else { return }
        if Int(control) & 0x01 == 0 { return }
        _ = try await command(0xAE, [0x0D, 0x00])
    }

    // MARK: - Frame exchange

    /// Writes a namecard frame into the mailbox and reads the 32-byte ACK.
    func exchange(_ message: [UInt8], ackTimeoutMs: Int = 1_500) async throws -> Ack {
        try await waitMailboxFree(timeoutMs: 1_000)
        var write = [UInt8]()
        write.append(UInt8(message.count - 1))
        write.append(contentsOf: message)
        _ = try await command(0xAA, write)

        // Avoid hammering MB_CTRL_Dyn while EH and the MCU's I2C are active.
        try await Task.sleep(for: .milliseconds(Constants.ackSettleMs))
        let deadline = Date().addingTimeInterval(Double(ackTimeoutMs) / 1000)
        var lastError: Error?
        while Date() < deadline {
            // Right after the RF write the MCU grabs the mailbox over I2C, so an
            // RF read can transiently NAK ("Tag response error"). Keep polling
            // until the ACK appears or the timeout elapses instead of aborting.
            do {
                let control = try await readControl()
                if Int(control) & 0x02 != 0 {
                    return try Ack.decode(try await readHostMessage())
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(for: .milliseconds(Constants.ackPollMs))
        }
        throw lastError ?? ST25MailboxError.ackTimeout
    }

    // MARK: - Low-level primitives

    private func waitMailboxFree(timeoutMs: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            // Tolerate transient RF NAKs while the MCU is still using the mailbox.
            if let raw = try? await readControl() {
                let control = Int(raw)
                if control & 0x06 == 0 { return }
                if control & 0x02 != 0 { _ = try? await readHostMessage() }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        // Best effort: if the mailbox never reported free, proceed anyway rather
        // than aborting the whole transfer. The following 0xAA write overwrites
        // the RF-to-host slot, and a genuine failure surfaces on that command.
    }

    private func readControl() async throws -> UInt8 { try await readDynamic(0x0D) }

    private func readDynamic(_ address: UInt8) async throws -> UInt8 {
        let response = try await command(0xAD, [address])
        guard let first = response.first else { throw ST25MailboxError.ackLengthMismatch(0) }
        return first
    }

    private func readHostMessage() async throws -> [UInt8] {
        let answer = try await command(0xAC, [0, UInt8(Constants.ackFrameSize - 1)])
        guard answer.count == Constants.ackFrameSize else {
            throw ST25MailboxError.ackLengthMismatch(answer.count)
        }
        return answer
    }

    @discardableResult
    private func command(_ code: Int, _ parameters: [UInt8]) async throws -> [UInt8] {
        do {
            let response = try await tag.customCommand(
                requestFlags: flags,
                customCommandCode: code,
                customRequestParameters: Data(parameters)
            )
            return [UInt8](response)
        } catch {
            throw ST25MailboxError.command(
                code: code,
                paramCount: parameters.count,
                underlying: (error as NSError).localizedDescription
            )
        }
    }

    private func quietDelay() async throws {
        try await Task.sleep(for: .milliseconds(Constants.enableRetryQuietMs))
    }

    private enum Constants {
        static let mbEnable = 0x01
        static let ehVccOn = 0x08
        static let enableTimeoutMs = 8_000
        static let enableRetryQuietMs = 1_000
        static let enableVerifyDelayMs = 25
        static let ackFrameSize = 32
        static let ackSettleMs = 50
        static let ackPollMs = 15
    }
}
