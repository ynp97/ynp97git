---
種別: アプリ単体引き継ぎ
分割元: 🧩 アプリ開発状況（AI共通）.md（2026-07-31に分割。**本文は一字も変えていない**）
役割: このアプリだけを最小文脈で再開するためのファイル。索引は [[🧩 アプリ開発状況（AI共通）]]。
---

# E. 出席簿アプリ

### E. 出席簿アプリ

- 記録: [[出席簿アプリ改善ログ_2026-06-20]]
- 種別: 学習施設用の出席簿 / 月次レポート作成アプリ
- Git管理コピー: `アプリ本体/出席簿`
- 現在の実行配置: `/Applications/出席簿.app`
- 移設元: `/Users/yoshiakinagumo/Documents/Codex/2026-06-03/7/outputs`
- HTML本体: `アプリ本体/出席簿/attendance_form_report.html`
- アプリバンドル: `/Applications/出席簿.app`（Vault内の重複 `出席簿.app` は混乱防止のため削除済み）
- 状態: 実用試作あり。ただし保存の信頼性が最優先課題。
- 2026-06-30配線（重要）: ドックの `/Applications/出席簿.app` は内部Pythonサーバー(8765)を立て、`Contents/Resources/attendance_form_report.html`（バンドル内コピー）を開く構造。`/Applications` からVault正本へのシンボリックリンクは実アプリ起動時に権限/404化することがあったため、**バンドル内HTMLへ最新版を実コピーする方式**に変更。反映用は `アプリ本体/出席簿/出席簿_最新を反映.command`（ダブルクリックで `/Applications/出席簿.app` へ正本HTMLをコピーし、launchを更新してサーバー再起動）。古い混乱元だったVault内 `出席簿.app` と旧Codex作業フォルダ `Documents/Codex/2026-06-03/7/outputs` の出席簿HTML/.appは削除済み。以後、正本 `アプリ本体/出席簿/attendance_form_report.html` を直したらこのcommandで反映する。保存は同サーバーの `/api/data` 経由で `~/Library/Application Support/出席簿/attendance_data.json` に実ファイル保存される（デスクトップにファイルは作らない）。
- 2026-06-30追加: ①レポート出力（A4プレビュー/印刷）の一番上に挨拶文を表示できるようにした。レポート欄に編集用textarea「挨拶文（レポートの一番上に表示）」を追加、入力即 `state.reportGreeting` に自動保存。空なら非表示（`hidden`属性＋`:not([hidden])`で制御）、編集欄は印刷/プレビューでは非表示。②保存をデスクトップにファイルを作らない内部・自動保存へ変更。topbarの「全データ保存」は `exportBackup`（ファイルDL）→ `saveAllInternal`（localStorage保存＋status表示のみ）に変更。手動のファイル書き出しは名簿管理画面の「バックアップを書き出す（ファイル）」に残置。さらに `visibilitychange(hidden)`/`pagehide`/`beforeunload` で `save()` を呼ぶ安全網を追加し、画面切替・終了でデータが失われないようにした。node構文チェック済み。実体は `アプリ本体/出席簿/attendance_form_report.html`。
- 2026-07-15追加: デスクトップにJSONが増えない自動世代バックアップを実装。正本サーバーを `アプリ本体/出席簿/server.py` とし、通常データを `~/Library/Application Support/出席簿/attendance_data.json`、日付ごとの自動バックアップを同 `Backups/attendance_backup_YYYY-MM-DD.json` にアトミック保存。同日は1ファイルを更新し、90日分を保持する。実アプリへ反映済み。起動後にGET/POST 200と今日分のバックアップ生成を確認。6/30の既存4ファイルは、有用な2種類（詳細26件版／最多37件版）を `Backups/legacy_*.json` として保護。現行データ14件と内容が異なるため、自動統合・復元は行っていない。

目的:
- 学習施設ごとに生徒を登録し、日ごとの学習内容・活動内容を記録する。
- 月ごとのA4印刷用レポートを作る。

実装済みの主な機能:
- 名簿管理
- 学習施設ごとの生徒登録
- 月別一覧表示
- A4プレビューと印刷
- 科目プルダウンと複数科目入力
- 活動内容選択
- 全データ保存

現在の課題:
- `localStorage` だけでは、開くURLやブラウザが変わると保存領域が分かれる。
- Pythonサーバー経由の実ファイル保存は試したが、保存先権限で止まった。
- データ復旧を優先し、保存方式を安定させてからUI改善へ進む必要がある。

次に見ること:
- `attendance_backup_2026-06-05 (1).json` を安全に保管する。
- 保存先を `~/Library/Application Support/出席簿/attendance_data.json` に変更する。
- 起動時読み込み、登録ごとの自動保存、最終保存時刻表示を確認する。

注意:
- データ復旧より前に、アプリ配置や保存方式を大きく変えない。
- 実データやバックアップJSONは個人情報を含む可能性があるため、Git管理しない。
- 今後は `アプリ本体/出席簿` をGit管理上の正とする。

---
