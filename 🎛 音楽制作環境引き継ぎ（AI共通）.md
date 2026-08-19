---
種別: 音楽制作環境 / AI共通引き継ぎ
作成日: 2026-07-11
起動合図: q97
対象: Cubase / Logic / DAW / MIDI / オーディオ / プラグイン / Mac・PC操作 / 周辺機器
---

# 🎛 音楽制作環境引き継ぎ（AI共通）

## AIへ

`q97` で起動したら、このノートを最初に読む。相談に関係するリンクだけを追加で参照し、戦略・アプリ・説教系ファイルは読まない。操作案内では推測で設定名・CC番号・接続状態を埋めず、スクリーンショット、機器側エディター、Cubase/Logicの実表示を優先する。

> [!important] 曲・プロジェクトの所在を探すとき（2026-07-31追加）
> **[[🎛 Cubaseプロジェクト地図]] に441件のCPRが一覧してある**（更新日・場所・容量・Audio有無・保存パス）。「あの曲のCubaseファイルどこだっけ」は、まずここを**曲名で検索**する。**67,394文字あるので全文は読まない。** 該当行だけを引く。
> 一覧の生成日は地図の冒頭にある。**それ以降に作った・移動したプロジェクトは載っていない**ので、見つからないときは実機で確認する。

## 現在の確定設定

### Cubase 15 × KORG nanoKEY Studio

- USB用とBluetooth用のMIDI Remoteを別サーフェスとして併存。
- Bluetooth用ポート: `nanoKEY Studio Bluetooth`
- ノブ8個: QC1〜QC8。
- X-Yモード: X軸（横）＝CC16、Y軸（縦）＝CC17、各0〜127。
- Cubaseでは専用X/YパッドへCC16/17を直接入力。
- 詳細: [[🎹 Cubase 15・nanoKEY Studio Bluetooth MIDI Remote設定]]

### BFD3.5 × Cubase 15

- BFD3本体バージョン: 3.5.0.49。
- 現在のCore Library: `/Users/yoshiakinagumo/Documents/BFD Drums/BFD3 Core Library`（約45GB）。
- 旧参照先 `/Volumes/TRANSCEND/DTM DATE FOLDER/BFD3 Core Library` はデータが存在せず、二重表示・ロード失敗の原因になるためBFDのContent Locationsから外す。
- Cubase用完全版ドラムマップ: `/Users/yoshiakinagumo/Desktop/INTRANS/名称未設定フォルダ 2/BFD3.drm`。
- 日常入力用の簡易マップを自作したが、Cubase上で全行がKickとして展開され使用不可。`/Users/yoshiakinagumo/Desktop/BFD3簡易版_スネア・ハット重視.drm` は使わない。
- 簡略化は正常動作する完全版 `BFD3.drm` と、Cubase 15ドラムエディターの「ピッチ表示」機能を組み合わせる方針。
- その後、正常な完全版のMap部分を一切変更せず、Orderだけを並べ替えた `/Users/yoshiakinagumo/Desktop/BFD3_ESSENTIAL_Snare_HiHat.drm` を新規作成。スネア・ハイハット・主要ドラムを先頭へ配置。ファイル構造とMap部分の完全一致は検証済みだが、Cubase実機での読み込み結果は未確認。
- 全128音を名称で分類した `/Users/yoshiakinagumo/Desktop/BFD3_ALL_SOUNDS_SORTED.drm` を作成。順番はキック→スネア→ハイハット→タム→ライド→クラッシュ→その他シンバル→パーカッション→その他。正常版のMap/出力/チャンネルは完全保持し、Orderとマップ名だけを変更。

#### ドラムマップの細かい並べ替えを頼まれたとき

