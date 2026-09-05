import SwiftUI

struct SettingsView: View {
    @Bindable var controller: NamecardController
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("書き込みオプション") {
                    Toggle("書き換え前にクリーニング（白→黒→白）", isOn: $controller.cleanBeforeWrite)
                        .font(.subheadline)
                }

                Section("URLを書き込む（NDEF）") {
                    TextField("https://example.com", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        controller.writeURL(urlText)
                    } label: {
                        Label("URLを書き込む", systemImage: "link")
                    }
                    .disabled(controller.isBusy || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("内蔵パターン（画像なしで表示更新を試験）") {
                    Picker("パターン", selection: $controller.selectedPatternId) {
                        ForEach(Array(controller.patternNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index + 1)
                        }
                    }
                    Button {
                        controller.writePattern()
                    } label: {
                        Label("選択パターンを書き込む", systemImage: "square.grid.2x2")
                    }
                    .disabled(controller.isBusy)
                }

                Section("ステータス") {
                    Button {
                        controller.checkStatus()
                    } label: {
                        Label("STATUSを確認", systemImage: "waveform.path.ecg")
                    }
                    .disabled(controller.isBusy)
                }

                Section("通信ログ") {
                    Text(controller.logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("ログをクリア") { controller.clearLog() }
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
