// ── 設定管理 ──
import type { DeepSeekConfig, DeepSeekModel } from "./types.js";

const DEFAULTS = {
  baseUrl: "https://api.deepseek.com",
  defaultModel: "deepseek-chat" as DeepSeekModel,
};

/**
 * 設定を読み込む（優先順位: 引数 > 環境変数 > デフォルト）
 */
export function loadConfig(overrides?: Partial<DeepSeekConfig>): DeepSeekConfig {
  const apiKey =
    overrides?.apiKey ||
    process.env.DEEPSEEK_API_KEY ||
    process.env.DS_API_KEY ||
    "";

  if (!apiKey) {
    console.error(
      "❌ DeepSeek API キーが設定されていません。\n" +
        "   DEEPSEEK_API_KEY 環境変数を設定するか、.env ファイルを作成してください。"
    );
    process.exit(1);
  }

  return {
    apiKey,
    baseUrl: overrides?.baseUrl || process.env.DS_BASE_URL || DEFAULTS.baseUrl,
    defaultModel:
      (overrides?.defaultModel as DeepSeekModel) ||
      (process.env.DS_MODEL as DeepSeekModel) ||
      DEFAULTS.defaultModel,
  };
}
