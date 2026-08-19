# DeepSeek Pro — API クライアント & CLI

DeepSeek Pro API を TypeScript から使うためのクライアントライブラリ＆コマンドラインツール。

## セットアップ

```bash
cd apps/deepseek-pro
npm install
npm run build
```

## API キー

環境変数 `DEEPSEEK_API_KEY` に DeepSeek の API キーを設定してください。

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxx
```

## 使い方（CLI）

```bash
# ビルド
npm run build

# 質問
node dist/cli.js ask "TypeScriptのinterfaceとtypeの違いは？"

# モデル一覧
node dist/cli.js models

# 対話モード
node dist/cli.js chat

# ヘルプ
node dist/cli.js --help
```

## ライブラリとして使う

```typescript
import { DeepSeekClient, loadConfig } from "@ynp97/deepseek-pro";

const config = loadConfig();
const client = new DeepSeekClient(config);

const answer = await client.ask("こんにちは", {
  system: "あなたは親切なアシスタントです。",
});
console.log(answer);
```

## 環境変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `DEEPSEEK_API_KEY` | APIキー（必須） | — |
| `DS_BASE_URL` | APIエンドポイント | `https://api.deepseek.com` |
| `DS_MODEL` | デフォルトモデル | `deepseek-chat` |
