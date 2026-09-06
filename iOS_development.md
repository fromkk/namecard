# iOSアプリの構成と実装メモ

## 現在の状況

iOSアプリのソースは[`iOS/`](iOS/)にあります。SwiftUI + MVVMで実装し、外部ライブラリには依存していません（Core NFC / SwiftUI / Core Graphicsのみ）。iPhone実機とv5基板で、画像書き込み・URL書き込み・内蔵パターン表示を確認済みです。

対応機能:

- 画像書き込み（ドット密度 / 1bpp）と、レイヤー編集（テキスト・画像、移動・拡大縮小・回転・重なり順・Undo/Redo・グリッド）
- Library（カードのJSON + BIN保存、サムネイル、編集読込、改名、削除、Android互換のBIN入出力）
- URL（NDEF URI）書き込みと読み返し確認
- 内蔵パターン / STATUS確認

4階調（gray4）表示は今回のスコープ外です。iOSのリーダーセッションは約60秒で終了する一方、4階調はEPDの帯域ごとの更新と、電源サイクルをまたぐ2プレーン再開が必要で相性が悪いため、まず1bppに絞りました。

以降は、移植時の設計資料と、プロトコル・画像形式・コマンドの仕様（`iOS/`実装の背景）です。

## ビルドと署名

1. `iOS/Namecard.xcodeproj`をXcodeで開く
2. アプリターゲットの`Signing & Capabilities`で自分のTeamを選ぶ（`Near Field Communication Tag Reading` Capabilityと`NFCReaderUsageDescription`は設定済み、Bundle Identifierは`work.tokumaru.namecard`）
3. iPhone実機を接続してビルド・実行する

Core NFCを有効にしたアプリを実機で署名・実行するには`Near Field Communication Tag Reading` Capabilityが必要です。これは無料のPersonal Teamでは利用できず、Apple Developer Program（年額）への加入が必要です。Simulatorではファームウェアと通信できないため、NFC以外（UI・画像変換）の確認のみ可能です。

