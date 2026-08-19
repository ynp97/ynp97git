---
種別: Obsidian×AI実行環境 / 引き継ぎ正本・livingドキュメント
作成日: 2026-07-15
役割: Obsidian、Copilot、LM Studio、ローカルモデル、OpenClaw、DeepSeek等の外部AI API、埋め込み、Vault QAに関する現在構成・検証結果・運用・未解決を一か所に集約する正本。
更新方針: モデル、設定、索引範囲、運用、既知の限界が変わったら上書き更新。経緯は相談ログに残す。
---

# 🤖 Obsidian×AI実行環境引き継ぎ（AI共通）

> [!important] このテーマの正本
> ローカルAIは一時的な実験ではなく、南雲が継続して育てたい**一つの本線**。Obsidianは、人生・信仰・創作・事業の記録とAI協働をつなぐ**非常に重要な基盤**である。
> 四つの柱を増やすのではなく、四つ全部を横断して支える「記憶・検索・AI協働の基盤」として扱う。
> LM Studio等のローカルAIだけでなく、OpenClawを通して使うDeepSeek・Kimi・MiniMax・GLM・Gemini等の外部APIも、費用・能力・画像対応・Mac負荷を分担する同じAI実行環境の一部として扱う。
> Obsidian、LM Studio、ローカルモデル、外部AI API、OpenClaw、Copilot、Vault QA、RAG、埋め込みについて相談されたAIは、長い相談ログを探す前にまずこのノートを読む。

## 0. `ai97`参照索引

`ai97`からAI実行環境の相談へ入ったときの参照索引。LOCAL AIを中心に、DeepSeek等の外部AI APIとOpenClawも同じまとまりで扱う。このノートへ来た後は関係する節だけを参照する。

- **起動だけ**: 1（本線）、2（現在地）、9（次の一手）
- **LM Studio・モデルのロード・サーバー・接続**: 1、2、4、5、7、9
- **Obsidian Copilot・Vault QA・RAG・埋め込み・索引**: 1〜7
- **OpenClaw・DS・DeepSeek・ALLOW・Docker**: 9.5、9.6、更新履歴の該当項目
- **Kimi・MiniMax・GLM・Gemini等の外部API比較**: 9.7〜9.9。変動情報は公式情報で最新確認する。
- **画像・音声・マルチモーダル**: 9.6、9.8
- **新モデル・価格・入れ替え**: 9.7〜9.9。変動情報は公式情報で最新確認する。
- **過去の続き**: このノートを固有名詞で検索し、不足時だけ相談ログの関連箇所を検索する。ログ全体は読まない。

AI全体の入口は`🤖 AI関連引き継ぎ（AI共通）.md`。詳細な起動・更新規則は`.agents/skills/ai97/SKILL.md`を正とする。Obsidian Copilotでは`/ai97`を候補から選ぶ。

## 1. 本線の構成

```text
Obsidian Vault
  ↓
Obsidian Copilot 3.3.3
  ↓ Vault QA（関連ノートを検索）
bge-m3（日本語対応の埋め込みモデル）
  ↓ 検索で拾った断片を渡す
LM Studioのローカルサーバー（http://localhost:1234/v1）
  ↓
Qwenが回答
```

**本線**: `Obsidian → CopilotのVault QA → bge-m3 → LM StudioのQwen`

**予備**: LM Studioアプリ単体へテキストを添付する方法。Vaultを継続的に参照する本線ではなく、一時利用・切り分け用。

## 2. 現在の構築状況（2026-07-16確認）

> [!success] 本線復旧済み
> `Qwen3 30B A3B 2507 + bge-m3 + Copilot Vault QA` を正本構成として復旧し、292ノートのForce Reindex、出典付きVault QA回答、`/ynp97`の「ブリーフィングを読みました」応答まで実画面で確認した。
> 2026-07-16 00:18、回答モデルを`Qwen3.6 35B`へ切り替え、同じ292ノート索引とbge-m3を使って`/ynp97`が完走することも確認。現在の選択モデルはQwen3.6。

### 構築済み・設定が残っているもの

