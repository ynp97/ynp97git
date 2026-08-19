---
種別: 設計図 / DS作業票（実装前）
作成日: 2026-07-31
更新日: 2026-07-31
役割: [[🧩 アプリ開発状況（AI共通）]] U節の設計図。既存実装（Swift + ScreenCaptureKit）を ds-apps/ds/screen-recorder へ正しく引き継ぐための作業票の元になる。
---

# 🧩 スクリーンレコーダー 設計図（DS作業票）

## 0. この設計図の使い方（実装者へ）

- **作り直す理由はリポジトリ・手続きの問題だけ。機能・実装方針は変更しない。** 既存コードにない機能を憶測で足さない。
- **完了条件は「コードが書けた」ではなく、`.app`として起動し、実際に録画→停止→ファイルが再生できることまで実機確認する。** 過去にこのアプリは「Saved:」と無条件表示していたのに実は0バイトだった失敗があるので、成功表示を鵜呑みにせず毎回サイズ・再生を確認する。
- 既存 `main.swift` のコメントに残っている過去の失敗（idle/blankフレーム・偶数解像度・0バイトファイル）の教訓は消さない。理由が書いてあるコードを「読みにくいから」で削らない。

---

## 1. 位置づけ

- 既存実装: `アプリ本体/screen-recorder/Sources/ScreenRecorder/main.swift`、`Package.swift`。動作する完成度の高いコード（後述§2）。
- **作り直す理由（2026-07-31 本人確定）**: リポジトリ・手続きの問題だけ。旧 `ynp97apps15/screen-recorder` は、別リポジトリで公開設定・作業票なしで作られたガバナンス上の問題があった（[[ds-apps-single-repo-rule]]、[[ds-instruction-loophole-closing]] 参照）。**技術内容はそのまま踏襲する。**
- **用途（2026-07-31確定）**: 主に会議の**議事録作成**用の下地録画。OBSは煩雑なので使わない。**シンプルさを壊さない。**

---

## 2. 現状の実装（そのまま維持する設計）

- SwiftUI + ScreenCaptureKit + AVFoundation + AppKit。`Package.swift`: `swift-tools-version: 6.0`、`macOS(.v14)`、`executableTarget`。
- **UI**: 320×280固定ウインドウ、タイトルバー非表示（`.hiddenTitleBar`）。ボタン1つのみ（未録画＝`record.circle`青／録画中＝`stop.fill`赤／権限要＝「Open Settings」橙）。下にステータステキスト。録画後は「Show in Finder」リンクを表示。
- **キャプチャ**: `SCShareableContent.current` から最初のディスプレイを取得。解像度は偶数へ丸める（H.264の制約。奇数高さだとエンコーダが即失敗し0バイトファイルの原因になるため）。`SCStreamConfiguration`: `capturesAudio=true`、`sampleRate=48000`、`channelCount=2`、`minimumFrameInterval=1/30秒`（30fps）、`showsCursor=true`、`queueDepth=8`、`pixelFormat=420YpCbCr8BiPlanarVideoRange`。
- **書き出し**: `AVAssetWriter`、`.mov`コンテナ。映像＝H.264、平均ビットレート6Mbps。音声＝AAC、48kHz/2ch/128kbps。
- **フレーム処理（`Engine`クラス）**: ScreenCaptureKitが出す`.idle`/`.blank`フレーム（画面に変化がない時に画像バッファを持たずに来る）は除外し、`.complete`フレームのみ書き込む。除外しないと`AVAssetWriter`が`-16122`で失敗し出力が0バイトになる。セッション開始は必ず**最初の映像フレーム**に固定する（音声フレームに固定すると壊れる）。書き込み失敗を検知したら`onFailure`で最初のエラーだけ報告する。
- **停止処理**: `stopCapture` → `markAsFinished` → `finishWriting`。**完了状態・映像フレーム数>0・ファイルサイズ>0の3つを確認してから初めて「Saved」と表示する。** 条件を満たさない場合はファイルを削除し「Failed: 理由」を表示する（旧版が無条件で「Saved:」と表示し失敗を隠していた反省がコードコメントに残っている。この検証は削除しない）。
- **出力先**: `~/Desktop/ScreenRecordings/Screen yyyy-MM-dd HH.mm.ss.mov`
- **権限**: `SCStreamErrorDomain`の`-3801`を検知したら「Open Settings」ボタンで画面収録のプライバシー設定（`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`）を開く。

