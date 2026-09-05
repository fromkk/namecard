import SwiftUI

struct RootView: View {
    @State private var controller = NamecardController()
    @State private var editor = EditorCanvasState()
    @State private var library = LibraryStore()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            EditorView(editor: editor, controller: controller, library: library)
                .tabItem { Label("New", systemImage: "square.and.pencil") }
                .tag(0)

            LibraryView(library: library, controller: controller, onEdit: loadCardIntoEditor)
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(1)

            SettingsView(controller: controller)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .overlay { if controller.isBusy { progressOverlay } }
    }

    private func loadCardIntoEditor(_ card: LibraryCard) {
        guard
            let pixels = try? NativeImageFormat.decode(card.bytes),
            let image = CanvasRenderer.image(fromCanvasPixels: pixels)
        else { return }
        editor.replaceWithImage(image)
        selectedTab = 0
    }

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(controller.busyTitle).font(.headline)
                Text(controller.progressStatus)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ProgressView(value: controller.progressFraction)
                    .progressViewStyle(.linear).frame(width: 220)
                Text("\(Int(controller.progressFraction * 100))%")
                    .font(.title3.bold()).monospacedDigit()
                Text("完了するまで名刺を動かさないでください")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

#Preview {
    RootView()
}
