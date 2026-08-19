---
種別: アプリ単体引き継ぎ
分割元: 🧩 アプリ開発状況（AI共通）.md（2026-07-31に分割。**本文は一字も変えていない**）
役割: このアプリだけを最小文脈で再開するためのファイル。索引は [[🧩 アプリ開発状況（AI共通）]]。
---

# P. OpenClaw + DeepSeek ローカル開発環境

### P. OpenClaw + DeepSeek ローカル開発環境（2026-07-19構築）

- 種別: アプリではなく開発環境。安価なAPI（DeepSeek）でアプリ試作を量産するための実行基盤。
- 構成: OpenClaw 2026.7.1-2（npm、`~/.npm-global`）＋ DeepSeek API（`deepseek/deepseek-v4-flash`、7/24以降の正式モデル名）。
- 起動: ターミナルで `openclaw dashboard`（トークン付きURLでブラウザが開く）。ゲートウェイは LaunchAgent 常駐（`openclaw gateway stop / start`）。
- 安全設定（確定値）: bind=loopback(127.0.0.1:18789)・token認証・チャンネル連携なし／`tools.exec.ask=always`（シェルは毎回承認）／`agents.defaults.workspace=/Users/yoshiakinagumo/openclaw-apps`／不要スキル33個無効化。
- 既知の限界: ファイルツール（read/write）は承認なしで動き、絶対パスならワークスペース外にも理屈上届く（ソフトな壁）。本物の壁が要るならDocker sandbox（未導入・無料）。Vault・機密はOpenClawに繋がない運用でカバー。
- 共有フォルダ運用: Vaultの `🤝 AI連携用（DeepSeek共有可）` が正本。DeepSeekに見せてよい資料だけをここに置く。基準＝**他人・鍵・金・内面は渡さない／作るもの・技術は渡してよい**。
- 動作確認済み: チャット応答、`~/openclaw-apps` へのファイル作成（hello.txt）、exec承認プロンプト（mkdir時に表示・Allow onceで実行）、tako-shooter等の試作生成。
- 注意: DeepSeekに送った内容は中国のサーバーに渡る前提で扱う。実データ（出席・住所録・日記）は `~/openclaw-apps` に置かない。
- **★事故記録（2026-07-20）**: DSがDockへのzaza.app追加作業中に `defaults delete com.apple.dock persistent-apps` を実行し、**Dockの全アプリ登録を消失**（Time Machineスナップショットなし＝復元不可、標準Dock＋zazaで再構築）。原因＝バックアップなしでMac本体設定を変更。**対策＝AGENTS.mdに「defaults delete全面禁止／設定変更は事前に `backups/` へexport必須」を明文化（反映済み）**。教訓＝execの毎回承認（ask=always）は維持し、承認時に `delete` の語が見えたら止める。Dock再建は最終使用日リスト（mdfind/mdls）から選んで追加のみで行う。
- **受け渡し運用の更新（2026-07-20）**: Claude(Cowork)が `~/openclaw-apps` を接続フォルダとして承認取得済み＝**双方向の受け渡し（共有資料の反映・成果物の検品と受け取り）はClaudeが直接行う。ターミナルのcp作業は不要**（緊急時の手動cpはREADMEに残置）。壁の本体は「DeepSeek側がVaultに触れない」ことで、これは不変。受け取り手順＝①外部送信・CDN・evalの有無をスキャン②中身を確認③合格品を `アプリ本体/` へコピー④台帳へ登録。
- AGENTS.md反映済み（2026-07-20）: 昨夜未反映だったワークスペース規則を、OpenClaw初期規則（記憶・レッドライン）とマージした版で `~/openclaw-apps/AGENTS.md` に配置。正本はVaultの `🤝` フォルダ。新しいOpenClawセッションから有効（念のため `openclaw gateway restart` でも可）。
- **DS用台帳＝同僚方式の運用へ（2026-07-20）**: DSを「写しで働く業者」から「編集版の台帳を持つ同僚」へ引き上げ。`🤝/アプリ台帳（DS用）.md`（workspace側 `docs/アプリ台帳（DS用）.md`）を新設＝**本台帳と同じ節記号（C〜R）**・各節に「DS作業メモ」欄・新規アプリは未採番で追記→原本側が採番。DSのAGENTS.mdに台帳の儀式（開始時読む/終了時追記）を組込み。旧`アプリ一覧（技術情報のみ）.md`は台帳へ移行済み（ポインタ化）。**同期はClaudeの担当**＝本台帳（🧩）の技術面が動いたらDS用台帳へ反映し、DSの作業メモは検品して本台帳へ反映する。A・B節は非共有のまま（機微）。ユーザーがDSダッシュボードへ直接打つ内容だけは検問不能＝「他人・鍵・金・内面は打たない」が唯一の手動ルール。

---
