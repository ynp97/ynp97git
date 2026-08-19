// ── DeepSeek Pro API クライアント ──
import type {
  DeepSeekConfig,
  ChatCompletionRequest,
  ChatCompletionResponse,
  ListModelsResponse,
  ModelInfo,
  ChatMessage,
} from "./types.js";

export class DeepSeekClient {
  private config: DeepSeekConfig;

  constructor(config: DeepSeekConfig) {
    this.config = config;
  }

  private get headers(): Record<string, string> {
    return {
      Authorization: `Bearer ${this.config.apiKey}`,
      "Content-Type": "application/json",
    };
  }

  private async request<T>(path: string, options?: RequestInit): Promise<T> {
    const url = `${this.config.baseUrl}${path}`;
    const res = await fetch(url, {
      ...options,
      headers: { ...this.headers, ...options?.headers },
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(
        `DeepSeek API エラー (${res.status}): ${res.statusText}\n${body}`
      );
    }

    return res.json() as Promise<T>;
  }

  /** 利用可能なモデル一覧を取得 */
  async listModels(): Promise<ModelInfo[]> {
    const res = await this.request<ListModelsResponse>("/v1/models");
    return res.data;
  }

  /** チャット完了（非ストリーム） */
  async chat(
    req: Omit<ChatCompletionRequest, "stream">
  ): Promise<ChatCompletionResponse> {
    return this.request<ChatCompletionResponse>("/v1/chat/completions", {
      method: "POST",
      body: JSON.stringify({ ...req, stream: false }),
    });
  }

  /** シンプルなチャット（1メッセージ） */
  async ask(
    prompt: string,
    options?: {
      model?: string;
      system?: string;
      temperature?: number;
      maxTokens?: number;
    }
  ): Promise<string> {
    const messages: ChatMessage[] = [];
    if (options?.system) {
      messages.push({ role: "system", content: options.system });
    }
    messages.push({ role: "user", content: prompt });

    const res = await this.chat({
      model: (options?.model as any) || this.config.defaultModel,
      messages,
      temperature: options?.temperature,
      max_tokens: options?.maxTokens,
    });

    return res.choices[0]?.message?.content || "";
  }
}
