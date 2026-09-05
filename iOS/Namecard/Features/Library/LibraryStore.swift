import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LibraryStore {
    private(set) var cards: [LibraryCard] = []
    private(set) var message = ""

    private let repository = CardLibraryRepository()

    init() { reload() }

    func reload() { cards = repository.list() }

    func save(name: String, bytes: [UInt8]) {
        do {
            let card = try repository.save(name: name, bytes: bytes)
            reload()
            message = "「\(card.name)」を保存しました。"
        } catch {
            message = "保存エラー: \(error.localizedDescription)"
        }
    }

    func rename(_ card: LibraryCard, to name: String) {
        do {
            let renamed = try repository.rename(card, to: name)
            reload()
            message = "「\(renamed.name)」へ変更しました。"
        } catch {
            message = "名称変更エラー: \(error.localizedDescription)"
        }
    }

    func delete(_ card: LibraryCard) {
        repository.delete(card)
        reload()
        message = "「\(card.name)」を削除しました。"
    }

    func importBIN(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count == NativeImageFormat.byteCount else {
                throw NativeImageFormatError.invalidByteCount(data.count)
            }
            let name = url.deletingPathExtension().lastPathComponent
            save(name: name.isEmpty ? "インポート画像" : name, bytes: [UInt8](data))
        } catch {
            message = "インポートエラー: \(error.localizedDescription)"
        }
    }

    func thumbnail(for card: LibraryCard) -> UIImage? {
        guard let pixels = try? NativeImageFormat.decode(card.bytes) else { return nil }
        return CanvasRenderer.image(fromCanvasPixels: pixels)
    }
}

/// A `.bin` file wrapper for SwiftUI `.fileExporter`.
struct BinDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    var bytes: [UInt8]

    init(bytes: [UInt8]) { self.bytes = bytes }

    init(configuration: ReadConfiguration) throws {
        bytes = [UInt8](configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(bytes))
    }
}
