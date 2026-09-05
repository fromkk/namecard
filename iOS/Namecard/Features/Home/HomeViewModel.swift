import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    // Editing state
    var cleanBeforeWrite = true
    var selectedPatternId = 1
    private(set) var sourceImage: UIImage?
    private(set) var previewImage: UIImage?

    // Transfer state
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
    var canWriteImage: Bool { sourceImage != nil && !isBusy }

    private let writer = NamecardWriter()

    // MARK: - Image selection

    func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                append("画像を読み込めませんでした。\n")
                return
            }
            setImage(image)
        } catch {
            append("画像読込エラー: \(error.localizedDescription)\n")
        }
    }

    func setImage(_ image: UIImage) {
        sourceImage = image
        writer.resetImageProgress()
        updatePreview()
        append("画像を読み込みました。送信方式を選び、名刺へタッチしてください。\n")
    }

    func updatePreview() {
        guard let sourceImage, let pixels = CanvasRenderer.canvasPixels(from: sourceImage) else {
            previewImage = nil
            return
        }
        // Show exactly what the e-paper will receive (encode then decode).
        guard
            let encoded = try? NativeImageFormat.encode(pixels),
            let decoded = try? NativeImageFormat.decode(encoded)
        else {
            previewImage = CanvasRenderer.image(fromCanvasPixels: pixels)
            return
        }
        previewImage = CanvasRenderer.image(fromCanvasPixels: decoded)
    }

    // MARK: - NFC operations

    func writeImage() {
        guard let sourceImage else { return }
        guard let pixels = CanvasRenderer.canvasPixels(from: sourceImage) else {
            append("画像を変換できませんでした。\n")
            return
        }
        let clean = cleanBeforeWrite
        do {
            let bytes = try NativeImageFormat.encode(pixels)
            run(.image(bytes: bytes, clean: clean), alert: "名刺へタッチして固定してください")
        } catch {
            append("画像変換エラー: \(error.localizedDescription)\n")
        }
    }

    func checkStatus() {
        run(.status, alert: "名刺へタッチしてください")
    }

    func writePattern() {
        run(.pattern(selectedPatternId), alert: "名刺へタッチして固定してください")
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

    // MARK: - Log

    private func append(_ message: String) {
        logText += message
    }
}
