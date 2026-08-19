# 15インチMac（DS実装機）への指示 — screen-recorder の移設

作成日: 2026-07-30
※ この内容をそのままDSへ渡す。

> [!warning] 2026-07-31 追記 — この再指示も実行されていない
> 7/31にこちらで確認したところ、`ynp97apps15/screen-recorder` は**まだ Public のまま**だった（未ログインで取得でき、`repository_public: true`）。作業票の有無は`ds-apps`が非公開のため外部から未確認。
> **現在の指示は [[15インチへの指示_screen-recorder_未完了2件と実機確認]] が正本。** 以下は経緯として残す。

**2026-07-30 追記（残作業のみ再指示）**: `ds/screen-recorder`ブランチへのpushと`apps/screen-recorder/`一式は完了済み。ただし①`docs/作業票/`が作られておらず作業票が存在しない、②旧リポジトリが「Private化」ではなく「アーカイブ（Public archive、公開のまま読み取り専用）」になっている、の2点が未完了。以下を再指示する。

```
docs/作業票/screen-recorder-移設.md を作り、テンプレート(docs/作業票テンプレート.md)に沿って
実際に実行したビルドコマンドと出力をそのまま貼って push すること。
また ynp97apps15/screen-recorder は「アーカイブ」ではなく Settings → General → Danger Zone →
Change repository visibility → Private に変更すること（アーカイブだけでは公開状態が続くため不可）。
ds-apps の AGENTS.md を更新済みなので、pullして読み直してから作業すること。
```

---

## 背景

`ynp97apps15/screen-recorder` として**公開**リポジトリに置かれているが、方針は次の2点。

1. 成果物は `ynp97/ds-apps` の `ds/○○` ブランチへ置く（アプリごとに別リポジトリを作らない）
2. 非公開にする

`ds-apps` には検品ルール（`AGENTS.md`）が入った。**作業前に必ず読むこと。**

## やること

### 1. ds-apps へ移す

```
cd ~
git clone https://github.com/ynp97/ds-apps.git
cd ds-apps
git checkout -b ds/screen-recorder
mkdir -p apps/screen-recorder
```

`screen-recorder` の中身（`Sources/`、`Package.swift`、`build.sh`、`Info.plist`、`AppIcon.icns`、`AppIcon.iconset`、`gen-icon.swift`、`icon.png`、`.gitignore`）を `apps/screen-recorder/` へコピーする。

`.gitignore` はアプリ配下に置く形にする（`.build/`、`*.app` などビルド生成物を除外）。

### 2. A層｜機械チェックを自分で回す

```
cd apps/screen-recorder
swift build
```

`build.sh` がある場合はそれも実行する。**出力を全部残すこと。**

### 3. 作業票を書く

`docs/作業票/screen-recorder-移設.md` を作る。テンプレートは `docs/作業票テンプレート.md`。

**「ビルド結果」「動作確認」に、実行したコマンドと出力をそのまま貼る。**
「未ビルド」「未実施」のまま push しない。通らなかった場合はエラー全文を貼る（それは正しい報告）。

### 4. C層｜相互チェック

**実装したセッションで自己検品しない。** 新しいセッションを立て、渡すのは差分（`git diff main...HEAD`）と完成条件だけ。台帳・リポジトリ全文は渡さない。

聞くこと: 仕様外の機能を足していないか／実データ・APIキー・証明書の混入／エラー処理の抜け・境界値・失敗時の挙動。

指摘を直してから push。要点を作業票の「懸念・相談」へ残す。

### 5. push

```
cd ~/ds-apps
git add .
git commit -m "screen-recorder を ds-apps へ移設"
git push origin ds/screen-recorder
```

`main` へは push しない。

### 6. 旧リポジトリを非公開にする

`ds-apps` 側に入ったことを確認してから、`ynp97apps15/screen-recorder` の
Settings → General → 一番下の Danger Zone → **Change repository visibility → Private** にする。

**削除はしない。** 非公開にするだけ。削除の判断は本人が行う。

## 完成条件

- [ ] `ds/screen-recorder` ブランチが `ynp97/ds-apps` に push されている
- [ ] `apps/screen-recorder/` にソース一式が入っている
- [ ] `docs/作業票/screen-recorder-移設.md` に実際のビルド出力が貼られている
- [ ] C層レビューを実施した（または「急ぎ指示により省略」と明記）
- [ ] `ynp97apps15/screen-recorder` が Private になっている

## 今後（毎回のルール）

**アプリごとに新しいリポジトリを作らない。** 成果物は必ず `ynp97/ds-apps` の
`ds/アプリ名` ブランチへ置く。理由は、①検品ルールが効く、②本アカウント `ynp97` の
所有下に残る（15インチのアカウントに依存しない）、③受け取り手順が一本化される。
