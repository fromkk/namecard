import Observation
import SwiftUI

/// Shared NFC coordinator: runs writes/patterns/status, exposes progress and a
/// running log for the UI. Editor and Settings screens share one instance.
@MainActor
@Observable
final class NamecardController {
    var cleanBeforeWrite = true
    var selectedPatternId = 1

    private(set) var isBusy = false
    private(set) var busyTitle = ""
    private(set) var progressFraction = 0.0
    private(set) var progressStatus = ""
    private(set) var logText = "操作を選んでから名刺へタッチしてください。\n"

    let patternNames = [
        "1. チェック柄", "2. NFC OK", "3. 全面黒", "4. 全面白", "5. 長辺の縞",
        "6. 短辺の縞", "7. グリッド", "8. 斜線", "9. ターゲット", "10. TEST 10",
    ]

    var nfcAvailable: Bool { writer.isAvailable }

    private let writer = NamecardWriter()

    func writeImage(bytes: [UInt8]) {
        run(.image(bytes: bytes, clean: cleanBeforeWrite), alert: "名刺へタッチして固定してください")
    }

    func checkStatus() {
        run(.status, alert: "名刺へタッチしてください")
    }

    func writePattern() {
        run(.pattern(selectedPatternId), alert: "名刺へタッチして固定してください")
    }

    func clearLog() {
        logText = ""
    }

    private func run(_ request: NamecardWriter.Request, alert: String) {
        guard !isBusy else { return }
        guard writer.isAvailable else {
            append("この端末ではNFCを利用できません。\n")
            return
        }
        isBusy = true
        busyTitle = busyTitle(for: request)
        progressFraction = 0
        progressStatus = "名刺を探しています"

        let onLog: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.append(message + "\n") }
        }
        let onProgress: @Sendable (TransferProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.progressFraction = progress.fraction
                self?.progressStatus = progress.status
            }
        }

        Task {
            do {
                try await writer.run(request, alertMessage: alert, onLog: onLog, onProgress: onProgress)
                progressStatus = "完了しました"
            } catch is CancellationError {
                append("キャンセルされました。\n")
            } catch {
                append("エラー: \(error.localizedDescription)\n")
            }
            isBusy = false
        }
    }

    private func busyTitle(for request: NamecardWriter.Request) -> String {
        switch request {
        case .image: return "NFCで画像を書き込み中"
        case .pattern: return "パターンを書き込み中"
        case .status: return "STATUSを確認中"
        }
    }

    private func append(_ message: String) {
        logText += message
    }
}
