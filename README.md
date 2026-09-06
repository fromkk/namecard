# NFC Namecard/Badge

NFCによる給電（Energy Harvesting）を用いた、書き換え可能な電子ペーパー / NFCタグ / マイコンと、ファームウェア、Android/iOSアプリです。

Maker Faire Tokyo 2026のブース「そうまめの部屋」で販売します。

## リポジトリ構成

- `namecard.kicad_sch` / `namecard.kicad_pcb` — KiCad回路図・基板設計
- [`production/`](production/) — Gerber、BOM、CPLなどの製造データ
- [`firmware/`](firmware/) — STM32ファームウェア
- [`client/android/`](client/android/) — Androidアプリ
- [`iOS/`](iOS/) — iOSアプリ（SwiftUI）
- [`iOS_development.md`](iOS_development.md) — iOSアプリの構成・実装メモ

Maker Faire Tokyo 2026向けの現行製造データは[`production/v5/`](production/v5/)にあります。JLCPCBへ入稿するファイルと注意点は同ディレクトリのREADMEを確認してください。

## Androidアプリのインストール

**[最新版のAndroidアプリ（namecard.apk）をダウンロード](https://github.com/soumame/namecard/releases/download/android-main/namecard.apk)**

利用にはAndroid 8.0以降のNFC対応端末が必要です。iOSアプリのソースは[`iOS/`](iOS/)にあります。配布バイナリ（TestFlight / App Store）は提供していないため、iPhoneで使うにはXcodeで自分でビルドしてください。構成や実装メモは[iOSアプリの構成・実装メモ](iOS_development.md)を参照してください。

1. 上のリンクから`namecard.apk`をダウンロードする
2. ブラウザからのインストールが止められた場合は、表示された設定画面で今回使用したブラウザからのインストールを許可する
3. 設定画面から戻り、`namecard.apk`をインストールする
4. インストール後、必要に応じてブラウザからのインストール許可をOFFへ戻す
5. アプリを開き、画像やテキストを編集してから`NFCに書込`を選び、完了するまで名刺を端末のNFCアンテナへ固定する

アップデートするときは、最新版APKを再度ダウンロードして既存アプリの上からインストールしてください。アプリを先にアンインストールすると、Libraryに保存した画像も削除されます。

このアプリが要求するAndroid権限はNFCのみです。リリースにはAPKと一緒にSHA-256チェックサムを掲載しています。過去のバージョンと更新内容は[Releases](https://github.com/soumame/namecard/releases)で確認できます。

うまく書き込めない場合は、スマートフォンのNFCアンテナ位置を確認し、ケースを外してからもう一度お試しください。書き込み中は名刺を動かしたり、ほかのアプリへ切り替えたりしないでください。

## iOSアプリのビルド

iOSアプリのソースは[`iOS/`](iOS/)にあります。SwiftUIで実装し、外部ライブラリには依存していません。配布バイナリは提供していないため、次の手順で自分でビルドしてください。

1. `iOS/Namecard.xcodeproj`をXcodeで開く
2. アプリターゲットの`Signing & Capabilities`で自分のTeamを選ぶ（`Near Field Communication Tag Reading` Capabilityは設定済み）
3. iPhone実機を接続してビルド・実行する

対応機能は、画像書き込み（ドット密度）、レイヤー編集、Library（Android互換のBIN入出力）、URL（NDEF）書き込み、内蔵パターン表示です。Core NFCの実機動作にはApple Developer Programへの加入が必要です。4階調表示は未対応です。詳しくは[iOSアプリの構成・実装メモ](iOS_development.md)を参照してください。

## 開発状況について

詳しい開発状況は[ブログ記事](https://tokumaru.work/ja/tech/maker-faire-tokyo-2026/)をご確認ください。

## Q&A

### なんでアプリがPlay Storeで公開されていないの?

- 少量製作のハードウェア向けアプリであるため、現在は署名済みAPKをGitHub Releasesで公開しています。
- ソースコードもこのリポジトリで確認できます。

### iOS版はあるの?

- ソースは[`iOS/`](iOS/)にあります。画像書き込み（ドット密度）、レイヤー編集、Library、URL（NDEF）書き込み、内蔵パターン表示に対応し、iPhone実機とv5基板で動作を確認しています（4階調表示は未対応）。
- 配布バイナリ（App Store / TestFlight）は提供していません。Core NFCを有効にしたアプリを実機で署名・実行するには`Near Field Communication Tag Reading`のCapabilityが必要で、無料のPersonal Teamでは利用できず、Apple Developer Programへの加入が必要です。そのため利用にはXcodeで自分でビルドしてください。
- 構成や実装メモは[iOSアプリの構成・実装メモ](iOS_development.md)を参照してください。
- 改善のPull Requestを歓迎します。実装・実機検証の共有は[https://tokumaru.work](https://tokumaru.work)からもご連絡いただけます。

### 1枚あたりの原価は？いくらで売るの？

- 部品の調達や製品の仕様次第ですが、30枚量産すると1枚あたり2500~3000円超えとなります。
  - たくさん発注すれば安くなるので、大量生産すれば2000~2500円くらいを狙えると考えています。
- それに自分の開発に使う道具の調達や時間を入れると、5000円くらいで売るのが妥当かなと考えています。

## ライセンス

このリポジトリで独自に作成したハードウェア設計、製造データ、ファームウェア、Android/iOSアプリ、文書は[MIT License](LICENSE)で提供します。自由に利用・改変・再配布できますが、著作権表示とライセンス表示を保持してください。

STM32Cube/CMSISやMaterial Symbolsなどの第三者著作物には、それぞれのライセンスが適用されます。詳細は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)を確認してください。