- 現在の最新版・次回編集の基準: `/Users/yoshiakinagumo/Desktop/BFD3_ALL_SOUNDS_SORTED.drm`。
- 正常な元マップ（音対応の正本）: `/Users/yoshiakinagumo/Desktop/INTRANS/名称未設定フォルダ 2/BFD3.drm`。
- ユーザーは今後「この音を一つ上へ」「AとBを入れ替える」程度の微調整を依頼する可能性がある。
- 微調整時は最新版を基に、XMLの `<list name="Order" type="int">` 内の対象 `item value` の位置だけを動かす。
- `<list name="Map">`、INote、ONote、Channel、OutputDevices、Flagsには触れない。マップ名は必要な場合だけ変更する。
- 編集後の必須検証: Mapが正本と完全一致／Map 128行／Order 128行／Order値が128個すべて一意／`Name, Quantize, Map, Order, OutputDevices, Flags` の全セクションが存在。
- 既存の正常ファイルは上書きせず、原則として新しい名前でデスクトップへ出す。ユーザーが明示した場合だけ最新版を上書きする。
- 失敗した `BFD3簡易版_スネア・ハット重視.drm` は基準にしない。
- BFDグルーヴをCubaseへMIDIドラッグし、簡易マップでキック等を編集する運用を想定。

### Illformed Glitch 2（未インストール）

- 2026-08-10時点の公式現行版は2.1.5。無料化され、Mac版にVST3が追加された。Apple Siliconに対応。
- 公式Mac版ZIPの中身は `Glitch2.component` / `Glitch2.vst` / `Glitch2.vst3` / `Glitch2_User_Guide.pdf` / `Glitch2_Presets`。
- Cubase 15では `Glitch2.vst3` を `/Library/Audio/Plug-Ins/VST3/` へ。Logicでも使う場合は `Glitch2.component` を `/Library/Audio/Plug-Ins/Components/` へ。`Glitch2.vst` は旧VST2用なので、Cubase 15用としては原則不要。
- プリセットは任意。`Glitch2_Presets` をDocumentsなどの分かりやすい場所へ保管し、Glitch 2内から読み込む。
- Cubase/Logic実機での認識・起動は未確認。成功後に本節の「未インストール」を更新する。

## 索引

### Cubase

- [[🎹 Cubase 15・nanoKEY Studio Bluetooth MIDI Remote設定]]
- [[会話ログ/Cubase 15 tempo display]]
- [[会話ログ/Cubase BPM speed issue]]

### Logic

