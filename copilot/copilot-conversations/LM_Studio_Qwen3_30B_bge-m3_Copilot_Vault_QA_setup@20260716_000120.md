---
epoch: 1784127680172
modelKey: "qwen/qwen3-30b-a3b-2507|lm-studio"




tags:
  - copilot-conversation
---

**user**: LM Studio Qwen3 30B bge-m3 Copilot Vault QA setup
[Timestamp: 2026/07/16 00:01:20]

**ai**: The current setup for the LM Studio Qwen3 30B, bge-m3, Copilot, and Vault QA system is fully operational and has been confirmed through multiple verification steps. The established pipeline is: `Obsidian → Copilot Vault QA → bge-m3 → LM Studio Qwen` [^1]. This configuration has been validated as the primary workflow, with LM Studio running locally and hosting both the Qwen3 30B model and the `text-embedding-bge-m3` embedding model simultaneously, both in a "Running" state on port `1234` [^2].

The integration was completed on July 6, 2026, when the `bge-m3` embedding model was successfully loaded into LM Studio and connected to Obsidian Copilot via the OpenAI-compatible API endpoint (`http://localhost:1234/v1`) [^3]. The Vault QA feature was then activated by enabling semantic search and setting the embedding model to `text-embedding-bge-m3` [^4]. To optimize performance and reduce hallucination risks, the vault index was pruned from 4,045 to 293 items by excluding 10 folders, including `journal`, `archive`, and `media`, ensuring only core content is searched [^5].

A new, higher-performance model, `qwen3.6-35b-a3b-mlx`, has been added to the Copilot interface and is now available as `Qwen3.6 35B (LM Studio)` [^6]. This model has been successfully connected and tested, confirming that communication between Obsidian and LM Studio is functional. However, it was also confirmed that the model must be used exclusively in Vault QA mode to access the full context of the vault; using it in standard chat mode results in hallucinations, as demonstrated by the model incorrectly interpreting the string `ynp97` as a Pokémon card set [^7].

The system is now ready for real-world use, with the next steps focused on performance optimization. The current `ynp97` command, which references a large volume of notes, is being restructured to reduce latency by decreasing the number of retrieved fragments from 30 to 8, the context history from 15 to 6, and the maximum response length from 6,000 to 2,000 tokens [^8]. This adjustment is expected to significantly improve response speed while maintaining accuracy.

#### Sources
[^1]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^2]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^3]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^4]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^5]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^6]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^7]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[^8]: [[🗒 相談ログ（追記式）]] (🗒 相談ログ（追記式）.md)
[Timestamp: 2026/07/16 00:02:29]