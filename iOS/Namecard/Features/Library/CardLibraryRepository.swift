import Foundation

/// A saved card: native 1-bit bytes plus metadata. BIN files are byte-compatible
/// with the Android client and the exported/imported `.bin` format.
struct LibraryCard: Identifiable, Equatable {
    let id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var bytes: [UInt8]
}

/// Stores cards as `<id>.json` + `<id>.bin` under Application Support.
/// Ported from the Android `CardLibraryRepository`.
struct CardLibraryRepository {
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("card-library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func list() -> [LibraryCard] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(readCard)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(name: String, bytes: [UInt8]) throws -> LibraryCard {
        guard bytes.count == NativeImageFormat.byteCount else {
            throw NativeImageFormatError.invalidByteCount(bytes.count)
        }
        let now = Date()
        let card = LibraryCard(
            id: UUID().uuidString, name: normalize(name),
            createdAt: now, updatedAt: now, bytes: bytes
        )
        try Data(bytes).write(to: binURL(card.id))
        try writeMetadata(card)
        return card
    }

    @discardableResult
    func rename(_ card: LibraryCard, to name: String) throws -> LibraryCard {
        var updated = card
        updated.name = normalize(name)
        updated.updatedAt = Date()
        try writeMetadata(updated)
        return updated
    }

    func delete(_ card: LibraryCard) {
        try? FileManager.default.removeItem(at: binURL(card.id))
        try? FileManager.default.removeItem(at: metadataURL(card.id))
    }

    // MARK: - Private

    private func readCard(_ metadata: URL) -> LibraryCard? {
        guard
            let data = try? Data(contentsOf: metadata),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = json["id"] as? String,
            let name = json["name"] as? String,
            let created = json["createdAt"] as? TimeInterval,
            let updated = json["updatedAt"] as? TimeInterval,
            let bytes = try? Data(contentsOf: binURL(id)),
            bytes.count == NativeImageFormat.byteCount
        else { return nil }
        return LibraryCard(
            id: id, name: name,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            bytes: [UInt8](bytes)
        )
    }

    private func writeMetadata(_ card: LibraryCard) throws {
        let json: [String: Any] = [
            "id": card.id, "name": card.name,
            "createdAt": card.createdAt.timeIntervalSince1970,
            "updatedAt": card.updatedAt.timeIntervalSince1970,
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: metadataURL(card.id))
    }

    private func metadataURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).json") }
    private func binURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).bin") }

    private func normalize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? "名称未設定" : trimmed
        return String(value.prefix(80))
    }
}
