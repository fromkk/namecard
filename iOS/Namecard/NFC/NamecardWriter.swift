import CoreNFC
import Foundation

enum NamecardWriterError: Error, LocalizedError {
    case nfcNotAvailable
    case sessionUnavailable
    case notISO15693

    var errorDescription: String? {
        switch self {
        case .nfcNotAvailable: return "この端末ではNFCを利用できません"
        case .sessionUnavailable: return "NFCセッションを開始できませんでした"
        case .notISO15693: return "対応するNFC-Vタグではありません"
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
        case image(bytes: [UInt8], format: NamecardImageFormat, clean: Bool)
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
            case let .image(bytes, format, clean):
                let imageSession = reuseOrCreateSession(bytes: bytes, format: format, clean: clean)
                try await transfer.image(mailbox, session: imageSession)
                retainedImageSession = nil
            }

            session.invalidate()
            finish(.success(()))
        } catch {
            log("失敗: \(error.localizedDescription)")
            session.invalidate(errorMessage: error.localizedDescription)
            finish(.failure(error))
        }
    }

    private func reuseOrCreateSession(
        bytes: [UInt8],
        format: NamecardImageFormat,
        clean: Bool
    ) -> ImageTransferSession {
        let expectedClean = format == .dotDensity && clean
        if let previous = retainedImageSession,
           previous.image == bytes,
           previous.format == format,
           previous.cleanBeforeWrite == expectedClean {
            return previous
        }
        let created = ImageTransferSession(image: bytes, format: format, cleanBeforeWrite: clean)
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
