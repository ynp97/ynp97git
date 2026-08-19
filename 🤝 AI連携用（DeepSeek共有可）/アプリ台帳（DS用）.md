# アプリ台帳（DS用）

あなた（OpenClaw/DeepSeek）のための開発台帳。原本はユーザーの記録庫にあり、これはその技術編集版。**節の記号（C〜R）は原本と共通**なので、「C節のシランガナ」と言えば他のAIにも通じる。

> [!important] 台帳の使い方（毎セッションの儀式）
> 1. **セッション開始時にこの台帳を読む**（対象アプリの節だけでよい）。
> 2. アプリを作った・直したら、**セッション終了時に該当節の「DS作業メモ」へ1〜2行追記**する（日付＋やったこと＋未解決）。過去の記述は消さない。
> 3. **新しいアプリを作ったら「新規（未採番）」として末尾に節を足す**。記号の採番は原本側（Claude）が行う。
> 4. この台帳の同期はClaudeが担当。原本の更新はここに反映され、あなたの追記は検品後に原本へ反映される。
> 5. A・B節は原本にのみ存在する（非共有）。欠番は誤りではない。

## 技術傾向（このユーザーの定番構成）

- 基本は**単体HTMLアプリ**(HTML+CSS+JS一体、サーバーなし、ブラウザで直接開く)。
- 保存は localStorage ＋ JSONバックアップ書き出し/復元。
- localStorageのプロファイル分岐事故を防ぐため、Chrome起動は `--profile-directory=Default` ＋ URLパラメータ（`?app=1` 等）固定のランチャー（.app）を使うことが多い。
- 長期運用のデータは `~/Library/Application Support/<アプリ名>/` へのJSON実ファイル保存に移行する方針。
- ネイティブはSwiftUI（iOS/macOS）。iOSはVision(OCR)+AVFoundation+SQLiteの経験あり。
- **実データ（出席・住所録・日記など個人情報）はこのワークスペースに持ち込まない。コードの相談のみ。**

## アプリ一覧（記号は原本と共通）

### C. シランガナ（iPhoneアプリ / SwiftUI）
カメラで読めない漢字を撮影し、読み仮名と意味を表示するOCRアプリ。SwiftUI + AVFoundation + Vision + SQLite辞書。縦書き対応（縦長画像をN分割して横並べ替え）、複数の画像前処理パターン、辞書照合の候補順位づけ、診断パネルあり。課題は薄い文字の認識精度と、辞書照合で長い誤候補が短い正解に勝つスコアリング問題（`ReadingDictionary.findBestReading`）。App Store公開を目指している。
- **コードの場所: `~/openclaw-apps/shirangana/`**（2026-07-20にClaudeが正本から配置。辞書JMdict.sqlite込み・機密スキャン済み）。検証・修正はここで行い、修正はファイルに直接反映してよい。
- **実機ビルド手順（「iPhoneで試そう」と言われたらこれ）**: ①iPhoneの接続をユーザーに確認 ②`xcodebuild -project ~/openclaw-apps/shirangana/Shirangana.xcodeproj -scheme Shirangana -destination 'platform=iOS,name=iphone15proMAX' -allowProvisioningUpdates build` ③`xcrun devicectl device install app` でインストール（端末名 `iphone15proMAX`、Bundle ID `com.yoshiakinagumo.shirangana`）。ビルドエラー時は推測より先にエラーメッセージ全文を確認。署名は `-allowProvisioningUpdates` で自動解決される（開発者信頼は設定済み）。
- DS作業メモ:
  - 2026-07-20 「長い誤候補が短い正解に勝つ」スコアリング問題を修正。compound baseScoreを9,850/6,200→7,000/4,200、exact full-matchを10,000→12,000に変更。コメントも刷新。

### D. Graveyard of the Black Nebula（単体HTML）
自分用の音源アーカイブ。音源/画像の取り込み、ブラウザ内DB保存、再生、リネーム、メモ、検索、JSON入出力。課題は大量ファイル取り込みの速度と公開用ビュー。
- DS作業メモ:

### E. 出席簿アプリ（単体HTML＋ランチャー.app）※コード相談のみ
学習施設用の出席記録・月次A4レポート印刷。保存はローカルサーバー経由で `~/Library/Application Support/` にJSON実ファイル保存＋日次世代バックアップ（90日保持）。**実データは持ち込み禁止。**
- DS作業メモ:

### F. eBay Record Lister（単体HTML）
レコードのeBay出品管理。Discogs取込、写真バーコード検出、送料表による送料自動計算、損益分岐点計算、英語出品文の生成、出品用コピペパック、CSV/JSON出力。
- DS作業メモ:

### G. TODOインボックス（SwiftUI Macアプリ）
思いつきTODOの受け皿。付箋タグ、期限、EventKitカレンダー追加、Markdown自動書き出し。
- DS作業メモ:

### H. レコード査定パイプライン（Python CLI）
写真フォルダ→ローカルVLM（LM Studio / Qwen3-VL）→Discogs API照合→査定表（MD/CSV/JSON）自動生成。
- DS作業メモ:

### I. ポケカ戦績アプリ（SwiftUI / SQLite）
対戦の勝敗・先攻後攻・デッキを記録し、相性表・勝率を集計。
- DS作業メモ:

### J. 資料請求ラベル管理（単体HTML＋ランチャー.app）※コード相談のみ
資料請求メール/Excelを取り込み、条件抽出して A4 24面ラベル（66×33.9mm, 3×8）にCSS実寸で印刷。送付済み台帳による二重発送防止（氏名＋郵便番号で同一人物判定、表記ゆれ正規化）。**実データは持ち込み禁止。**
- DS作業メモ:

### K. やりたいことソーター（単体HTML / 試作）
やりたいことの雑投入→分野/時期/大きさ/強さで整理、まとめ/分解、Markdown書き出し。
- DS作業メモ:

### L. 三本立て毎日TODO（単体HTML / 現役）
3プロジェクトの日次TODO実行台帳。日めくり表示、週表示、AI用コピー、JSONバックアップ、カレンダー同期（launchd常駐のローカルPythonサーバー `127.0.0.1:8769` がiCal URLをJSON化）。
- DS作業メモ:

### M. 音楽制作ルーレット（単体HTML）
毎日1本固定＋1本ルーレット抽選で音楽制作タスクを決める。工程の順番進行、30分タイマー、完了履歴。
- DS作業メモ:

### N. PTCGL ポケカコーチ（単体HTML / v0.1）
ポケモンカードのオンライン対戦ログ（英語）を解析し、試合要約と改善点を返す。
- DS作業メモ:

### O. 自分用日記アプリ（構想中 / Mac先行）※ダミーデータのみ
日記データ（Markdown+写真）の閲覧・検索アプリを作る予定。タイムライン、全文検索、写真表示、「この日の記憶」機能を構想。**日記の実データは持ち込まない。まずダミーデータで試作する。**
- DS作業メモ:

### P. OpenClaw + DeepSeek 開発環境（あなた自身の実行基盤）
OpenClaw＋DeepSeek API。ワークスペースは `~/openclaw-apps`。規則は `AGENTS.md`。
- DS作業メモ:

### Q. tako-shooter（タコ VS イカ - 貝殻シューティング / 単体HTML）
DS製第1号。canvasシューティングゲーム、タッチ・マウス対応、完全自己完結。2026-07-20に検品済み・正本へ受け取り済み。
- DS作業メモ: 2026-07-19 初版生成。

### R. ZatsuTodo（雑TODO / SwiftUI Macアプリ）
通常のMacウインドウで動く雑TODO投入アプリ。現役の正本はVault側 `アプリ本体/ZatsuTodo`。DS作業用コピーは `~/openclaw-apps/ZatsuTodo` だが、正本へ戻す前に必ず検品する。
- **DS作業用コード**: `~/openclaw-apps/ZatsuTodo/`
- **禁止事項**: LaunchAgentへ `KeepAlive` を戻さない。浮遊NSPanel、rootView差し替え、LazyVStack、onHover方式へ戻さない。
- DS作業メモ:
  - 2026-07-19 thought-to-todo初版生成。
  - 2026-07-21 SwiftUI Mac版へ全面リメイク。
  - 2026-07-27 フリーズと強制終了不能をCodexが修正。原因はホバー時の11タグ全展開によるレイアウト反復と、LaunchAgent `KeepAlive=true` による強制終了後の即再起動。1.1/build 2でクリック式タグメニュー、通常アプリ化、画面内終了、⌘Q、JSON二重保存へ変更。実機で終了後に自動再起動しないことまで確認済み。
  - 2026-07-27 1.1でも即フリーズ再発。macOSハング記録で `LazySubviewPlacements`＋`PointerRegionUpdater` のSwiftUI更新ループを確認。1.2/build 3で旧浮遊画面を全面廃棄し、通常WindowGroup＋ScrollView/VStack＋ホバーなしへ作り直した。タグ12回、表示5回、スクロール10回、追加削除後もCPU 0%・内部採取正常。

## 新規（未採番）

> 新しく作ったアプリはここに「### 新規: <アプリ名>」で追記。採番は原本側が行う。