- Obsidian Copilot: **v3.3.3**
- LM Studio接続先: `http://localhost:1234/v1`
- Copilotに登録済みの旧回答モデル: `qwen/qwen3-30b-a3b-2507`
- 表示名: `Qwen3 30B (LM Studio)`
- 埋め込みモデル: `text-embedding-bge-m3`
- Copilotの埋め込みモデル選択: `text-embedding-bge-m3|lm-studio`
- Semantic Search: **ON**（`enableSemanticSearchV3: true`）
- 索引同期: **ON MODE SWITCH**／同期有効
- 取得断片の上限: 30
- 出典表示: ON
- Copilotの既定回答モデル: `qwen3.6-35b-a3b-mlx|lm-studio`
- Qwen3.6のLM Studioロード設定: コンテキスト`16384`、parallel`1`。メモリ保護によりbge-m3を先に載せると失敗する場合があるため、**Qwen3.6を先にロードし、その後bge-m3をロードする**。
- Qwen3.6にも`useResponsesApi: false`を設定し、Chat Completions経路を使う。
- LM Studioモデル設定: `useResponsesApi: false`（重要。Copilot 3.3.3の既定Responses API経路はLM Studioで停止したため、実動するChat Completions経路を使う）
- 軽量化済み: `maxSourceChunks: 8`、`contextTurns: 6`、AIタイトル自動生成OFF。`maxTokens`は当初2000へ下げたが、Qwen3.6が内部推論だけで1999トークンを使い切り本文ゼロで終了したため、2026-07-16に`maxTokens: 6000`へ戻した。
  - > [!warning] **2026-08-01 現物確認: `maxTokens` は `2000` に戻っている**（`.obsidian/plugins/copilot/data.json` を実査）。いつ・なぜ戻ったかは不明。**Qwen3.6を使うと本文ゼロの空回答が再発する条件がそのまま残っている。** 使う前にCopilot設定で6000へ直すこと。
  - **2026-08-01に判明した現物の他の値**: `defaultChainType = llm_chain`（**既定はVault QAではない**）／`enableAutonomousAgent = true`（`writeFile`・`editFile`を含むツールが有効）／`isPlusUser = false`／APIキーはmacOSキーチェーン保存（`_keychainOnly = true`）で`data.json`からは有無を判定できない。**詳細は [[🧭 実行環境の能力表（AI共通）]] §4-2 が正本。**
- Copilotカスタムコマンド: `copilot/copilot-custom-prompts/ynp97.md`
- `ynp97`には、ブリーフィング4ファイルの参照と、回答可能性判定・根拠のない補完禁止・確認不能時の停止ルールを反映済み。

### 2026-07-16の復旧結果

- Qwen3 30Bとbge-m3を同時ロードし、LM Studio APIの直接応答を確認。
- Vault QAの索引を全面再構築。除外10フォルダを適用した対象は292ノートで、全件完了。
- テスト質問 `LM Studio Qwen3 30B bge-m3 Copilot Vault QA setup` に対し、相談ログを出典として構成・ポート・索引範囲を回答。検索は正常。
- `/ynp97`を候補から選択して実行し、約64秒で「ブリーフィングを読みました」と応答。ynp97はこの環境で動作する。
- 根本原因は、Copilot 3.3.3がLM Studioモデルに新しいResponses APIを既定使用していたこと。検索自体は16件取得できていたが、`safeFetch request`以後で停止し、LM StudioへChat Completions要求が届かなかった。`useResponsesApi: false`で解決。
- 併発していた問題は、索引が25ノート相当に縮んでいたことと、30断片・15会話・6000出力の過大設定。292ノートへ再索引し、8・6・2000へ軽量化した。

### Qwen 3.6の検証履歴（現在の選択モデル）

- 2026-07-16 00:14:37にVault QAで`/ynp97`を送信し、00:18:06に「ブリーフィングを読みました」と応答。実測約3分29秒。
- Qwen3.6は`/no_think`を与えても内部推論を継続する。短い直接テストでも約130 reasoning tokensを使ったため、Qwen3 30Bより大幅に遅い。故障ではなくモデル特性。
- Qwen3 30Bは約64秒で同じ`/ynp97`を完了したため、速度優先時の確実な予備モデルとして残す。
- 2026-07-16 00:41、Vault QAで「直近修正されたものを確認して。」と質問したところ、内部推論だけで出力上限2000のうち1999トークンを使い、回答本文を生成する前に`Response Truncated`となった。これは接続不良ではなく、Qwen3.6に対する出力上限不足。対応として`maxTokens`を6000へ戻した。
- 同じ画面で`Relevant Notes: No relevant notes found`も出ている。Vault QAはファイルの更新時刻順を取得する機能ではなく、質問と意味が近い断片を探す仕組み。「直近修正されたもの」だけでは意味検索の手がかりがなく、最近順検索のテストには向かない。テーマや正本名を指定して質問する。

