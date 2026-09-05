import SwiftUI

struct RootView: View {
    @State private var controller = NamecardController()
    @State private var editor = EditorCanvasState()

    var body: some View {
        TabView {
            EditorView(editor: editor, controller: controller)
                .tabItem { Label("New", systemImage: "square.and.pencil") }

            SettingsView(controller: controller)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .overlay { if controller.isBusy { progressOverlay } }
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
