---
種別: AI連携用 / DeepSeek共有可
作成日: 2026-07-19
役割: OpenClaw + DeepSeek に渡してよいファイルだけを置く場所。
---

# 🤝 AI連携用（DeepSeek共有可）

> [!important] このフォルダのルール
> ここに置いたファイルは **DeepSeek（中国のクラウドAPI）に送られる前提** で扱う。
> 置いてよいもの: アプリのコード、技術仕様、公開前提の文書、調べ物。
> 置いてはいけないもの: **他人の情報（教会員・生徒・請求者）／認証情報・鍵／資金・金額の実情／家庭・信仰の内面の記録**。

## 運用（2026-07-20更新：受け渡しはClaudeが直接行う）

1. DeepSeekに見せたい資料はまずこのフォルダに入れる（コピーでよい）。
2. **反映と受け取りはClaude(Cowork)に頼む**。Claudeは `~/openclaw-apps` を接続フォルダとして承認済みで、双方向のコピーを直接行える。
   - 行き（Vault→openclaw-apps）: このフォルダの資料を反映。
   - 帰り（openclaw-apps→Vault）: DS製アプリを検品（外部送信・CDN・evalスキャン→中身確認）してから `アプリ本体/` へ移し、台帳（🧩）へ登録。
3. OpenClaw（DeepSeek）は `~/openclaw-apps` の中だけで作業する。Vault本体は繋がない。**DeepSeek側にVaultへのコピーを頼まない**（壁はDeepSeekに対するものであり、検品係のClaudeが橋を担う）。

（緊急時・手動でやる場合のコマンド）

```bash
mkdir -p ~/openclaw-apps/docs
cp "/Users/yoshiakinagumo/Documents/Obsidian Vault/🤝 AI連携用（DeepSeek共有可）/AGENTS.md" ~/openclaw-apps/
cp "/Users/yoshiakinagumo/Documents/Obsidian Vault/🤝 AI連携用（DeepSeek共有可）/アプリ一覧（技術情報のみ）.md" ~/openclaw-apps/docs/
```

## 中身

- `AGENTS.md` — OpenClawのワークスペース規則。`~/openclaw-apps` 直下に置くと毎セッション自動で読み込まれる。
- `アプリ台帳（DS用）.md` — 本台帳（🧩）の技術編集版。**節記号（C〜R）は原本と共通**。DSはここを毎セッション読み書きし（「DS作業メモ」欄）、原本との同期はClaudeが行う。A・B節は非共有（機微）。
- `アプリ一覧（技術情報のみ）.md` — 旧ファイル。台帳へ移行済み（ポインタのみ）。

## 更新

- アプリ台帳（🧩）を更新したら、必要に応じて「アプリ一覧（技術情報のみ）」にも技術部分だけ反映する。
- 新しくファイルを足すときは、上のルール（置いてよいもの／いけないもの）で自己チェックしてから入れる。
