import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var library: LibraryStore
    @Bindable var controller: NamecardController
    var onEdit: (LibraryCard) -> Void

    @State private var showingImporter = false
    @State private var exportCard: LibraryCard?
    @State private var renameCard: LibraryCard?
    @State private var renameText = ""
    @State private var deleteCard: LibraryCard?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if library.cards.isEmpty {
                    ContentUnavailableView(
                        "保存したカードはありません",
                        systemImage: "square.stack",
                        description: Text("New で作成して保存するか、BIN をインポートしてください。")
                    )
                } else {
                    ScrollView {
                        if !library.message.isEmpty {
                            Text(library.message)
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(library.cards) { card in
                                cardCell(card)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                Button {
                    showingImporter = true
                } label: {
                    Label("インポート", systemImage: "square.and.arrow.down")
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data]) { result in
                if case let .success(url) = result { library.importBIN(from: url) }
            }
            .fileExporter(
                isPresented: Binding(get: { exportCard != nil }, set: { if !$0 { exportCard = nil } }),
                document: exportCard.map { BinDocument(bytes: $0.bytes) },
                contentType: .data,
                defaultFilename: exportFilename(exportCard)
            ) { _ in exportCard = nil }
            .alert("カード名を変更", isPresented: Binding(get: { renameCard != nil }, set: { if !$0 { renameCard = nil } })) {
                TextField("カード名", text: $renameText)
                Button("保存") {
                    if let card = renameCard { library.rename(card, to: renameText) }
                    renameCard = nil
                }
                Button("キャンセル", role: .cancel) { renameCard = nil }
            }
            .confirmationDialog(
                "「\(deleteCard?.name ?? "")」を削除しますか？",
                isPresented: Binding(get: { deleteCard != nil }, set: { if !$0 { deleteCard = nil } }),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let card = deleteCard { library.delete(card) }
                    deleteCard = nil
                }
                Button("キャンセル", role: .cancel) { deleteCard = nil }
            }
        }
    }

    private func cardCell(_ card: LibraryCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.white
                if let thumb = library.thumbnail(for: card) {
                    Image(uiImage: thumb).interpolation(.high).resizable().scaledToFit()
                }
            }
            .aspectRatio(EditorCanvasState.paperWidth / EditorCanvasState.paperHeight, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            Text(card.name).font(.subheadline.weight(.medium)).lineLimit(1)

            HStack {
                Button {
                    controller.writeImage(bytes: card.bytes)
                } label: {
                    Image(systemName: "wave.3.right")
                }
                .disabled(controller.isBusy)

                Button { onEdit(card) } label: { Image(systemName: "pencil") }

                Spacer()

                Menu {
                    Button { renameCard = card; renameText = card.name } label: { Label("名称変更", systemImage: "textformat") }
                    Button { exportCard = card } label: { Label("BINをエクスポート", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { deleteCard = card } label: { Label("削除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func exportFilename(_ card: LibraryCard?) -> String {
        guard let card else { return "namecard" }
        let safe = card.name.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
        let trimmed = safe.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "namecard" : trimmed
    }
}
