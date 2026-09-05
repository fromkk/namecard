import Foundation
import Testing
@testable import Namecard

@MainActor
struct LibraryStoreTests {
    @Test func saveRenameDeleteRoundTrip() throws {
        let store = LibraryStore()
        let name = "test-\(UUID().uuidString)"
        let bytes = [UInt8](repeating: 0xAB, count: NativeImageFormat.byteCount)

        store.save(name: name, bytes: bytes)
        let saved = try #require(store.cards.first { $0.name == name })
        #expect(saved.bytes == bytes)

        store.rename(saved, to: name + "-renamed")
        #expect(store.cards.contains { $0.id == saved.id && $0.name == name + "-renamed" })

        let renamed = try #require(store.cards.first { $0.id == saved.id })
        store.delete(renamed)
        #expect(!store.cards.contains { $0.id == saved.id })
    }

    @Test func saveRejectsWrongByteCount() throws {
        let store = LibraryStore()
        let before = store.cards.count
        store.save(name: "bad-\(UUID().uuidString)", bytes: [0, 1, 2])
        #expect(store.cards.count == before) // nothing added
    }
}