- `Chord Bridge` 双方向試作版 0.9.1（build 11）を作成。CubaseのコードをLogicへ渡し、Logic側はMIDI／オーディオの受け渡しを選べる。
- デスクトップ版: `/Users/yoshiakinagumo/Desktop/Chord Bridge.app`
- ソースとビルド: `/Users/yoshiakinagumo/Documents/Obsidian Vault/アプリ本体/ChordBridgeMac`
- 現在のCubase側ボタンは `① 選んだトラックのコードを一つにまとめる`。コード名付きMIDIパートが横に並ぶトラック名を一回クリックしてから押す。
- アプリはCubaseの `編集 → 選択 → 選択トラック上の全イベントを選択` と `編集 → のり` を順に実行する。Cubaseではメニューを実際に開かないと `のり` が無視されるため、0.8では各メニューを明示的に開いてから項目を押す。
- 初回はmacOSのアクセシビリティ許可が必要。
- アドホック署名のため、再ビルド後は同じアプリ名でもアクセシビリティ登録を一度削除し、完成した `.app` を追加し直す。2026-07-24、旧登録を削除してデスクトップ版0.9.1（build 11）を追加し直し、Logic操作が通ることを確認済み。
- Cubase 15実プロジェクト `BURN` で実機検証済み。`Stage-73 V2 01` と `Modular V3 01` の各8コード（1〜9小節）を、並び順・位置・長さを維持した一つのMIDIパートへ自動結合できた。
- デスクトップ版は0.9.1（build 11）へ上書き済み。青地に `C7`、音符の橋、カタカナ `コード` を大きく配置した専用アイコンを組み込み、Dockへ固定済み。アプリ本体では新アイコンを確認済みだが、Dockタイルだけ白い仮表示が残る。2026-07-24、LaunchServicesへの再登録は承認後も実行基盤側のエラーで拒否され、表示更新待ち。
- 0.2で、LogicのDrummer／Bass Player／Keyboard Player等の選択Session Playerを通常MIDIリージョンへ変換するボタンと、選択MIDIをフォーマット1 MIDIとして書き出す画面を開くボタンを追加。
- Apple公式の現行手順は、Session PlayerリージョンをControlクリックし、`変換 → MIDIリージョンに変換`。その後、選択リージョンを `ファイル → 書き出す → 選択範囲をMIDIファイルとして...` でStandard MIDI Fileとして書き出せる。
- Logicの変換コマンドはメインメニュー経路を日本語／英語で試し、取得できない場合は安全に停止してControlクリックによる手動変換を画面内で案内する。
- Logic Pro 12.3のインストール、アプリ0.2のビルド・署名・起動・画面レイアウト・デスクトップ配置は確認済み。実プロジェクトを使うCubase／Logicの変換、Logic保存画面、MIDI往復はユーザーが手動検証する。
- 0.2ではCubaseの背面に隠れてドラッグできなかったため、0.2.1でウインドウをフローティング階層へ変更し、全Spaces／フルスクリーン補助表示にも対応。ビルド・署名・起動・画面表示は確認済み。
- デスクトップ版0.2.1への上書きはユーザーが明示承認済み。しかし承認後の再実行でもCodexの承認サービスがモデル非対応エラーを返し、未完了。Vault内の0.2.1完成版を現在起動している。
- ユーザーから「フローティングしていない。ドラッグよりコピー＆ペーストでよい」とフィードバック。デスクトップ側は上書き失敗により旧版のままだった。
- 0.3で「MIDIをコピー」を追加。選択したMIDIをmacOSクリップボードへファイルURLと `public.midi-audio` データの両方で格納し、Cubase／Logic側で `Command-V` を試せる。ビルド・署名・起動・画面表示は確認済み。
- DAW側がこの形式の貼り付けを受け付けるかは未検証。不可の場合はコピー方式への継ぎ足し修正をせず、Chord BridgeからCubase／LogicのMIDI読み込み画面を直接開く方式へ切り替える。
- ユーザー実機で「一つのコードしか送れない」と判明。Cubase画面では1〜8小節に複数コードが並ぶ一方、受渡対象はAmin7一つのMIDIパートになっていた。
- 0.4でCubase側処理を修正。コードをMIDI化した後、変換先 `Chord Bridge` トラック上の全イベントを `編集 → 選択 → 選択トラック上の全イベントを選択` で選択し、`編集 → のり` で時間位置・長さ・並び順を維持した一つのMIDIパートへ結合する。
- 0.4のビルド・署名・起動・新ボタン表示は確認済み。実行時に、再ビルドでmacOSのアクセシビリティ許可が外れていることが判明し、実機変換は停止。ユーザーがChord Bridge 0.4をアクセシビリティで再許可した後に確認する。
- ユーザー確認により、フローティング表示自体は解決済み。
- 0.8でCubaseメニューを明示的に開いてから選択・結合する方式へ修正し、実機で自動結合まで確認済み。0.4時点の未検証状態は解消。
- Logic Pro 12.3の実画面では、選択リージョンの右クリックに `選択範囲をMIDIファイルとして…`、`書き出す → 1個のリージョンをオーディオファイルとして…` がある。Session Playerは右クリックの `変換 → MIDIリージョンに変換` を使う。
- 0.9に `MIDIで受け取る` と `オーディオで受け取る（WAV／AIFF）` を追加し、受渡カードもMIDI／WAV／AIFF／CAF等に対応。デスクトップ配置・権限・起動は確認済み。
- 2026-07-24、Logic 12.3のBass Player Session Playerリージョンを選択し、Chord Bridgeの `MIDIで受け取る` からMIDIリージョンへの変換と「MIDIファイルを別名で保存」画面の表示まで実機で成功。`/Users/yoshiakinagumo/Desktop/プロジェクト 1.mid`（320バイト）として保存し、Chord Bridgeの受渡カードへ読み込めることも確認した。
- 上記の実機確認で、変換後に選択が元のコードMIDI `Amin7` へ飛び、Session Player演奏ではなくCubaseから渡したコードが書き出される不具合を確認。変換前の選択Session Playerリージョンの画面位置を保持し、変換後に同じ位置を選び直して書き出す0.9.2（build 12）を実装・ビルド済み。2026-07-24、デスクトップ版への上書きはユーザー承認後も実行基盤の承認エラーで拒否され、反映待ち。
- Logicのリージョンそのものは別アプリへ直接ドラッグできない。Chord Bridgeの `MIDIで受け取る`／`オーディオで受け取る` でファイルを書き出し、保存後に `ファイルを選ぶ…` で受渡カードへ載せる。

