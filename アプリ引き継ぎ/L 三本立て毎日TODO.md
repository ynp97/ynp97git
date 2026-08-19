---
種別: アプリ単体引き継ぎ
分割元: 🧩 アプリ開発状況（AI共通）.md（2026-07-31に分割。**本文は一字も変えていない**）
役割: このアプリだけを最小文脈で再開するためのファイル。索引は [[🧩 アプリ開発状況（AI共通）]]。
---

# L. 三本立て毎日TODO

### L. 三本立て毎日TODO（単体HTML / 現役）

- 本体: `🗓 三本立て毎日TODO（アプリ）.html`
- 元計画: `🗓 三本立て毎日TODO（6月26日〜8月15日）.md`
- Dockアプリ: `/Users/yoshiakinagumo/Documents/Obsidian Vault/三本立てTODO.app`
- Dockアプリの起動実体: `三本立てTODO.app/Contents/MacOS/run`
- localStorage key: `himekuri-todo-v1` / `himekuri-last-saved-v1` / `himekuri-custom-v1`
- 状態: シランガナ / 学校事業 / eBay の日次TODO実行台帳。日めくり、全一覧、マップ、追加TODO、曜日指定、AI用コピー、JSONバックアップ/復元、右ドックの音楽制作/タスクルーレット統合まで実装済み。
- 2026-07-14ゴール可視化: フッターの「🎯 ゴール確認」から別ウインドウを開き、学校・ヤフオク・シランガナごとの8/15到達点、そこまでに行う全工程、W3〜W7の週ごとのゴールを一画面で確認できるようにした。通常の日めくり画面は増やしていない。JavaScript構文チェック済み。
- 2026-07-14同期の根本修正: 7/12のDock起動時サーバー方式でも2回連続で停止したため、`launchd` のユーザー常駐サービス `com.ynp97.threetodo-calendar`（RunAtLoad＋KeepAlive）へ刷新。Macの保護機能によりDocuments内のPythonを常駐プロセスから直接読めなかったため、設置コマンド `三本立てTODO_同期を常時自動復旧.command` が同期本体を `~/Library/Application Support/ThreeTodo/three_todo_calendar_server.py` へコピーし、`~/Library/LaunchAgents` へ登録する構成にした。意図的にサービスを再起動した前後で `127.0.0.1:8769/health` がともに応答することを確認済み。今後はDock経由で開かなくてもログイン中は自動起動し、停止しても自動復旧する。
- 2026-07-02保存先調査: Dock自体はVault内の `三本立てTODO.app` を指しており、ランチャーも正しいHTMLを開いていた。ただし中身が `open -a "Google Chrome" "$HTML"` で通常Chromeに渡していたため、保存先はアプリ固定ではなくChromeプロファイルごとの `file://` localStorageだった。Chrome履歴上、同じHTMLが `Default` / `Profile 1` / `Profile 4` で開かれており、各プロファイルに `himekuri-*` 系データが分かれて残っていた。曜日指定は `himekuri-custom-v1` の `type:"weekly"` として複数プロファイルに存在するため、起動時のChromeプロファイルが変わると「曜日指定が消えた」ように見える。
- 2026-07-12修正: カレンダー同期の「同期できませんでした。Failed to fetch」に対応。同期は `アプリ/three_todo_calendar_server.py`（`127.0.0.1:8769`、非公開iCal URL→今日以降の予定をJSON化）経由で、Failed to fetch＝このサーバーが未起動（Chromeのウインドウ復元などでDockランチャーを経由しないとサーバーが立たない）。対策①ランチャー `三本立てTODO.app/Contents/MacOS/run` にサーバー起動後の health 待ち（最大3秒）を追加、ログを追記式に変更。②Vault直下に `三本立てTODO_同期を直す.command` を新設（ダブルクリックでサーバーだけ立て直す。ウインドウは閉じなくてよい。失敗時は `/tmp/three_todo_calendar.log` 末尾を表示）。bash構文・Python構文チェック済み。同日、本人実機で「ウインドウを閉じる→Dockから開き直す→今すぐ同期」で同期成功を確認（修復.commandは使わず解決。予備として残置）。もし今後も失敗する場合はChromeのプライベートネットワークアクセス制限の可能性があるためログと合わせて要調査。
- 2026-07-02修正: `三本立てTODO.app/Contents/MacOS/run` を変更し、Chrome起動時に `--profile-directory=Default` と `--app=<三本立てTODOのfile URL>?dock=1` を指定するよう固定。調査時点で直近利用が `Default` だったため、まず最新セーブポイントを正としてDock起動を安定化した。さらにHTML側に直開きガードを追加し、`?dock=1` がない `file://` 起動では保存画面へ入らず「Dockから起動してください」を表示するようにした。起動テストでURL `file:///Users/yoshiakinagumo/Documents/Obsidian%20Vault/...TODO...html?dock=1`、タイトル `三本立て毎日TODO（6/26〜8/15）` を確認済み。Nodeで直開きガードも確認済み。

現在の課題:
- Dockからの起動は `Default` プロファイル固定にしたため、通常運用では同じセーブポイントを見る。
- HTML直開きは保存分岐防止のため停止済み。別プロファイルで同HTMLを直接開いても、`?dock=1` がなければ保存画面に入らない。
- ただし保存そのものはまだブラウザlocalStorage依存なので、長期的には実ファイル保存化が最も堅い。
- 音楽制作ドックの `todayPlan` は日付が変わると当日分へ切り替わるため、ここは仕様として内容が変わる。

次に見ること:
- しばらくDockからだけ開き、曜日指定が安定して出るか確認する。
- 必要なら `Profile 1` / `Profile 4` に残った古い曜日指定やチェックをJSONバックアップ経由で手動統合する。
- 長期修正: 出席簿アプリと同じく `~/Library/Application Support/...` のJSON実ファイル保存に移し、localStorage分岐を根本的に起こさない。

---
