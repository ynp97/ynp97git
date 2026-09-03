---
種別: アプリ単体引き継ぎ
分割元: 🧩 アプリ開発状況（AI共通）.md（2026-07-31に分割。**本文は一字も変えていない**）
役割: このアプリだけを最小文脈で再開するためのファイル。索引は [[🧩 アプリ開発状況（AI共通）]]。
---

# I. ポケカ戦績アプリ

### I. ポケカ戦績アプリ（SwiftUIネイティブ v0.1）

- 実体: `資料/Desktop収集/v1_17_swiftui_cli_build_pokeca_records`（＋ `アーカイブ/デスクトップ収集/Desktop/` に同名コピー）
- 種別: ポケモンカード戦績トラッカー（SwiftUI / SQLite、HTMLラッパーではないネイティブ）
- 開くもの: フォルダ内 `Package.swift` をXcodeで開く→My Mac→Run。保存先 `~/Library/Application Support/PokecaRecordsSwiftUI/records.sqlite3`
- 状態: v0.1。**2026-06-23まで本台帳に未登録だった**ものを精査して登録。
- 実装済み: 戦績入力／日時記録／勝敗・先攻後攻・初手のボタン選択／デッキ選択／戦績一覧／編集・複製・削除／相性表／実勝率・補正勝率・信頼度・最低試合数フィルター／デッキ画像登録／JSON・CSV入出力。
- 関連構想: [[ポケカ]]（時間投下と生産性のバランス問題、「いい方向にアジャスト」方針）。
- 次に見ること: 物販（eBay・ポケカ転売）と戦績の役割整理。Vault外の元実体(Codex)と`アプリ本体/`の一本化。

#### 2026-08-31 このPCへ復元

- BENJAMINの`_移行データ/∕Users∕yoshiakinagumo∕Desktop/AI関係/v1_17_swiftui_cli_build_pokeca_records`に、v1.17の完成`.app`・`Package.swift`・`Sources/PokecaRecords/main.swift`・アイコン・ビルド手順が揃った実体を発見。
- 正本をVault内の`アプリ本体/pokeca-records/`へ回収した（`.build`は除外）。
- 完成版を`/Applications/PokecaRecords_v1.17.app`へインストールし、起動後に`~/Library/Application Support/PokecaRecordsSwiftUI/records.sqlite3`が生成されることを確認。現在の戦績件数は0件。
- BENJAMIN内に過去の`records.sqlite3`は見つからなかった。アプリ本体とソースは復元済みだが、過去戦績は未復元。
- 原因確定: 2026-08-15の`scripts/migrate_app_data.sh`はApplication Supportをアプリごとに個別指定しており、`PokecaRecordsSwiftUI`が対象から漏れていた。BENJAMINのゴミ箱、JSON/CSV書き出し、ポケカ関連名、v1.17固有のJSONキーでも再検索したが、過去戦績はなかった。復元元は旧M5の`~/Library/Application Support/PokecaRecordsSwiftUI/records.sqlite3`か、M5を含むTime Machineに限られる。
- 初回の`swift build -c release`はユーザーキャッシュの権限とSwiftPM内部sandboxで失敗し、途中でSwift/SDK不一致エラーも出た。2026-09-01、モジュールキャッシュとscratch pathを`/private/tmp`へ逃がし、SwiftPMを制限外で実行するとreleaseビルドが成功。現在はこのPCで再ビルド可能と確認済み。

#### 2026-09-01 v1.18（複数Mac用自動バックアップ）

- BENJAMINから回収したv1.17を土台に、`アプリ本体/pokeca-records/`をv1.18へ更新。`/Applications/PokecaRecords_v1.18.app`へ導入済み。v1.17は残した。
- 戦績・デッキの保存、編集、削除、アプリ起動時にJSONを自動生成。Mac内の`~/Library/Application Support/PokecaRecordsSwiftUI/Backups/<Mac名>/`と、iCloud Driveが有効なら`iCloud Drive/ポケカ戦績バックアップ/<Mac名>/`の両方へ保存。
- Macごとにフォルダを分け、`pokeca_records_latest.json`と日付付きJSON（30件保持）を作る。SQLite本体をiCloudへ置かず、同時編集による破損を避けた。
- バックアップ画面に「今すぐバックアップ」「フォルダを開く」「自動バックアップから復元」を追加。復元前の自動保護、JSONの先行検証、SQLiteトランザクション／失敗時ロールバックも実装。
- v1.17のJSON復元で、ID付きデッキが新規挿入されず、画像・代表カード情報が落ちる可能性があった不具合も修正。
- 検証: `swiftc -frontend -parse`・型検査・releaseビルド成功、アプリ署名検証、実起動を確認。一時戦績1件を入れ、Mac内とiCloudのJSONがともに1件・SHA-256一致となることを確認。検査後は元の0件へ戻し、SQLite=`integrity_check: ok`、両JSON=0件・SHA-256一致を再確認した。
- M5でv1.18を起動すると、旧M5に残る戦績がそのMac専用フォルダへ即時バックアップされる。その後、15インチAirのv1.18からM5側のJSONを選べば復元できる。
- **実機復元完了（2026-09-01）**: M5でv1.18を起動し、画面に`iCloud Drive＋Mac内・197件（起動時保護）`を確認。iCloud Driveの`ポケカ戦績バックアップ/MacBook Pro/`に`pokeca_records_latest.json`と`pokeca_records_2026-09-01.json`が生成された。15インチAir側の「自動バックアップから復元」で`MacBook Pro/pokeca_records_latest.json`を選び、**197件の復元を画面で確認した。**

