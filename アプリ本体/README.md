# アプリ本体

このフォルダは、開発中アプリの実体コードをVaultと同じGitHubで管理するための場所。

## 管理中のアプリ

### Shirangana

- 移設元: `/Users/yoshiakinagumo/Documents/Codex/2026-06-09/new-chat/work/Shirangana`
- 種別: iPhoneアプリ
- 開くもの: `Shirangana/Shirangana.xcodeproj`
- 備考: `DerivedData` と `DerivedDataSimulator` はGit管理しない。

### Graveyard-of-the-Black-Nebula

- 移設元: `/Users/yoshiakinagumo/Documents/Codex/2026-05-28/new-chat`
- 種別: 音源アーカイブ用Webアプリ
- 開くもの: `Graveyard-of-the-Black-Nebula/index.html`
- 主なファイル: `index.html`, `styles.css`, `app.js`

### 出席簿

- 移設元: `/Users/yoshiakinagumo/Documents/Codex/2026-06-03/7/outputs`
- 種別: 学習施設用出席簿アプリ
- 開くもの: `出席簿/attendance_form_report.html`
- アプリバンドル: `出席簿/出席簿.app`
- 備考: 実データやバックアップJSONは個人情報を含む可能性があるため、Git管理しない。

## 運用

1. アプリを編集したら、このフォルダ内の実体を更新する。
2. 関連ノートは `🧩 アプリ開発状況（AI共通）.md` に反映する。
3. `git status` で差分を確認する。
4. 意味のある単位でcommitする。
5. `git push` でGitHubへ送る。
