import Foundation

enum NamecardTransferError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return nil
    }
}

/// CRC-32/IEEE used to validate the whole image, matching `java.util.zip.CRC32`.
enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
            return crc
        }
    }()

    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in bytes {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xffff_ffff
    }
}

/// Holds progress for one 1-bit image so a dropped NFC session can be resumed on
/// the next tap, mirroring the dot-density path of the Android client.
nonisolated final class ImageTransferSession {
    static let imageSize = NativeImageFormat.byteCount // 4736
    static let cleanPatternIds = [4, 3, 4]

    let image: [UInt8]
    let transferId: UInt16
    let cleanBeforeWrite: Bool

    var maxChunk = 0
    var sequence = 0
    var offset = 0
    var cleanStep = cleanPatternIds.count
    var started = false
    var committed = false
    var executeSent = false
    var recoveryChecked = false
    var cleanRequested: Bool
    var batchClean = false

    init(image: [UInt8], cleanBeforeWrite: Bool) {
        self.image = image
        self.transferId = UInt16(UInt64(Date().timeIntervalSince1970 * 1000) & 0xffff)
        self.cleanBeforeWrite = cleanBeforeWrite
        self.cleanRequested = cleanBeforeWrite
    }

    func metadata() -> [UInt8] {
        let crc = CRC32.checksum(image[0..<Self.imageSize])
        var payload = [UInt8]()
        appendLE16(&payload, UInt16(NativeImageFormat.width))
        appendLE16(&payload, UInt16(NativeImageFormat.height))
        appendLE16(&payload, UInt16(Self.imageSize))
        payload.append(1) // format: native 1bpp
        payload.append(1) // single plane
        appendLE32(&payload, crc)
        appendLE32(&payload, batchClean ? 1 : 0)
        return payload
    }

    var cleanComplete: Bool { cleanStep >= Self.cleanPatternIds.count }

    func requireClean() { cleanStep = 0 }
    func requestClean() { cleanRequested = true }

    func prepareCleaning(batchSupported: Bool) {
        guard cleanRequested else { return }
        if batchSupported { batchClean = true } else { requireClean() }
    }

    func reset() {
        sequence = 0
        offset = 0
        started = false
        committed = false
        executeSent = false
    }

    private func appendLE32(_ buffer: inout [UInt8], _ value: UInt32) {
        buffer.append(UInt8(value & 0xff))
        buffer.append(UInt8((value >> 8) & 0xff))
        buffer.append(UInt8((value >> 16) & 0xff))
        buffer.append(UInt8((value >> 24) & 0xff))
    }
}

/// Progress reported during a transfer.
struct TransferProgress: Sendable {
    var fraction: Double
    var status: String
}

