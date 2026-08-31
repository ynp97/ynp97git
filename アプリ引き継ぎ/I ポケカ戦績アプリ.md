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
- このPCで`swift build -c release`を試したが、Command Line ToolsのSwift 6.3.3とSDKのSwift 6.3.2の不一致で失敗。完成済みarm64バイナリは起動できるため、現時点の利用に支障はない。再ビルド時はCommand Line Toolsの版を揃える。

---