### ACE Studio 2.0（検討中）

- 目的は、頭の中で鳴っている編曲をハミングからMIDI化し、AI楽器・生成レイヤーを使ってCubaseで短時間に作品へすること。本人が歌とギターを担当し、ACEは演奏できないパートを補う位置づけ。
- Logic Session PlayerをCubaseへ移すためのChord Bridge開発、複数の生成音源購入、手作業のMIDI打ち込みをどこまで置き換えられるかが導入判断の中心。
- ACEの7日間返金保証は、試用開始後に集中時間が取れないと判断材料が不足する。即購入せず、実際の一曲を使って合計6時間程度（ハミング→MIDI・AI楽器／生成レイヤー・Music Enhancer／Cubase書き出し）を確保できる時期に試す方針を検討する。
- Cubase次期版の公式機能発表も比較材料にするが、2026-07-27時点ではCubase 16の機能・発売日は公式未発表。

#### Cubase → Logic → Cubase の制作フロー

- Cubaseを曲構成・テンポ・コード・最終ミックスの正本とする。LogicはSession Playerによる演奏生成に使う。
- 往路: Cubaseコードパッド → コードトラックへ配置／録音 → コードをMIDIへ変換 → Logicへ渡す → Logicのコードトラックで解析 → Session Playerに演奏させる。
- 復路: LogicのDrummer／Bass／Keyboard等のSession Playerリージョンを通常MIDIへ変換 → Standard MIDI Fileとして書き出す → Cubaseへ読み込み → Cubaseで音源差し替え・編集・ミックス。
- 一つの `Chord Bridge` アプリに「Cubase → Logic」と「Logic → Cubase」の二方向ボタン、曲ごとの受渡トレイ、Drums／Bass／Keys別のMIDIカードを持たせる方針。
- DAW固有のコードトラック、Session Player設定、音源、プラグイン、ミックス設定は直接相互変換しない。受け渡す正本はMIDIノート・ベロシティ等の演奏データ。
- コード名の再解析、テンション／分数コード、ドラムノート配列は往復後に確認が必要。テンポと曲構成はCubase側を基準に維持する。

### Mac・PC操作／周辺機器

- nanoKEY StudioのBluetooth接続は上記Cubaseノートに統合。
- 音楽制作に直接関係するMac/PC操作だけを対象とする。

## つまずきから引く

- Bluetoothスキャンが終わらない → 別のMac/iPhone/iPadへの接続を切る。
- USBでは動くがBluetoothでMIDI Remoteが動かない → USBとBluetoothは別ポート。Bluetooth用サーフェスを使う。
- XYパッドが音程を鳴らす → Touch ScaleではなくX-Yモード。
- XYの動きがおかしい → X＝CC16、Y＝CC17、各0〜127を確認。
- CC番号が不明 → KORG KONTROL Editorで左の `X-Y` を選び、詳細欄を下へスクロール。中央図だけで判断しない。
- `.drm` など専用形式の自作ファイルが読み込み時に壊れた → 壊れた生成物への継ぎ足し修正を繰り返さない。まず正常動作する正本をコピーし、変更点を最小限に限定して最初から作り直せないか検討する。

## AIの作業原則（今回の失敗から）

- うまくいかなかった方式を、その前提のまま何度も修正し続ける傾向に注意する。
- 1回目の修正でも同じ症状が残った場合は、追加修正より先に「正常な正本から再作成」「別経路」「変更範囲の縮小」を検討する。
- 専用ファイル形式では、見た目のXML検証や行数だけで成功と断定しない。実際のアプリで読み込めることを成功条件にする。
- 今回のBFDドラムマップでは、正常版にあった `Order`、`OutputDevices`、`Flags` を落とした自作版がCubaseで全行Kickとして展開された。その不良版を修正し続けたのが失敗。
- 解決策は、正常版 `BFD3.drm` を正本としてMap部分を完全保持し、マップ名とOrderだけを変更して新規作成することだった。

## 更新ログ

→ **[[🎛 音楽制作環境 更新ログ]]** へ分離（2026-07-31）。現在の設定は上の「現在の確定設定」が正なので、**通常は開かなくてよい。**
設定を変えたときは、本体を直したうえで更新ログへ1ブロック追記する。