- [Apple Developer Program](https://developer.apple.com/programs/)
- [iOSでサポートされるCapability](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)

## 目標とする機能

iOS版はAndroid版の主要機能を次のように実装しています（4階調を除く）。

| Android版の機能 | iOS版の実装 |
| --- | --- |
| Jetpack Compose UI | SwiftUI |
| テキスト・画像レイヤー編集 | SwiftUI gestures + Core Graphics |
| 移動、拡大縮小、回転、整列、Undo/Redo | SwiftUI state + UndoManager |
| 1-bitディザ画像 | Core Graphicsで描画後、同じ4×4 Bayer変換 |
| 4階調画像 | 未対応（スコープ外。「現在の状況」参照） |
| NFC-V / ST25DV Mailbox | Core NFC `NFCTagReaderSession` + `NFCISO15693Tag` |
| 中断後の再開 | `STATUS`応答のsequence/offsetから再開 |
| URL書き込み | `NFCNDEFTag`によるNDEF URI書き込みと読み返し |
| LibraryとBIN入出力 | Application Support配下のJSON + BIN、Document Picker |
| 内蔵パターン・状態確認 | 既存の`PATTERN` / `STATUS`コマンド |

UIコードをそのまま共有することはできませんが、画像形式と通信プロトコルは共通です。まずプロトコル部分をSwiftで忠実に移植し、その上へSwiftUIを載せる構成が最も小さく始められます。

## 正とする既存実装

移植時は次のファイルを仕様の基準にしてください。

- [`client/android/app/src/main/java/jp/namecard/nfctest/NamecardProtocol.kt`](client/android/app/src/main/java/jp/namecard/nfctest/NamecardProtocol.kt) — ST25DV Mailbox、フレーム生成、ACK解析
- [`client/android/app/src/main/java/jp/namecard/nfctest/NativeImageFormat.kt`](client/android/app/src/main/java/jp/namecard/nfctest/NativeImageFormat.kt) — 1-bit・4階調画像変換
- [`client/android/app/src/main/java/jp/namecard/nfctest/MainActivity.kt`](client/android/app/src/main/java/jp/namecard/nfctest/MainActivity.kt) — 転送、再試行、NDEF書き込みの状態遷移
- [`firmware/Core/Inc/nc_protocol.h`](firmware/Core/Inc/nc_protocol.h) — ファームウェア側の定数とフレーム定義
- [`firmware/Core/Src/nc_protocol.c`](firmware/Core/Src/nc_protocol.c) — フレーム検証と転送状態
- [`firmware/Core/Src/app.c`](firmware/Core/Src/app.c) — 充電、表示更新、ACKの意味

Android側の挙動だけを推測して別プロトコルを作らず、ファームウェア側の定義とも照合してください。

## 開発環境を用意する

必要なものは次の通りです。

- 現行Xcodeが動作するMac
- Core NFCを利用できる実機iPhone。SimulatorではNFC通信を検証できません
- v5基板と現行ファームウェア
- Apple Developer Programのメンバーシップ。Core NFCを有効にした実機ビルドと一般公開の両方で必要です

アプリは[`iOS/`](iOS/)に配置済みです。Bundle Identifierは`work.tokumaru.namecard`、Teamは未設定なので、`Signing & Capabilities`で自分のTeamを選んでください。`Near Field Communication Tag Reading` Capability（entitlement）と`NFCReaderUsageDescription`は設定済みです。

- [Apple: Building an NFC Tag-Reader App](https://developer.apple.com/documentation/corenfc/building-an-nfc-tag-reader-app)
- [Apple: Core NFC](https://developer.apple.com/documentation/corenfc)

## ディレクトリ構成

```text
iOS/
  Namecard.xcodeproj
  Namecard/
    NamecardApp.swift
    Namecard.entitlements
    Protocol/{NamecardProtocol.swift, Ack.swift}
    Image/{NativeImageFormat.swift, CanvasRenderer.swift}
    NFC/{ST25Mailbox.swift, NamecardTransfer.swift, NamecardWriter.swift}
    Features/
      RootView.swift
      NamecardController.swift
      Editor/{EditorCanvasState.swift, EditorView.swift}
      Library/{CardLibraryRepository.swift, LibraryStore.swift, LibraryView.swift}
      Settings/{SettingsView.swift, UrlValidation.swift}
  NamecardTests/
```

`NamecardProtocol`、`Ack`、`NativeImageFormat`はCore NFCやSwiftUIに依存させず、単体テストだけで検証できるようにしています。`ST25Mailbox`（Core NFC）と`NamecardTransfer`（転送の状態機械）がその上で通信を担います。

## 実装手順

以下は移植時の手順で、現在の[`iOS/`](iOS/)実装の背景です。プロトコルと画像形式は`firmware`とAndroid実装を正として移植し、Swift Testingの単体テストで一致を確認しています。

### 1. プロトコルをSwiftへ移植する

Namecard protocolのフレームは最大256 bytesで、16-byte headerの後ろに最大240-byte payloadが続きます。複数byte整数はlittle endianです。

| Offset | Size | 内容 |
| ---: | ---: | --- |
| 0 | 2 | Magic: ASCII `NC` |
| 2 | 1 | Version: `1` |
| 3 | 1 | Type |
| 4 | 2 | Transfer ID |
| 6 | 2 | Sequence |
| 8 | 2 | Offset |
| 10 | 2 | Payload length |
| 12 | 2 | Header CRC16 |
| 14 | 2 | Payload CRC16 |
| 16 | 可変 | Payload |

CRC16は初期値`0xFFFF`、多項式`0x1021`のCRC-16/CCITTです。Header CRCの計算時はoffset 12〜13を除外します。画像全体の検証にはCRC-32/IEEEを使います。

コマンド種別は次の通りです。

| Type | Value | 用途 |
| --- | ---: | --- |
| START | `0x01` | 画像サイズ、形式、CRCを通知 |
| DATA | `0x02` | 画像データを分割送信 |
| COMMIT | `0x03` | 受信画像を検証・確定 |
| STATUS | `0x04` | 状態、電圧、中断位置を取得 |
| EXECUTE | `0x05` | e-paper更新を開始 |
| PATTERN | `0x06` | 内蔵試験パターンを表示 |
| NDEF_WRITE_PREPARE | `0x07` | NDEF書き込み前にMailboxを停止 |
| ACK | `0x80` | 成功・進捗応答 |
| ERROR | `0x81` | エラー応答 |

最初にAndroidのunit testと同じ入力・期待値をSwift XCTestへ移植し、CRC、フレーム、ACK、画像変換が一致することを確認します。

### 2. Core NFCでST25DVへ接続する

`NFCTagReaderSession`を`.iso15693`で開始し、検出した`.iso15693`タグへ`session.connect(to:)`で接続します。`NFCISO15693Tag`はISO 15693の標準コマンドとメーカー独自コマンドを送信できます。

この名刺で必要なST25DVコマンドは次の通りです。

| Command | Value | Request parameters |
| --- | ---: | --- |
| Fast Write Message | `0xAA` | `[frame length - 1] + frame` |
| Fast Read Message | `0xAC` | `[start offset, response length - 1]` |
| Read Dynamic Configuration | `0xAD` | `[register address]` |
| Write Dynamic Configuration | `0xAE` | `[register address, value]` |

STのmanufacturer codeは`0x02`です。Core NFCの`customCommand` APIはmanufacturer codeなどISO 15693の外側のフレームを組み立てるため、`customRequestParameters`にはAndroidのraw `NfcV.transceive()`と違ってUIDやmanufacturer codeを重ねて入れず、表のST固有parameterだけを渡します。

概念的には次の呼び出しになります。

```swift
let response = try await tag.customCommand(
    requestFlags: [.highDataRate, .address],
    customCommandCode: 0xAD,
    customRequestParameters: Data([registerAddress])
)
```

Core NFCがメーカー独自コマンド`0xA0`〜`0xDF`を扱えることはAppleのAPI仕様に明記されています。

- [Apple: NFCISO15693Tag](https://developer.apple.com/documentation/corenfc/nfciso15693tag)
- [Apple: customCommand](https://developer.apple.com/documentation/corenfc/nfciso15693tag/customcommand%28requestflags%3Acustomcommandcode%3Acustomrequestparameters%3Acompletionhandler%3A%29)
- [ST: ST25DV Fast Transfer Mode application note](https://www.st.com/resource/en/application_note/an4910-data-exchange-between-wired-ic-and-wireless-rf-iso-15693-using-fast-transfer-mode-supported-by-st25dvi2c-series-stmicroelectronics.pdf)
- [ST: NFC Tap iOS application](https://www.st.com/en/embedded-software/stsw-st25ios001.html)

STのiOSサンプルは参考になりますが、このプロジェクトのプロトコル自体は小さいため、最初の試作ではSDK全体を組み込まずCore NFCへ直接実装する方が依存関係を抑えられます。

### 3. Mailbox交換を実装する

Android版と同じ順序で次を実装します。

1. `MB_CTRL_Dyn`を読み、必要なら`MB_EN`を有効化する
2. Mailboxが空くまで待つ
3. `0xAA`でNamecard frameを書き込む
4. 約50 ms待ち、`MB_CTRL_Dyn`の`HOST_PUT_MSG`をpollする
5. `0xAC`で32-byte ACKを読み、CRCと内容を検証する
6. ACKが返す`expectedSequence`と`expectedOffset`を次の送信へ使う

1回のDATA payloadはprotocol上240 bytes以下です。Core NFCで安定する最大値はiPhone実機で測定し、最初は128 bytes程度から試してください。端末やOSで制約が異なる場合に備え、値を固定せずtransport層で調整できるようにします。

### 4. 画像を同じ形式へ変換する

SwiftUIの編集結果をCore Graphicsで296×128 pixelのARGB画像へ描画し、Android版と同じnative formatへ変換します。

- 1-bit: 4,736 bytes
- 4階調: 4,736 bytes × 2 planes = 9,472 bytes
- Native index: `x * 16 + y / 8`
- Bit mask: `0x80 >> (y & 7)`
- 1-bitの閾値: Android版と同じ4×4 Bayer matrix

透明pixelは白背景へ合成してから輝度を計算します。AndroidでexportしたBINとiOSで生成したBINをbyte単位で比較するgolden testを用意してください。

### 5. 画像転送の状態機械を移植する

基本フローは次の通りです。

```text
STATUS → START → DATA × N → COMMIT → 充電待ち → STATUS → EXECUTE → STATUS
```

重要なのは、通信切断を失敗として最初からやり直すのではなく、再タッチ後の`STATUS`に含まれるsequence/offsetから再開することです。4階調ではplane 0を保存してからplane 1を送ります。

RF通信は名刺への給電も兼ねる一方、頻繁な通信がVRESの充電を妨げる場合があります。Android版と同様に、ACKの`vddMv`を見てDATA間隔を調整し、COMMIT後は通信を止めて充電時間を確保します。

iOS側のreader sessionはOSにより中断・無効化されることがあるため、1回のsessionで必ず完了する前提にしないでください。アプリ側に転送ID、plane、sequence、offsetを保持し、「名刺を離してもう一度タッチ」で安全に続行できるUIにします。

### 6. NDEF URL書き込みを移植する

`NFCISO15693Tag`は`NFCNDEFTag`としても利用できます。Android版と同じく、次の順序を守ります。

1. `NDEF_WRITE_PREPARE`を送り、ファームウェアに画像処理停止を要求する
2. ST25DV Mailboxを無効化する
3. NDEF URI recordを書き込む
4. 書いたNDEFを読み返して一致を確認する
5. Mailboxを再び有効化する

URLは`http`または`https`だけを許可し、Android版と同じ480-byte上限を適用します。途中でsessionが切れた場合も、次回接続時にMailboxを再開できるよう`defer`相当の後処理を用意します。

### 7. SwiftUIの編集画面とLibraryを作る

通信が安定してから、UIを次の順序で追加します。

1. 画像選択と296×128 preview
2. テキスト・画像layer
3. drag、pinch、rotation、整列、grid、snap
4. Undo/Redoとlayer順序
5. 1-bit / 4階調切り替え
6. Library保存、rename、import/export
7. 書き込み進捗、アンテナ位置、再タッチ案内

BINファイル形式をAndroid版と同じにすれば、両OS間でデータを交換できます。

## 開発計画

機能を一度に移植せず、実機で不確実性を潰す順序で進めました。

| Phase | 完了条件 | 状況 |
| --- | --- | --- |
| 0. Feasibility spike | iPhoneでST25DVを検出し、`STATUS` ACKを取得 | 完了 |
| 1. Transport | Mailbox、CRC、retry、再タッチ再開 | 完了 |
| 2. Hardware update | PATTERN、1-bit画像を表示 | 完了（4階調は対象外） |
| 3. Editor | 画像・文字編集とAndroid互換BIN生成 | 完了 |
| 4. Library / URL | 保存、入出力、NDEF URL書き込み | 完了 |
| 5. Distribution | 複数iPhoneで検証し、配布方法を決定 | 未着手 |

残る課題は、複数機種での検証と、整列スナップ／ガイド線・キャンバスのパン/ズームといったエディタの細部です。

## 実機テスト項目

- `NFCTagReaderSession.readingAvailable`がtrueになること
- ST25DV04KだけをISO 15693タグとして選択できること
- `MB_EN`の有効化、32-byte ACK、CRC検証
- 10種類の内蔵パターン
- 1-bit画像と4階調画像
- 転送中に名刺を離し、再タッチで続行できること
- 弱いアンテナ位置でVDDに応じた待ち時間が働くこと
- URL書き込み後、アプリ外から通常のNFCタッチでURLが開くこと
- 異なるiPhoneモデル・iOSバージョンでの転送時間と安定性

## 実装・検証できた方へ

このリポジトリの独自部分はMIT Licenseです。iOS版の試作、Core NFCでのST25DV Mailbox疎通、対応端末の検証結果だけでも歓迎します。

Pull RequestまたはIssueに加えて、実装や実機検証ができた場合は[https://tokumaru.work](https://tokumaru.work)からご連絡ください。
