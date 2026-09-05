import Testing
@testable import Namecard

@MainActor
struct EditorCanvasStateTests {
    @Test func addingTextRendersBlackPixels() throws {
        let editor = EditorCanvasState()
        editor.addText("NAMECARD")

        let bytes = try editor.renderNativeImage()
        #expect(bytes.count == NativeImageFormat.byteCount)
        #expect(bytes.contains { $0 != 0xff }) // some black pixels were drawn
        #expect(editor.hasSelection)
        #expect(editor.canUndo)
    }

    @Test func undoRestoresBlankCanvas() throws {
        let editor = EditorCanvasState()
        editor.addText("A")
        editor.undo()

        let bytes = try editor.renderNativeImage()
        #expect(bytes.allSatisfy { $0 == 0xff }) // white again
        #expect(!editor.hasSelection)
        #expect(editor.canRedo)
    }

    @Test func clearRemovesEverything() throws {
        let editor = EditorCanvasState()
        editor.addText("A")
        editor.addText("B")
        editor.clearAll()
        #expect(!editor.hasSelection)
        #expect(try editor.renderNativeImage().allSatisfy { $0 == 0xff })
    }
}