- LM Studioで検証した新しい回答モデル: `qwen3.6-35b-a3b-mlx`
- 2026-07-15の確認時、LM Studioサーバーから新Qwenとbge-m3が公開されることを確認済み。
- Copilot設定へ `qwen3.6-35b-a3b-mlx` を新規追加済み。表示名は `Qwen3.6 35B (LM Studio)`。旧Qwenと既定Geminiは残している。
- ユーザーがLM StudioのDeveloper画面でサーバーをRunningにし、Qwen 3.6と `text-embedding-bge-m3` を手動ロード。Copilotのモデル欄に `Qwen3.6 35B (LM Studio)` が表示され、**モデルとの通信**は成功した。
- ただし2026-07-15 22:17の実画面では、Copilotのモードが **`chat (free)`** のままでVault QAではなかった。`ynp97`を送ると、Qwenはそれをポケモンカードの番号097と誤解し、架空の「約束の絆（Yinic Promise）」、メガリザードンXex、価格表を生成した。これは重大な幻覚。
- したがって現状は「Qwenとの通信は成功／Obsidianの記憶との接続は未成立」。Vault QAモードへの切り替えと、文字列としての `ynp97` ではなくCopilotのカスタムコマンド `/ynp97` をメニューから選択して実行する必要がある。
- 応答も約1分かかっており、Vault連携確認後に速度軽量化が必要。
- Codex側からポート1234を測定した際は応答した時と停止していた時があり、サーバー常時稼働の安定性は未確認。ユーザー画面でRunningを正とする。

## 3. Vault QAの索引範囲

最初は4,045件以上を索引したが、古い計画や大量のアーカイブが現在方針より強く拾われた。除外を設定して**約293件の核となるノート**へ絞った。

現在の除外:

- `ジャーナル`
- `アーカイブ`
- `Obsidian_ChatGPT_Context_Vault`
- `scripts`
- `_査定結果`
- `media`
- `e-bay PIC`
- `output`
- `copilot`
- `tmp`

Inclusionsは空。つまり、上記を除外し、それ以外を対象とする。

> [!note] 鹿島学園2026年度 通信制実務マニュアル（2026-07-28追加）
> 原本PDFは除外対象の `アーカイブ` に保存し、検索用の章別Markdown12件と参照入口を、索引対象の `資料/KG通信制実務マニュアル2026/` に置いた。入口は [[資料/KG通信制実務マニュアル2026/00 AI参照入口]]。PDFページ141〜155は日本語OCRなので、Vault QAは検索・候補提示までとし、表・日付・金額・連絡先の確定は原本PDFで行う。次回の索引同期後からVault QAの検索対象になる。

> [!note] `聖書（新改訳2017）` フォルダの扱い（2026-07-19決定）
> 新改訳2017全66巻を内蔵したが、**Vault QAの索引には当面含めない**（除外はしていないが、Force reindex時に手動で外すか、除外フォルダに追加を検討）。理由=全文（詩篇2578節等）を索引に入れると意味検索が聖書に強く引っ張られ、ynp97等の戦略相談が濁る懸念。**聖書本文の参照は、Cowork（Claude）がファイルを直接読む方が確実**（set97/st97/釈義スキルに「本文は内蔵聖書から読む」を追記済み）。Qwenでも全文検索したい必要が出たら、そのとき除外を外してForce reindexすればよい（後からいつでも可逆）。

## 4. 普段の起動手順

1. LM Studioを起動する。
2. 回答用Qwenと `text-embedding-bge-m3` をロードする。
3. DeveloperでローカルサーバーをRunningにする。接続先は `http://localhost:1234/v1`。
4. Obsidianを開き、Copilotチャットを開く。
5. 回答モデルとしてLM StudioのQwenを選ぶ。
6. チャットモードを必ず **Vault QA** にする。
7. 戦略相談ならCopilotのカスタムコマンド `/ynp97` を使う。

> ChatモードのままではVault検索をせず、モデルが手元知識だけで作文することがある。Vaultを読ませる目的では必ずVault QAを使う。

## 5. Qwen 3.6をCopilotへ登録するときの値

