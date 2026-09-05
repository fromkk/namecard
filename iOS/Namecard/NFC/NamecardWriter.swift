import CoreNFC
import Foundation

enum NamecardWriterError: Error, LocalizedError {
    case nfcNotAvailable
    case sessionUnavailable
    case notISO15693
    case invalidURL
    case ndefUnsupported
    case ndefNotWritable
    case ndefVerifyFailed

    var errorDescription: String? {
        switch self {
        case .nfcNotAvailable: return "この端末ではNFCを利用できません"
        case .sessionUnavailable: return "NFCセッションを開始できませんでした"
        case .notISO15693: return "対応するNFC-Vタグではありません"
        case .invalidURL: return "URLの形式を確認してください"
        case .ndefUnsupported: return "名刺側FWがURL書き込みに未対応です。先にFWを更新してください"
        case .ndefNotWritable: return "この名刺のURL領域は書き込みできません"
        case .ndefVerifyFailed: return "書き込んだURLを読み返せませんでした"
        }
    }
}

/// Owns a Core NFC reader session and runs one namecard operation per tap.
///
/// The image transfer session is retained between taps so a dropped NFC link
/// resumes from the saved sequence/offset, matching the Android behaviour.
nonisolated final class NamecardWriter: NSObject, @unchecked Sendable {
    enum Request {
        case status
        case pattern(Int)
        case image(bytes: [UInt8], clean: Bool)
        case url(String)
    }

    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var request: Request = .status
    private var onLog: (@Sendable (String) -> Void)?
    private var onProgress: (@Sendable (TransferProgress) -> Void)?
    private var retainedImageSession: ImageTransferSession?

    /// Discards any retained image progress so the next image write starts fresh.
    func resetImageProgress() {
        retainedImageSession = nil
    }

    func run(
        _ request: Request,
        alertMessage: String,
        onLog: @escaping @Sendable (String) -> Void,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        guard NFCTagReaderSession.readingAvailable else {
            throw NamecardWriterError.nfcNotAvailable
        }
        self.request = request
        self.onLog = onLog
        self.onProgress = onProgress

        guard let session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self) else {
            throw NamecardWriterError.sessionUnavailable
        }
        session.alertMessage = alertMessage
        self.session = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            session.begin()
        }
    }

    // MARK: - Operation

    private func perform(session: NFCTagReaderSession, tag: NFCTag, iso15693: NFCISO15693Tag) async {
        let log = onLog ?? { _ in }
        let forward = onProgress ?? { _ in }
        // Mirror progress onto the Core NFC scan sheet so the user sees the write
        // state ("書き込み中 45%") on the system UI, not just inside the app.
        let progress: @Sendable (TransferProgress) -> Void = { update in
            session.alertMessage = "\(update.status)（\(Int(update.fraction * 100))%）"
            forward(update)
        }
        do {
            try await session.connect(to: tag)
            let mailbox = ST25Mailbox(tag: iso15693)

            // Weaker readers detect the passive ST25 well before harvested power
            // has charged VRES enough to boot the MCU. Stay quiet first.
            progress(TransferProgress(fraction: 0.05, status: "MCU起動・VRES充電を待っています"))
            try await Task.sleep(for: .milliseconds(Constants.bootQuietMs))
            try await mailbox.enable()

            let transfer = NamecardTransfer(onLog: log, onProgress: progress)
            switch request {
            case .status:
                _ = try await transfer.status(mailbox)
            case let .pattern(id):
                try await transfer.pattern(mailbox, id: id)
            case let .image(bytes, clean):
                let imageSession = reuseOrCreateSession(bytes: bytes, clean: clean)
                try await transfer.image(mailbox, session: imageSession)
                retainedImageSession = nil
            case let .url(urlString):
                try await writeURL(urlString, tag: iso15693, mailbox: mailbox, log: log, progress: progress)
            }

            session.invalidate()
            finish(.success(()))
        } catch {
            log("失敗: \(error.localizedDescription)")
            session.invalidate(errorMessage: error.localizedDescription)
            finish(.failure(error))
        }
    }

    /// Writes an NDEF URI record after asking the firmware to pause its mailbox
    /// image processing, then reads it back to verify. Mirrors the Android
    /// `runUrlWrite` handshake (NDEF_WRITE_PREPARE → disable mailbox → write →
    /// verify → re-enable).
    private func writeURL(
        _ urlString: String,
        tag: NFCISO15693Tag,
        mailbox: ST25Mailbox,
        log: @Sendable (String) -> Void,
        progress: @Sendable (TransferProgress) -> Void
    ) async throws {
        guard let url = URL(string: urlString),
              let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
            throw NamecardWriterError.invalidURL
        }
        let message = NFCNDEFMessage(records: [payload])

        progress(TransferProgress(fraction: 0.25, status: "URL書き込みを準備中"))
        let transferId = UInt16(UInt64(Date().timeIntervalSince1970 * 1000) & 0xffff)
        let ack = try await mailbox.exchange(
            NamecardProtocol.frame(type: .ndefWritePrepare, transferId: transferId, sequence: 0, offset: 0, payload: [])
        )
        if ack.error == NamecardFirmwareError.command.rawValue {
            throw NamecardWriterError.ndefUnsupported
        }
        try ack.requireSuccess()
        try await mailbox.disable()

        progress(TransferProgress(fraction: 0.5, status: "URLを書き込み中"))
        let (status, _) = try await tag.queryNDEFStatus()
        guard status == .readWrite else { throw NamecardWriterError.ndefNotWritable }
        try await tag.writeNDEF(message)

        progress(TransferProgress(fraction: 0.8, status: "URLを確認中"))
        let readBack = try await tag.readNDEF()
        guard readBack.records.contains(where: { $0.wellKnownTypeURIPayload() == url }) else {
            throw NamecardWriterError.ndefVerifyFailed
        }

        // Best effort: re-enable the mailbox so image writes work again.
        try? await mailbox.enable()
        log("URLを書き込み、読み返して確認しました: \(url.absoluteString)")
        progress(TransferProgress(fraction: 1.0, status: "URLを書き込みました"))
    }

    private func reuseOrCreateSession(bytes: [UInt8], clean: Bool) -> ImageTransferSession {
        if let previous = retainedImageSession,
           previous.image == bytes,
           previous.cleanBeforeWrite == clean {
            return previous
        }
        let created = ImageTransferSession(image: bytes, cleanBeforeWrite: clean)
        retainedImageSession = created
        return created
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.onLog = nil
        self.onProgress = nil
        self.session = nil
        continuation.resume(with: result)
    }

    private enum Constants {
        static let bootQuietMs = 4_000
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NamecardWriter: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        finish(.failure(error))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let first = tags.first, case let .iso15693(iso) = first else {
            session.invalidate(errorMessage: NamecardWriterError.notISO15693.localizedDescription)
            return
        }
        Task { await self.perform(session: session, tag: first, iso15693: iso) }
    }
}