#### 2026-09-01 v1.19（PTCGLレート）

- v1.18の画面構成を保ち、入力順を`自分のデッキ → 相手のデッキ → レート → 勝敗 → 先/後`へ変更。一覧も`相手のデッキ → レート → 勝敗 → 先/後`の順にした。
- レートは編集・複製・日別表示・検索・JSONバックアップ・CSV書き出しへ反映。SQLiteは起動時に`rating`列を自動追加し、旧197件は空欄のまま保持する。v1.18以前のJSONは`rating`がなくても空欄として復元できる。
- `アプリ本体/pokeca-records/PokecaRecords_v1.19.app`を作成し、`/Applications/PokecaRecords_v1.19.app`へ導入。v1.18はロールバック用に残した。
- 検証: 型検査・releaseビルド・署名検証に成功。実データを退避後、旧DBをv1.19で自動移行し、SQLite=`integrity_check: ok`・197件・`rating`列1本を確認。一時テスト戦績へレート`1234`を入れ、SQLiteとMac内JSONで保存を確認した。その後、退避DBへ戻して再起動し、SQLite=197件・テスト戦績0件・Mac内JSON=197件（全件に`rating`キー）を再確認した。
- **iCloud最終確認完了**: このAirでv1.19のiCloud Driveアクセスを許可して再起動。Mac内・iCloudの`pokeca_records_latest.json`はいずれも197件、全197件に`rating`キーあり、一時テスト戦績0件、SHA-256も一致した。SQLiteも`integrity_check: ok`・197件を再確認済み。


#### 2026-09-03 v1.20（時刻スタンプの修正）

**症状**: 戦績の時刻が実際の対戦時刻とずれる。

**原因（コードで確定）**: `EntryView` の `@State private var playedAt = Date()` が、入力画面を開いた瞬間の1回しか評価されず、`save()` はその値をそのまま書いていた。値が更新されるのは「入力画面を開き直したとき」「保存成功直後の `clear()`」「『今日・現在時刻』ボタンを押したとき」だけ。つまり**記録されていたのは対戦時刻ではなく、直前の入力を終えた時刻**だった。

**実データでの裏づけ**: `pokeca_records.csv`（207件）で、まとめて入力した戦績が30〜60秒間隔で並んでいた（2026-09-02 17:47:18→17:47:52、2026-09-03 10:07:43→10:08:16、2026-07-17 08:00:00→08:00:57 ほか）。PTCGLの1試合は10〜25分なので、この間隔は対戦間隔ではなく入力作業の間隔。

**直したこと（v1.20）**
1. 日時欄に手で触っていない限り、**保存ボタンを押したその瞬間**の時刻を書く（`save()` で `Date()` を採る）。
2. 自動のときは日時欄に現在時刻を `TimelineView` で出し続ける。画面の時刻と保存される時刻が一致する。フォーム全体ではなくその1行だけが再描画されるので、入力中の欄を邪魔しない。
3. 「日時を指定する」を押すと手動モードになり、その値をそのまま使う。「今にする」で自動へ戻る。上部の「今日・現在時刻」ボタンは廃止（この2つに統合）。
4. 戦績の**編集**時は保存済みの日時を保持する（今の時刻に書き換えない）。
5. **2分以上先の未来日時は保存を拒否**して警告する。

**★踏んではいけない地雷（v1.20で塞いだが、性質を残す）**
- `fetchRecords()` の `dateFormatter.date(from: iso) ?? Date()` は、SQLiteの日時文字列が想定形式（小数秒つきISO）でないと、**その戦績を黙って「アプリを開いた時刻」に化けさせていた**。エラーも警告も出ない。v1.20で ㋐小数秒なしISOも読む ㋑それでも読めなければ `.distantPast` にして件数を警告表示、へ変更。**`?? Date()` のようなフォールバックを日時に付けない。** 壊れたデータが「今日の記録」に見えるのがいちばん危ない。
- `JSONEncoder/JSONDecoder` の `.iso8601` は**小数秒を出さない/受け付けない**。SQLite側のフォーマッタ（小数秒つき）と非対称なので、JSON経由で入った文字列を直接SQLiteへ流すコードを足さないこと。

**データ側に残っている異常（未修正・本人判断待ち）**
- 1件だけ `2027-09-02 20:24:02`（XXX2 vs メガダークライ、レート1405、PTCGL夜）と年が1つ先になっている。DatePickerで年を動かしてしまったものと推測。v1.20の未来日時チェックは今後の入力にしか効かないので、**この1件はアプリの一覧から編集して年を2026へ直す必要がある。**

**ビルド**: `build.command` をダブルクリック。v1.20から ㋐ログを `アプリ本体/pokeca-records/build_last.log`（Vault内）にも書く ㋑`/Applications` への配置まで自動でやる。v1.19の`.app`はロールバック用に残してある。

**確かめ方**: 入力画面の日時欄が秒まで動いていること。対戦を1本終えてから保存し、一覧の時刻が保存を押した時刻と一致すること。

**状態**: ソース修正済み。**ビルドと実機確認は未実施（2026-09-03時点）。**


---