---

## 3. 音声設計の注記（機能追加ではなく運用メモ）

- `capturesAudio=true`は**システム／アプリ音声のみ**を拾う。**マイク入力（本人の肉声）は別経路**であり、このアプリはマイクを録らない。
- 対面会議で自分の発話も議事録に残したい場合、**アプリにマイク入力コードを足すのではなく**、macOS標準の「Audio MIDI設定」で **Multi-Output Device / Aggregate Device** を組み、マイクとシステム出力を、**既にインストール済みのBlackHole**へ合流させてから録画する運用でカバーする（症状を直す前に上位経路を確認する原則どおり、アプリ側のコード変更より先に既存ツールでの解決を優先）。
  - この運用手順化（Audio MIDI設定の具体的な組み方）は、実際に必要になった時点で別途文書化する。今回のアプリ実装のスコープには含めない。
- オンライン会議（Zoom/Meet等）は相手の声がシステム音声側に乗るため、現状の`capturesAudio`だけで議事録用途として成立するケースが多い。

---

## 4. リポジトリ・手続き（今回作り直す本体）

- **正**: `ynp97/ds-apps` の `ds/screen-recorder` ブランチのみ。**アプリごとに別リポジトリを作らない。**
- **現状（2026-07-30時点）**: `ds/screen-recorder`ブランチへのpushと`apps/screen-recorder/`一式は完了済み。`docs/作業票/screen-recorder-移設.md`の作成と旧リポジトリのPrivate化を再指示済みで、結果は検証待ち（本人方針＝次回のDS作業で指示を額面通り実行するかを観察してから、追加の手直しが要るか判断する。毎回掘り下げて修正を重ねる運用はしない）。
- 指示は「〜と書かない」ではなく「**〜というファイルが存在しないpushを禁止する**」の形で、ファイルの存在自体を縛る（[[ds-instruction-loophole-closing]]）。
- 可視性変更は「**Private**」の一択を明記し、archiveなど「近い効果に見える代替手段」への勝手な置き換えを禁じる。

---

## 5. 完了条件

- [ ] `ds/screen-recorder`ブランチが`ynp97/ds-apps`にpushされている
- [ ] `apps/screen-recorder/`にソース一式（`Sources/`、`Package.swift`、`build.sh`、`Info.plist`、`AppIcon.icns`等）が入っている
- [ ] `docs/作業票/screen-recorder-移設.md`に実際のビルドコマンドと出力がそのまま貼られている（「未ビルド」のままpushしない）
- [ ] C層レビュー実施済み（実装したセッションでの自己検品ではない。または「急ぎ指示により省略」と明記）
- [ ] `ynp97apps15/screen-recorder`がPrivateになっている（archiveでは不可）
- [ ] `.app`として起動し、録画→停止→`.mov`ファイルが実際に再生できることを実機確認済み

---

## 6. 未確定・要確認

| 項目 | 状態 |
| --- | --- |
| マイク入力の別途対応要否 | 保留（必要になったらBlackHole/Aggregate Device運用を別途文書化。今回は実装しない） |
| ウインドウ単位の録画（画面全体以外） | 未実装・今回スコープ外（現状は最初のディスプレイ全体固定） |
| 複数ディスプレイ時の選択UI | 未実装・今回スコープ外 |

**実装中に新たな判断が必要になったら、埋めずに止めて本人へ聞くこと（§0）。**

---

## 7. 次の一手

1. この設計図を`ds-apps/docs/`へ配置し、DSへ一行指示で伝える（既存の確立された型：①`docs/`へ置く → ②実際にコミットされたことを確認する → ③DSへ「`ds-apps`をpullして`docs/○○.md`を読んで」の一行だけ伝える）。
2. 2026-07-30の残作業（作業票・Private化）の実施結果を検証する。
3. [[🧩 アプリ開発状況（AI共通）]] U節へ登録する。

---

*関連: [[🧩 アプリ開発状況（AI共通）]] ｜ [[ds-apps-single-repo-rule]] ｜ [[ds-instruction-loophole-closing]] ｜ `ds-apps配置用/15インチへの指示_screen-recorder移設.md`*
