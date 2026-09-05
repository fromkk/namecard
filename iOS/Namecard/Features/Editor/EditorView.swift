import PhotosUI
import SwiftUI

struct EditorView: View {
    @Bindable var editor: EditorCanvasState
    @Bindable var controller: NamecardController
    @Bindable var library: LibraryStore

    @State private var photoItem: PhotosPickerItem?
    @State private var showingTextInput = false
    @State private var textInput = ""
    @State private var showingSaveDialog = false
    @State private var saveName = ""

    // Gesture tracking
    @State private var dragging = false
    @State private var transforming = false
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnify: CGFloat = 1
    @State private var lastRotation: Angle = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                canvas
                toolbar
                Button {
                    writeCurrent()
                } label: {
                    Label("NFCで書き込む", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isBusy)

                if !controller.nfcAvailable {
                    Label("NFCは実機のみ対応", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("New")
            .toolbar {
                Button {
                    saveName = ""
                    showingSaveDialog = true
                } label: {
                    Label("ライブラリに保存", systemImage: "square.and.arrow.down")
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadImage(item) }
            }
            .alert("テキストを追加", isPresented: $showingTextInput) {
                TextField("テキスト", text: $textInput)
                Button("追加") {
                    editor.addText(textInput)
                    textInput = ""
                }
                Button("キャンセル", role: .cancel) { textInput = "" }
            }
            .alert("ライブラリに保存", isPresented: $showingSaveDialog) {
                TextField("カード名", text: $saveName)
                Button("保存") { saveToLibrary() }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let scale = geo.size.width / EditorCanvasState.paperWidth
            ZStack(alignment: .topLeading) {
                if let preview = editor.previewImage {
                    Image(uiImage: preview)
                        .interpolation(.high)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.width * EditorCanvasState.paperHeight / EditorCanvasState.paperWidth)
                }
                selectionOverlay(scale: scale)
            }
            .frame(width: geo.size.width, height: geo.size.width * EditorCanvasState.paperHeight / EditorCanvasState.paperWidth)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .contentShape(Rectangle())
            .gesture(dragGesture(scale: scale))
            .gesture(magnifyRotateGesture())
        }
        .aspectRatio(EditorCanvasState.paperWidth / EditorCanvasState.paperHeight, contentMode: .fit)
    }

    @ViewBuilder
    private func selectionOverlay(scale: CGFloat) -> some View {
        if let selection = editor.selectionBounds() {
            let rect = selection.rect
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(.blue)
                .frame(width: rect.width * scale, height: rect.height * scale)
                .rotationEffect(.degrees(selection.rotation))
                .position(x: rect.midX * scale, y: rect.midY * scale)
                .allowsHitTesting(false)
        }
    }

    private func dragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !transforming, scale > 0 else { return }
                if !dragging {
                    dragging = true
                    editor.beginTransform()
                    editor.selectLayer(at: CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale))
                    lastTranslation = .zero
                }
                let delta = CGSize(
                    width: (value.translation.width - lastTranslation.width) / scale,
                    height: (value.translation.height - lastTranslation.height) / scale
                )
                editor.transformSelection(translation: delta, scale: 1, rotation: .zero)
                lastTranslation = value.translation
            }
            .onEnded { _ in
                dragging = false
                lastTranslation = .zero
                editor.endTransform()
            }
    }

    private func magnifyRotateGesture() -> some Gesture {
        MagnifyGesture().simultaneously(with: RotateGesture())
            .onChanged { value in
                if !transforming {
                    transforming = true
                    editor.beginTransform()
                    lastMagnify = 1
                    lastRotation = .zero
                }
                let magnification = value.first?.magnification ?? 1
                let rotation = value.second?.rotation ?? .zero
                let scaleDelta = lastMagnify != 0 ? magnification / lastMagnify : 1
                let rotationDelta = rotation - lastRotation
                editor.transformSelection(translation: .zero, scale: scaleDelta, rotation: rotationDelta)
                lastMagnify = magnification
                lastRotation = rotation
            }
            .onEnded { _ in
                transforming = false
                lastMagnify = 1
                lastRotation = .zero
                editor.endTransform()
            }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { showingTextInput = true } label: { toolLabel("テキスト", "textformat") }
                PhotosPicker(selection: $photoItem, matching: .images) { toolLabel("画像", "photo") }
                Button { editor.toggleGrid() } label: { toolLabel("グリッド", editor.gridEnabled ? "grid.circle.fill" : "grid") }
            }
            HStack(spacing: 12) {
                Button { editor.undo() } label: { icon("arrow.uturn.backward") }.disabled(!editor.canUndo)
                Button { editor.redo() } label: { icon("arrow.uturn.forward") }.disabled(!editor.canRedo)
                Button { editor.sendBackward() } label: { icon("square.2.layers.3d.bottom.filled") }.disabled(!editor.hasSelection)
                Button { editor.bringForward() } label: { icon("square.2.layers.3d.top.filled") }.disabled(!editor.hasSelection)
                Button { editor.deleteSelection() } label: { icon("trash") }.disabled(!editor.hasSelection)
                Button { editor.clearAll() } label: { icon("xmark.circle") }
            }
            .buttonStyle(.bordered)
        }
    }

    private func toolLabel(_ title: String, _ systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func writeCurrent() {
        do {
            let bytes = try editor.renderNativeImage()
            controller.writeImage(bytes: bytes)
        } catch {
            // Rendering can only fail if the canvas context could not be built.
        }
    }

    private func saveToLibrary() {
        guard let bytes = try? editor.renderNativeImage() else { return }
        library.save(name: saveName, bytes: bytes)
    }

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        editor.addImage(image)
        photoItem = nil
    }
}
