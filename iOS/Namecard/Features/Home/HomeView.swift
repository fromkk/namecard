import PhotosUI
import SwiftUI

struct HomeView: View {
    @State private var model = HomeViewModel()
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.nfcAvailable {
                        Label("この端末ではNFCを利用できません（実機のみ対応）", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    previewSection
                    formatSection
                    imageActions
                    Divider()
                    hardwareTestSection
                    Divider()
                    logSection
                }
                .padding()
            }
            .navigationTitle("Namecard")
            .overlay { if model.isBusy { progressOverlay } }
            .onChange(of: photoItem) { _, newValue in
                Task { await model.loadImage(from: newValue) }
            }
            .onChange(of: model.selectedFormat) { _, _ in model.updatePreview() }
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プレビュー（296 × 128）")
                .font(.headline)
            ZStack {
                Color.white
                if let preview = model.previewImage {
                    Image(uiImage: preview)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("画像を選択してください")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(CGFloat(NativeImageFormat.width) / CGFloat(NativeImageFormat.height), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("送信方式").font(.headline)
            Picker("送信方式", selection: $model.selectedFormat) {
                ForEach(NamecardImageFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Toggle("書き換え前にクリーニング（白→黒→白）", isOn: $model.cleanBeforeWrite)
                .disabled(model.selectedFormat == .gray4)
                .font(.subheadline)
        }
    }

    private var imageActions: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("画像を選択", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                model.writeImage()
            } label: {
                Label(
                    model.isBusy ? "書き込み中…" : "NFCで画像を書き込む",
                    systemImage: "wave.3.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canWriteImage)
        }
    }

    private var hardwareTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ハードウェアテスト").font(.headline)

            Picker("内蔵パターン", selection: $model.selectedPatternId) {
                ForEach(Array(model.patternNames.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index + 1)
                }
            }
            .pickerStyle(.menu)

            Button {
                model.writePattern()
            } label: {
                Label("選択パターンを書き込む", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)

            Button {
                model.checkStatus()
            } label: {
                Label("STATUSを確認", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通信ログ").font(.headline)
            Text(model.logText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(model.busyTitle)
                    .font(.headline)
                Text(model.progressStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ProgressView(value: model.progressFraction)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text("\(Int(model.progressFraction * 100))%")
                    .font(.title3.bold())
                    .monospacedDigit()
                Text("完了するまで名刺を動かさないでください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

#Preview {
    HomeView()
}