/// The namecard transfer state machine for 1-bit (dot-density) images. Ported
/// from the Android `MainActivity.transfer` flow, driving a connected mailbox.
nonisolated struct NamecardTransfer {
    let onLog: @Sendable (String) -> Void
    let onProgress: @Sendable (TransferProgress) -> Void

    // MARK: - STATUS

    @discardableResult
    func status(_ mailbox: ST25Mailbox) async throws -> Ack {
        let ack = try await mailbox.exchange(
            NamecardProtocol.frame(type: .status, transferId: 0, sequence: 0, offset: 0, payload: [])
        )
        try ack.requireSuccess()
        onLog("STATUS OK: state=\(ack.state) VDD=\(ack.vddMv)mV min=\(ack.minimumVddMv)mV error=\(ack.error)")
        return ack
    }

    // MARK: - PATTERN

    func pattern(_ mailbox: ST25Mailbox, id: Int) async throws {
        let transferId = UInt16((Int(Date().timeIntervalSince1970 * 1000) + id) & 0xffff)
        var ack = try await mailbox.exchange(
            NamecardProtocol.frame(type: .pattern, transferId: transferId, sequence: 0, offset: 0, payload: [UInt8(id)])
        )
        try ack.requireSuccess()
        onLog("PATTERN \(id) ACK: VDD=\(ack.vddMv)mV。VRESを充電します。")

        try await sleep(Constants.chargeQuietMs)
        repeat {
            ack = try await statusFrame(mailbox, transferId, sequence: 1)
            try ack.requireSuccess()
            onLog("充電: state=\(ack.state) VDD=\(ack.vddMv)mV min=\(ack.minimumVddMv)mV")
            if ack.state != 3 { try await sleep(1_000) }
        } while ack.state != 3

        ack = try await mailbox.exchange(frame(.execute, transferId, sequence: 1))
        try ack.requireSuccess()
        var sequence = ack.expectedSequence
        let firmwareBatch = ack.batchCleanActive
        var complete: Ack
        while true {
            let quiet = max(firmwareBatch ? 1_000 : 2_000, ack.quietMs)
            onLog("EXECUTE ACK。\(quiet)ms、RF通信を停止します。")
            try await sleep(quiet + 250)
            complete = try await statusFrame(
                mailbox, transferId, sequence: sequence,
                timeoutMs: firmwareBatch ? Constants.batchStatusTimeoutMs : 1_500
            )
            try complete.requireSuccess()
            if complete.state == 6 { break }
            guard firmwareBatch else {
                throw NamecardTransferError.message("PATTERN \(id) 更新後 state=\(complete.state)")
            }
            if complete.state == 3 {
                sequence = complete.expectedSequence
                ack = try await mailbox.exchange(frame(.execute, transferId, sequence: sequence))
                try ack.requireSuccess()
                sequence = ack.expectedSequence
            } else {
                try await sleep(1_000)
            }
        }
        onLog("PATTERN \(id) 完了: VDD=\(complete.vddMv)mV, 更新中min=\(complete.minimumVddMv)mV")
    }

    // MARK: - Image transfer

    func image(_ mailbox: ST25Mailbox, session: ImageTransferSession) async throws {
        let transferId = session.transferId

        onProgress(TransferProgress(fraction: 0.10, status: "中断状態を確認しています"))
        let recovery = try await status(mailbox)
        if session.executeSent, recovery.state == 6 {
            onLog("前回の表示更新完了を確認しました。")
            onProgress(TransferProgress(fraction: 1.0, status: "表示更新完了を確認しました"))
            return
        }
        applyRecovery(recovery, to: session)

        if !session.cleanComplete {
            onProgress(TransferProgress(fraction: 0.12, status: "画面をクリーニング中"))
            try await runCleanSequence(mailbox, session: session)
        }

        session.maxChunk = Constants.maxDataChunk
        onProgress(TransferProgress(
            fraction: imageFraction(session.offset, of: session.image.count),
            status: "画像データを送信中"
        ))

        var complete: Ack?
        while true {
            if session.started {
                onLog("進捗から再開: \(session.offset) / \(session.image.count) bytes（seq=\(session.sequence)）")
            }
            while !session.committed {
                if !session.started {
                    let ack = try await mailbox.exchange(
                        NamecardProtocol.frame(
                            type: .start, transferId: transferId, sequence: 0, offset: 0,
                            payload: session.metadata()
                        )
                    )
                    try ack.requireSuccess()
                    session.started = true
                    session.sequence = ack.expectedSequence
                    session.offset = ack.expectedOffset
                    onLog("画像 START ACK。")
                    try await sleep(frameGapMs(ack.vddMv))
                    continue
                }

                if session.offset < ImageTransferSession.imageSize {
                    let offset = session.offset
                    let end = min(offset + session.maxChunk, ImageTransferSession.imageSize)
                    let chunk = Array(session.image[offset..<end])
                    if offset == 0 {
                        onLog("DATA送信開始（chunk=\(session.maxChunk), frame=\(16 + chunk.count)B）")
                    }
                    let ack = try await mailbox.exchange(
                        NamecardProtocol.frame(
                            type: .data, transferId: transferId,
                            sequence: UInt16(session.sequence), offset: UInt16(offset), payload: chunk
                        )
                    )
                    if ack.error == 7 {
                        session.reset()
                        onLog("MCU再起動を検出。先頭から自動再送します。")
                        continue
                    }
                    if (ack.error == 8 || ack.error == 9), (0...ImageTransferSession.imageSize).contains(ack.expectedOffset) {
                        session.sequence = ack.expectedSequence
                        session.offset = ack.expectedOffset
                        onLog("FWの期待位置へ再同期しました。")
                        continue
                    }
                    try ack.requireSuccess()
                    session.sequence = ack.expectedSequence
                    session.offset = ack.expectedOffset
                    onProgress(TransferProgress(
                        fraction: imageFraction(session.offset, of: session.image.count),
                        status: "画像データを送信中 VDD=\(ack.vddMv)mV"
                    ))
                    if session.offset < ImageTransferSession.imageSize {
                        try await sleep(frameGapMs(ack.vddMv))
                    }
                    continue
                }

                let ack = try await mailbox.exchange(
                    NamecardProtocol.frame(
                        type: .commit, transferId: transferId,
                        sequence: UInt16(session.sequence), offset: UInt16(ImageTransferSession.imageSize), payload: []
                    )
                )
                if ack.error == 7 {
                    session.reset()
                    continue
                }
                try ack.requireSuccess()
                session.sequence = ack.expectedSequence
                session.offset = ack.expectedOffset
                session.committed = true
                onProgress(TransferProgress(fraction: 0.73, status: "データ転送を確認しました"))
            }

            var sequence = session.sequence
            var firstChargeWait = true

            // Charge until the firmware is READY(3) to refresh, then EXECUTE.
            var ready: Ack
            repeat {
                if firstChargeWait {
                    onLog("VRES充電のためRF通信を1.5秒停止します。位置を固定してください。")
                    try await sleep(Constants.chargeQuietMs)
                    firstChargeWait = false
                }
                ready = try await statusFrame(mailbox, transferId, sequence: sequence, offset: ImageTransferSession.imageSize)
                try ready.requireSuccess()
                onLog("充電: state=\(ready.state) VDD=\(ready.vddMv)mV min=\(ready.minimumVddMv)mV")
                if ready.state == 6 { complete = ready; break }
                if ready.state == 1 {
                    session.reset()
                    throw NamecardTransferError.message("MCUが電源断しました。先頭から再送します")
                }
                if ready.state != 3 { try await sleep(1_000) }
            } while ready.state != 3
            if complete?.state == 6 { break }

            sequence = ready.expectedSequence
            var ack = try await mailbox.exchange(frame(.execute, transferId, sequence: sequence, offset: ImageTransferSession.imageSize))
            try ack.requireSuccess()
            sequence = ack.expectedSequence
            session.sequence = sequence
            session.executeSent = true
            if ack.batchCleanActive { session.batchClean = true }
            onLog("EXECUTE ACK。表示を更新します。")
            onProgress(TransferProgress(fraction: 0.80, status: "e-paperを更新中"))
            // The firmware starts the refresh shortly after it sees this ACK read
            // and ignores the mailbox while REFRESHING, so our STATUS reads simply
            // time out until the update finishes. Wait briefly, then poll
            // tolerantly: a read timeout means "still updating", not failure.
            try await sleep(Constants.executeSettleMs)

            let updateDeadline = Date().addingTimeInterval(Double(Constants.updateDeadlineMs) / 1000)
            while Date() < updateDeadline {
                let progress: Ack
                do {
                    progress = try await statusFrame(
                        mailbox, transferId, sequence: sequence, offset: ImageTransferSession.imageSize, timeoutMs: 1_500
                    )
                } catch {
                    onProgress(TransferProgress(fraction: 0.92, status: "e-paperを更新中"))
                    try await sleep(Constants.updatePollGapMs)
                    continue
                }
                if progress.state == 6 {
                    complete = progress
                    onProgress(TransferProgress(fraction: 0.98, status: "表示更新を確認しました"))
                    break
                }
                try progress.requireSuccess()
                if progress.state == 1 {
                    session.reset()
                    session.executeSent = false
                    throw NamecardTransferError.message("更新中に電源断しました。先頭から再送します")
                }
                // States 2/3/5: charging between clean phases. The firmware
                // advances itself once VRES recharges, so keep polling gently.
                sequence = progress.expectedSequence
                onProgress(TransferProgress(fraction: 0.92, status: "e-paperを更新中"))
                try await sleep(Constants.updatePollGapMs)
            }
            guard complete?.state == 6 else {
                throw NamecardTransferError.message("表示更新の完了を確認できませんでした。もう一度名刺にタッチしてください")
            }
            break
        }

        guard let finished = complete else {
            throw NamecardTransferError.message("転送を完了できませんでした")
        }
        onLog("完了: VDD=\(finished.vddMv)mV, 更新中min=\(finished.minimumVddMv)mV")
        onProgress(TransferProgress(fraction: 1.0, status: "画像の書き込みが完了しました"))
    }

    // MARK: - Helpers

    private func applyRecovery(_ recovery: Ack, to session: ImageTransferSession) {
        guard !session.recoveryChecked else { return }
        if recovery.hasPendingImage || recovery.state == 7 {
            session.requestClean()
            onLog("前回の中断状態を検出。クリーニングを自動追加します。")
        }
        session.prepareCleaning(batchSupported: recovery.supportsBatchClean)
        session.recoveryChecked = true
    }

    private func runCleanSequence(_ mailbox: ST25Mailbox, session: ImageTransferSession) async throws {
        while !session.cleanComplete {
            let step = session.cleanStep
            onLog("画面クリーニング \(step + 1)/\(ImageTransferSession.cleanPatternIds.count)。位置を固定してください。")
            try await pattern(mailbox, id: ImageTransferSession.cleanPatternIds[step])
            session.cleanStep = step + 1
        }
        onLog("画面を白へリセットしました。本画像の転送を開始します。")
    }

    private func statusFrame(_ mailbox: ST25Mailbox, _ transferId: UInt16, sequence: Int, offset: Int = 0, timeoutMs: Int = 1_500) async throws -> Ack {
        try await mailbox.exchange(
            NamecardProtocol.frame(
                type: .status, transferId: transferId,
                sequence: UInt16(truncatingIfNeeded: sequence), offset: UInt16(offset), payload: []
            ),
            ackTimeoutMs: timeoutMs
        )
    }

    private func frame(_ type: NamecardFrameType, _ transferId: UInt16, sequence: Int, offset: Int = 0) -> [UInt8] {
        NamecardProtocol.frame(
            type: type, transferId: transferId,
            sequence: UInt16(truncatingIfNeeded: sequence), offset: UInt16(offset), payload: []
        )
    }

    private func imageFraction(_ transferred: Int, of total: Int) -> Double {
        guard total > 0 else { return 0.15 }
        let ratio = Double(min(max(transferred, 0), total)) / Double(total)
        return 0.15 + ratio * (0.72 - 0.15)
    }

    private func frameGapMs(_ vddMv: Int) -> Int {
        switch vddMv {
        case 3_200...: return 50
        case 3_050...: return 200
        default: return 500
        }
    }

    private func sleep(_ ms: Int) async throws {
        try await Task.sleep(for: .milliseconds(ms))
    }

    private enum Constants {
        static let chargeQuietMs = 1_500
        static let batchStatusTimeoutMs = 3_500
        /// Firmware CLIENT_RF_QUIET_MS is 2000; wait a touch longer before the
        /// first post-EXECUTE STATUS so a single refresh has finished.
        static let executeSettleMs = 2_250
        /// Poll for display completion up to this long, staying under the iOS
        /// ~60 s reader-session limit.
        static let updateDeadlineMs = 45_000
        static let updatePollGapMs = 800
        /// Core NFC caps the ISO 15693 custom-command frame near 255 bytes
        /// (a 240-byte payload → 257-byte 0xAA request throws "Packet length
        /// has exceeded the limit"). 128 bytes (145-byte request) is well inside.
        static let maxDataChunk = 128
    }
}
