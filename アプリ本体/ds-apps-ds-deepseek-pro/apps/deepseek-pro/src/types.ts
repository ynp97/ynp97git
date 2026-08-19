// ── DeepSeek Pro API 型定義 ──

/** 利用可能なDeepSeekモデル */
export type DeepSeekModel = "deepseek-chat" | "deepseek-reasoner";

/** メッセージロール */
export type MessageRole = "system" | "user" | "assistant";

/** チャットメッセージ */
export interface ChatMessage {
  role: MessageRole;
  content: string;
}

/** チャット完了リクエスト */
export interface ChatCompletionRequest {
  model: DeepSeekModel;
  messages: ChatMessage[];
  temperature?: number;
  max_tokens?: number;
  top_p?: number;
  frequency_penalty?: number;
  presence_penalty?: number;
  stream?: boolean;
}

/** 使用量情報 */
export interface Usage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

/** チャット完了レスポンス */
export interface ChatCompletionResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: {
    index: number;
    message: ChatMessage;
    finish_reason: string;
  }[];
  usage: Usage;
}

/** モデル情報 */
export interface ModelInfo {
  id: string;
  object: string;
  created: number;
  owned_by: string;
}

/** モデル一覧レスポンス */
export interface ListModelsResponse {
  object: string;
  data: ModelInfo[];
}

/** API設定 */
export interface DeepSeekConfig {
  apiKey: string;
  baseUrl: string;
  defaultModel: DeepSeekModel;
}
