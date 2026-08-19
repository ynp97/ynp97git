#!/usr/bin/env node
// ── DeepSeek Pro CLI ──

import { createInterface } from "readline";
import { loadConfig } from "./config.js";
import { DeepSeekClient } from "./client.js";

const VERSION = "0.1.0";

function printHelp() {
  console.log(`
DeepSeek Pro CLI v${VERSION}

使い方:
  dpro ask <プロンプト>          DeepSeekに質問する
  dpro models                    利用可能なモデル一覧を表示
  dpro chat                      対話モードで起動
  dpro --help                   このヘルプを表示
  dpro --version                 バージョン表示

環境変数:
  DEEPSEEK_API_KEY   APIキー（必須）
  DS_MODEL           デフォルトモデル（省略時: deepseek-chat）

例:
  dpro ask "TypeScriptのinterfaceとtypeの違いは？"
  dpro models
  dpro chat
`);
}

async function cmdAsk(args: string[]) {
  const prompt = args.join(" ");
  if (!prompt) {
    console.error("❌ プロンプトを入力してください");
    console.error("   使用例: dpro ask \"こんにちは\"");
    process.exit(1);
  }

  const config = loadConfig();
  const client = new DeepSeekClient(config);

  console.error("🔄 DeepSeek Pro に問い合わせ中...\n");
  const answer = await client.ask(prompt);
  console.log(answer);
}

async function cmdModels() {
  const config = loadConfig();
  const client = new DeepSeekClient(config);

  console.error("🔄 モデル一覧を取得中...\n");
  const models = await client.listModels();
  console.log("利用可能なモデル:");
  console.log("─".repeat(40));
  for (const m of models) {
    console.log(`  • ${m.id} (${m.owned_by})`);
  }
}

async function cmdChat() {
  const config = loadConfig();
  const client = new DeepSeekClient(config);

  console.log("💬 DeepSeek Pro 対話モード");
  console.log("   'exit' または Ctrl+C で終了");
  console.log("─".repeat(40));

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const messages: { role: "system" | "user" | "assistant"; content: string }[] = [];

  const askQuestion = (): Promise<string> => new Promise((r) => rl.question("> ", r));

  let input = await askQuestion();
  while (input.trim().toLowerCase() !== "exit") {
    if (!input.trim()) { input = await askQuestion(); continue; }

    messages.push({ role: "user", content: input.trim() });
    console.error("\n🔄 考え中...\n");

    const res = await client.chat({
      model: config.defaultModel,
      messages,
    });

    const reply = res.choices[0]?.message?.content || "";
    console.log(reply);
    console.log();
    messages.push({ role: "assistant", content: reply });
    input = await askQuestion();
  }
  rl.close();
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    printHelp();
    return;
  }

  if (args[0] === "--version" || args[0] === "-v") {
    console.log(`v${VERSION}`);
    return;
  }

  const cmd = args[0];
  const rest = args.slice(1);

  switch (cmd) {
    case "ask":
      await cmdAsk(rest);
      break;
    case "models":
      await cmdModels();
      break;
    case "chat":
      await cmdChat();
      break;
    default:
      console.error(`❌ 不明なコマンド: ${cmd}`);
      printHelp();
      process.exit(1);
  }
}

main().catch((err) => {
  console.error("❌ エラー:", err.message);
  process.exit(1);
});
