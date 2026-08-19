# 作業票 — screen-recorder：画面収録の許可が定着しない問題の修正

- 日付: 2026-07-31
- 実施: 本人（15インチMac / DSは経由していない）
- ブランチ: `ds/screen-recorder`
- 対象: `apps/screen-recorder/`

## 背景・症状

`.app` を起動して録画ボタンを押すと `Screen recording permission needed` になり録画できない。システム設定の「画面収録とシステムオーディオ録音」で許可を与えても、**使う瞬間に無効化され、一覧から項目ごと消える**。何度追加しても同じ。7月30日にDSがビルドした直後は一度動いたが、以降まったく動かなくなっていた。

## 原因（3つ重なっていた。どれか1つを直しても解決しない）

### ① `build.sh` が指定していた署名証明書が存在しなかった

旧 `build.sh` は `CERT="D60BB3F755BA4993EEDA2DCFF3905F3995CB212C"` を指定していたが、このIDは `security find-identity -v -p codesigning` の一覧に無い（失効か削除）。結果、署名が実質効かず、出来上がった `.app` は次の状態だった。

```
flags=0x20002(adhoc,linker-signed)
Identifier=ScreenRecorder            ← Info.plist の com.screenrecorder.app ではない
Info.plist=not bound
Sealed Resources=none
→ code has no resources but signature indicates they must be present（検証失敗）
```

macOSは画面収録の許可を**アプリの bundle identifier に結びつけて保存**する。それが署名に結びついていないため、許可を与えても本人確認に失敗し、記録ごと破棄されていた。

### ② アプリに許可を要求する処理が無かった

`main.swift` は `SCShareableContent.current` を呼ぶだけで、拒否されると `-3801`（userDeclined）を受けて「設定を開いて」と表示するだけだった。**`CGRequestScreenCaptureAccess()` を呼んでいないため、macOSは許可ダイアログを出さない。** ユーザーは手作業で登録するしかなく、その手動登録は①のせいで定着しない。

### ③ ad-hoc署名は、ビルドのたびに指紋が変わる

`codesign --sign -` は署名の指紋をアプリの中身から作る。ソースを1文字変えれば指紋が変わり、macOSは別アプリとみなして許可を無効化する。**ビルドのたびに許可がリセットされる。**

実測:

| テスト | 結果 |
|---|---|
| ソース無変更で再ビルド（キャッシュ、0.15s） | 許可は生きたまま録画できた |
| ソース変更ありで再ビルド（実コンパイル、2.05s） | 許可が外れ `permission needed` に戻った |

## 変更内容

### `Sources/ScreenRecorder/main.swift`

- `import CoreGraphics` を追加。
- `start()` の冒頭で `CGPreflightScreenCaptureAccess()` → `CGRequestScreenCaptureAccess()` を呼び、OS本来の許可ダイアログを出させる。理由をコメントで残した。
- 起動時の表示を `Ready v1.2` に変更（動いているのが新しいビルドか、古いプロセスの残りかを一目で判別するため。実際に古いプロセスが残っていてテストを1回無駄にした）。

**注意**: このブランチにあった `main.swift` は179行の旧版だった（移設コミット `e7046ca` のまま、以後変更なし）。本作業で入れた375行版には、旧版に無い安全策 ── idle/blankフレームの除外、H.264のための偶数解像度への丸め、書き込み失敗と0バイトファイルの検出・削除 ── が含まれている。**旧版を上書きしている。** 旧版側に失われる変更が無いことは `git log` で確認済み（移設コミット1件のみ）。

### `build.sh`

- 署名IDの**直書きをやめ**、`security find-identity -v -p codesigning` から有効な証明書を自動で拾うようにした。存在しないIDを指定したまま静かにad-hocへ落ちる事故を防ぐため。
- 証明書が1つも無ければ**ビルドを失敗させる**。
- `--deep` を外し `--identifier com.screenrecorder.app` を明示（Info.plist を署名に結びつけるため）。
- ビルド手順に `codesign --verify --strict` を組み込み、**署名が壊れていればビルドが通らない**ようにした。
- 出力先を `~/Desktop` → `/Applications` に一本化（2つ並存してどちらを見ているか分からなくなったため）。

