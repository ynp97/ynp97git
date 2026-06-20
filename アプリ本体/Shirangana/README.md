# シランガナ 1.0

カメラの中央に漢字を写して撮影すると、読みと代表的な意味を表示する無料のiPhoneアプリです。

## 初版の機能

- 起動直後にカメラを表示
- 撮影後の写真をピンチズーム・移動
- 横書き／縦書きの選択枠を切り替え
- 中央の小さな枠内だけを日本語OCR
- 内蔵辞書から読みを検索
- 複数の読みがある場合は最大4候補を表示
- 日本語WordNetから代表的な意味を最大2件表示
- 読みの音声再生
- 画像を保存しない
- 外部通信、広告、課金、アカウント登録なし

## 技術構成

- SwiftUI
- AVFoundation
- Vision
- SQLite
- JMdict
- 日本語WordNet 1.1
- iOS 17以降、iPhone縦向き専用

## プロジェクト生成

完全版XcodeとXcodeGenをインストールした後、次を実行します。

```sh
cd work/Shirangana
xcodegen generate
open Shirangana.xcodeproj
```

XcodeでSigning Teamを選択し、実機でカメラと読み取りを確認します。

## 辞書の再生成

リポジトリ直下で次を実行します。

```sh
curl -L https://www.edrdg.org/pub/Nihongo/JMdict_e.gz -o work/JMdict_e.gz
python3 work/build_jmdict.py \
  work/JMdict_e.gz \
  work/Shirangana/Shirangana/Resources/JMdict.sqlite \
  --wordnet work/wnjpn.db
```

## 公開前に必要な作業

- Apple Developer Programへの登録
- Bundle IDとSigning Teamの確定
- 実機テスト
- App Store用スクリーンショットの撮影
- サポートURLとプライバシーポリシーURLの公開
- TestFlight配布
- App Reviewへの提出