- Provider: `LM Studio`
- Model Name: `qwen3.6-35b-a3b-mlx`
- Base URL: `http://localhost:1234/v1`
- API Key: 空欄または任意の文字列
- CORS: ON
- 表示名の候補: `Qwen3.6 35B (LM Studio)`

登録後はTestを行い、Copilotチャット下部で新しいモデルを選ぶ。

## 6. 検証で分かった限界

### RAGはVaultを丸ごと読む仕組みではない

Vault QAは、質問と意味が近い断片を上位から数個拾う。ノート全体や正本の優先順位を、人間と同じように理解するとは限らない。

### 新旧や重要度を自動では判定できない

過去テストでは、8月の予定を尋ねた際、古い計画から「SNS毎日100件・NPO設立」などを現在方針のように回答した。正しい現在地は、📌事実と前提、🔭検討中プロジェクト、🗒相談ログの最新決定を優先する。

### 小型・ローカルモデルは拾った断片から作文しやすい

流暢さを根拠と考えない。資料にない数字、出典、製品、価格、出来事を補わせない。確認できない場合は停止させる。

2026-07-16の境界テストで、Qwen3.6は「メガリザードンXex」の相場は確認できないと停止した一方、存在自体は「安定した一般知識」として断定。根拠を求められると、2014年Phantom Forces、日本版「黒き炎のドラゴン」、53/108という詳細を捏造した。公式確認では、現在の「メガリザードンXex」は実在するが、日本公式登録は`M2a 223/193`・「MEGAドリームex」。Phantom Forces公式リストにリザードはなく、番号53はPoochyena。つまり存在は偶然当たったが、根拠と詳細は捏造。

再発防止として、`.obsidian/plugins/copilot/data.json`の共通`userSystemPrompt`と`/ynp97`の両方に、①モデル内部の学習記憶は固有対象の検証済み根拠ではない、②実際の参照文脈なしに「公式で確認」と言わない、③根拠を示せなければ前回の断定を撤回して終了、④似た名称・新旧表記を置換しない、を追加した。

### LM StudioアプリのSystem PromptとCopilotは別入口

LM Studioアプリのチャット欄で設定したSystem Promptが、CopilotからAPI経由で呼ぶ回答へ自動適用されるとは限らない。そのため、Copilot側の `/ynp97` にも捏造防止ルールを記載している。

### 最新情報・ネット検索は別系統

ローカルQwen単体は現在の相場・ニュース・発売情報などをリアルタイム確認できない。Vault内資料の整理・要約・検索・下書きと、ネット確認が必要な仕事を分ける。

## 7. よくある問題の切り分け

### Copilotから接続できない

1. LM StudioのサーバーがRunningか。
2. ポートが1234か。
3. Base URLが `http://localhost:1234/v1` か。
4. LM Studio側とCopilot側のCORSが有効か。
5. Copilotに登録したModel Nameが、LM Studioが公開しているIDと完全一致しているか。

### Vaultを読まずに答える

1. CopilotがChatではなくVault QAモードか。
2. bge-m3がロードされているか。
3. Semantic SearchがONか。
4. 必要なノートが除外フォルダへ入っていないか。
5. 必要ならForce reindex vaultを行う。

### 古い計画を現在方針として答える

- 回答に使った関連ノートを確認する。
- 📌事実と前提、🔭検討中プロジェクト、AIブリーフィングを質問内で明示する。
- 古い計画フォルダを除外するか、正本へのリンクを強める。
- QAの要約を証拠として扱わない。

## 8. この本線の役割分担

- **Obsidian**: 長期記憶、正本、一次資料、履歴、AI間の共有基盤。
- **Copilot**: Vaultから関連箇所を検索してモデルへ渡す入口。
- **bge-m3**: 日本語を含むノートの意味検索。
- **Qwen／ローカルAI**: 非公開資料をMac内で扱う、要約・整理・分類・下書き・検索結果の対話。
- **Gemini等のオンラインAI**: ネット確認、最新情報、必要に応じた別視点。
- **Codex／Claude**: Vaultの実ファイルを読み書きし、正本と実装を更新する作業役。

### ChatGPT無料枠とVault連携の境界（2026-08-09確定）

