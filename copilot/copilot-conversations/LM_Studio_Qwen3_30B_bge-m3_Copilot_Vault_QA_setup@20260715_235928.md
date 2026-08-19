---
epoch: 1784127568333
modelKey: "qwen/qwen3-30b-a3b-2507|lm-studio"




tags:
  - copilot-conversation
---

**user**: LM Studio Qwen3 30B bge-m3 Copilot Vault QA setup
[Timestamp: 2026/07/15 23:59:28]

**ai**: The local AI setup using LM Studio, Qwen3 30B, bge-m3, and Obsidian Copilot for Vault QA is fully operational and structured as a dedicated pipeline. The core architecture is defined as: `Obsidian → Copilot Vault QA → bge-m3 → LM Studio Qwen` [^1]. This setup was confirmed on 2026-07-15, with both the large language model (Qwen3 30B) and the embedding model (bge-m3) successfully loaded and running on LM Studio’s local server at `http://localhost:1234/v1` [^2]. The embedding model `text-embedding-bge-m3` is used for semantic search in Vault QA, and the system is configured to enable semantic search and use the local embedding model exclusively [^3].

The primary mode for using this setup is **Vault QA**, which must be selected in the Copilot interface to ensure queries are processed against the indexed vault content rather than relying on the model’s internal knowledge or generating hallucinated responses [^4]. The user must switch from the default `chat (free)` mode to Vault QA mode to access the full context of the vault, including the 293 core notes that were filtered from the original 4,045 via exclusions of folders like `journal`, `archive`, `media`, and `output` [^5]. This filtering was critical to prevent outdated or irrelevant notes (e.g., old plans for NPO establishment or large-scale actions) from interfering with current decision-making.

A new, higher-performance model, `qwen3.6-35b-a3b-mlx`, has been added to the setup and is now available as a model choice in Copilot, labeled as `Qwen3.6 35B (LM Studio)` [^6]. This model is intended for deeper analysis and complex queries, while lighter models like Qwen 8B or 14B may be used for everyday searches to improve speed and efficiency. The system is currently undergoing optimization to reduce latency, including reducing the number of retrieved context fragments from 30 to 8, limiting the chat history to 6 messages, and capping the maximum response length to 2,000 tokens [^7]. These changes are being tested to resolve performance issues and prevent hallucinations, such as the earlier misinterpretation of the string `ynp97` as a Pokémon card set.

The setup is maintained through a dedicated note: `🤖 Obsidian×ローカルAI引き継ぎ（AI共通）.md`, which serves as a central reference for all components, including agent roles, prompt protocols, and the full connection flow [^8]. All external connections, including the use of `@vault` and custom commands like `ynp97`, are designed to route through this pipeline to ensure consistency and prevent context loss.

#### Sources
[^1]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^2]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^3]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^4]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^5]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^6]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^7]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^8]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[Timestamp: 2026/07/16 00:00:44]