### `Info.plist`

- `CFBundleIconFile = AppIcon` を追加。これが無いと `build.sh` が `AppIcon.icns` をコピーしていてもアイコンが表示されず、Finderでもシステム設定の許可一覧でも白紙になり、探しにくい。
- バージョンを `1.1` / `3` へ。

## ビルド結果（実出力）

```
$ ./build.sh
[1/1] Planning build
Building for production...
[5/5] Linking ScreenRecorder
Build of product 'ScreenRecorder' complete! (2.05s)
署名に使う証明書: Apple Development: darkstarman2019@gmail.com (K74T5Z7BG6)
/Applications/ScreenRec.app: replacing existing signature
/Applications/ScreenRec.app: valid on disk
/Applications/ScreenRec.app: satisfies its Designated Requirement
Identifier=com.screenrecorder.app
Authority=Apple Development: darkstarman2019@gmail.com (K74T5Z7BG6)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
Info.plist entries=9
TeamIdentifier=UJV34TVHWC
Sealed Resources version=2 rules=13 files=1
✅ /Applications/ScreenRec.app
```

## 動作確認（実機・実出力）

1. `tccutil reset ScreenCapture com.screenrecorder.app` で許可の記録を消す
2. `.app` を起動 → 録画ボタン → macOSの窓が出る → ［システム設定を開く］→ 一覧の `ScreenRec.app` をオン → 終了して再度開く
3. 録画 → 停止 → `Saved Screen 2026-07-31 18.29.26.mov — 223 frames, 2.7 MB`
4. **ソースを書き換えて（`Ready v1.1` → `v1.2`）再ビルド**
5. **許可を入れ直さずに**録画 → 停止 → `Saved Screen 2026-07-31 18.31.21.mov — 555 frames, 8.3 MB`

**5 が通ったことが本作業の合格条件。** 修正前は 4 の時点で許可が外れていた。

映像・音声とも再生を本人が確認済み（`Saved Screen 2026-07-31 18.07.33.mov — 879 frames, 14.4 MB` で確認）。

## 懸念・相談

- **C層（DS↔DS相互チェック）は未実施。** 本人が直接作業したため。必要なら別セッションで差分レビューを回す。
- **署名に使っている `Apple Development` 証明書は、おおむね1年で失効する。** 失効したら `security find-identity -v -p codesigning` で現行を確認する。`build.sh` は自動で拾うので書き換えは不要だが、**証明書が変われば許可は一度外れる**ので入れ直しが必要。
- **このアプリはシステム音声しか録らない。マイク（自分の肉声）は入らない。** 会議の議事録用途では相手の声は残るが自分の発言が残らない。未解決。
- macOS Sequoia 以降は画面収録の許可を定期的に再確認してくる（「システムプライベートウインドウピッカーをバイパスして…」の窓）。壊れたわけではないので「許可」でよい。

## ★踏んではいけない地雷（消さないこと）

- **画面収録の許可ダイアログには「許可」ボタンが無い。** macOSの仕様で必ず「システム設定を開く」へ飛ぶ。「許可を押してください」という案内は誤り。
- **拒否の記録が残っていると `CGRequestScreenCaptureAccess()` は何も出さずに false を返す。** 詰まったら `tccutil reset ScreenCapture com.screenrecorder.app`。
- **アプリを更新したら、必ず古いプロセスを終了してから起動し直す。** 起動しっぱなしだと古いバイナリが動き続け、テストが無駄になる。
- **ターミナルからバイナリを直接起動しない。** 許可の主体がずれる。実機テストは必ず `.app` を起動して行う。
- **`build.sh` の署名IDを直書きに戻さない。** 存在しないIDでも静かにad-hocへ落ちて、原因が見えなくなる。