- OpenAIは2026-08-06、Free / GoにGPT-5.6 Lunaを既定展開し、翌週から**テキストチャットを無制限**にすると発表した（不正利用防止の制約あり）。ただし**ファイル、画像、その他ツールの制限は残り、Work / Codexの枠は変わらない**。正本: OpenAI ChatGPT Release Notes 2026-08-06。
- **OpenClawはLunaモデルに接続できるが、無制限Chat枠は使えない。** ChatGPT OAuthはプラン別のCodexクォータ、APIキーは従量課金。同じアカウントでもChat画面の権利は外部エージェント枠へ移らない。
- **Obsidian Copilotに無制限Lunaを入れることはできない。** CopilotのOpenAI接続はAPIキー方式で、ChatGPT Free / Plusの利用枠とは別会計。モデル一覧の組み込みGPTは、APIキーを入れなければ動かない。`Sign in with ChatGPT`も本人確認であり、モデル利用枠・トークン・ファイルを外部アプリへ渡す機能ではない。
- 別の無料ChatGPTアカウントは、**追加の無料相談枠**として使う。Webのアカウント切替は2アカウントを保持できるが、Codexデスクトップは未対応。履歴・メモリ・利用枠は混ざらない。
- 別GPTアカウントは同じOpenAI系なので、OpenAI障害・アカウント制限への保険にはならない。**別GPT=追加の無料枠、Gemini=別会社の非常用保険**とし、両方を残す。
- 未検証: ChatデスクトップのローカルプロジェクトでVaultを参照した場合、無制限テキストChatとファイル/ツール制限がどう分けて数えられるかは、公式資料に明記がない。

## 9. 現在の次の一手

1. 現在は `Qwen3.6 35B + bge-m3 + Vault QA` を使用する。起動順はQwen3.6（16k）→bge-m3。速度優先時は検証済みのQwen3 30Bへ戻せる。
2. 戦略相談は入力欄で `/ynp97` を候補から選ぶ。単なる文字列 `ynp97` として送らない。
3. 実測では通常Vault QAも`/ynp97`も約1分。さらに速度を求める場合は、正確性を保ったまま取得断片数を8から段階的に下げる検証を別途行う。

## 9.7 新モデル・重要更新の検知ルール（2026-07-22）

> [!important] ユーザーに情報収集を返さない
> 南雲本人はローカルAIの新製品情報を日常的に追いかける運用はしない。このテーマの相談を受けたAI側が、必要に応じて主要モデル・LM Studio・Ollama・OpenClaw・Apple Silicon対応の大きな変化を最新情報で確認する。全ニュースの羅列ではなく、現在の32GB Mac・Vault QA・OpenClaw・画像/音声用途に実際に関係する変化だけを短く伝える。

- 2026-07-22の反省: Gemma 4は2026-04-02に登場し、6月に12Bが追加されていたのに、7月のQwen・DeepSeek・OpenClaw検証中に一度も候補として提示しなかった。既存構成の復旧と目前の比較対象に視野が限定されたことが原因。
- 今後は新しいローカルモデルの導入・入れ替え・役割分担を話す前に、少なくともGoogle Gemma、Alibaba Qwen、DeepSeek、Meta Llama、Mistralの直近の主要公開モデルと、LM Studio/OpenClawでの実装対応を確認する。
- 「モデル自体の能力」と「現在使っているアプリからすぐ使える機能」を分けて報告する。

## 11. 関連する正本・設定

- [[🗂 話題別インデックス（AI共通）]]
- [[🧭 AIブリーフィング（最初に読む）]]
- [[📌 事実と前提（AI参照用）]]
- [[🔭 検討中プロジェクト（オープンな問い）]]
- [[🔌 外部AI連携（起動プロンプトと記憶プロトコル）]]
- `copilot/copilot-custom-prompts/ynp97.md`
- `.obsidian/plugins/copilot/data.json`

## 分割について（2026-07-31）

このファイルは32,933文字あり、現在の構成・DS委任の作業史・モデル比較の検討メモが混在していた。**本文を一字も変えずに**3つへ分けた。

- **このファイル** … 現在の構成・起動手順・設定値・限界・切り分け（＝いま使うもの）
- [[🤖 DS運用引き継ぎ（AI共通）]] … 9.5系・9.6（DeepSeek委任の手順と経緯）
- [[🗄 ローカルAI 検証・比較アーカイブ]] … 9.8〜9.11のモデル比較、10.検証履歴、更新履歴

分割前の全文は `バックアップ/🤖 ローカルAI引き継ぎ_分割前_2026-07-31.md`。
