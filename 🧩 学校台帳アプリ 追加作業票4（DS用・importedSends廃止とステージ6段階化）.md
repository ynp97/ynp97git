---
種別: 実装作業票 / 外部AI（DS＝OpenClaw＋DeepSeek）向け
作成日: 2026-07-28
対象: `~/openclaw-apps/SchoolLedger`
渡し方: このファイルだけを渡す。Vaultの他は読ませない。
前提: 追加作業票3（見積もり調査）の報告を受けての実装指示。**方針はA＝部分修正に決定。**
---

# 学校台帳アプリ 追加作業票4 ── importedSends廃止とステージ6段階化

> [!danger] レッドライン
> 1. **`~/Library/Application Support/SchoolLedger/data.json` を開かない・読まない。** 実在する家庭の氏名と住所が入っている。構造はソースの型定義から読むこと。
> 2. 動作確認は**架空の名前だけ**で行う。実データを外部へ出さない。
> 3. **移行コードを書く前に、必ず変換前バックアップの処理を先に実装する**（下記4-2）。

---

## 0. 方針の決定：**A＝必要な部分だけ直す**

あなたの報告ではB（作り直し）を推していたが、運営側の判断で**A（部分修正）**に決めた。理由：

1. 見積もりの表が内部矛盾している。1,200行を新規に書くほうが400行を直すより短時間かつ低リスク、は通常成立しない。実際のコードは3,129行あるので「作り直し1,200行」という数字も実態と合わない。
2. **初版で見つかった5つのバグの修正が、コード中にコメント付きで残っている。** 例：`DataModels.swift` 113〜128行と143〜153行に、ラベル管理が `batch: null` を出すこと、辞書に一致しない住所で `zone` が全部 null になること、そのため合成デコーダでは失敗するので `decodeIfPresent` で受けること、が明記されている。作り直すとこれらを踏み直す危険がある。
3. **実データが入っている。** 作り直しは移行コードも新品になり、初回実行で記録を壊すリスクが上がる。

**よって、既存コードを活かして必要箇所だけ直すこと。作り直さない。** 触る範囲はおよそ490行／3,129行。

なお、あなたの調査報告の**コードに関する記述は実コードと突き合わせて検証済みで、すべて正確だった**（捏造なし）。影響範囲の把握は信頼して使う。

---

## 1. importedSends を廃止し、people に統合する

### 1-1. モデル（`Models/DataModels.swift`）

- `SchoolLedgerData.importedSends` フィールドを**削除**（`init(from:)` の該当行も）。
- `ImportedSend` 型を**削除**。
- `SendsEnvelope` は**残す**。ただし `sends: [ImportedSend]` を受けられなくなるので、**取り込み専用の軽い構造体**（例 `IncomingSend`）を新設して受ける。**null 対応の `init(from:)` は旧 `ImportedSend` からそのまま移植すること**（`batch`・`zone.*` が null で来る。ここを落とすと初版と同じバグが再発する）。
- `ZoneInfo` 型は**残す**。置き場所を変えるだけ。
- `Person` に **`var zone: ZoneInfo? = nil`** を追加（ラベル管理から来ていない人は nil）。
- `Person.linkedSendId` を**削除**。

### 1-2. 取り込み（`ViewModels/DataStore.swift` の `importSends(from:)`）

- 読み込んだ `sends[]` の1件ずつを、**`Person` として `data.people` に直接追加する**。変換は次のとおり。

| 取り込みJSON | Person |
| --- | --- |
| `name` | `displayName` |
| `postal` | `address.postal` |
| `address` | `address.text` |
| `sentAt` | `firstContactDate`、かつ `events` の1件目 `{ date: sentAt, stage: "送付" }` |
| `zone` | `zone`（そのまま保持。**再計算しない**） |
| `tag`（既定「データパレット」） | `source` |
| `batch` | `sourceDetail` に `"batch:3"` の形で残す（無い場合は空） |
| `id` / `matchedPersonId` | 使わない。Personには新しいUUIDを振る |

- **重複判定は `data.people` に対して行う**（旧実装は `importedSends` に対してだった）。`displayName` と `address.postal` が同じ人がいたらスキップ。
- `updateImportedStats()` は**削除**。`importedSendsCount` / `unmatchedSendsCount` も削除。取り込み結果メッセージの距離帯内訳は、`data.people` の `zone` から作るよう書き換えて**残す**（初版でこれを出すようにした経緯があるので消さないこと）。

### 1-3. 紐づけ機能をまるごと削除

- `DataStore.matchPerson()` / `unmatchPerson()` を削除。
- `DataStore.deletePerson()` 内の unmatch 処理を削除。
- `DataStore.tagUsageCount()` の `importedSends` 参照を削除（`people` だけ数える）。
- `Views/PersonDetailView.swift` の `MatchSection` と `MatchSheet` を削除。代わりに、その人が `zone` を持っている場合だけ**距離帯を表示する小さな欄**を置く（最寄り駅・合計分・帯・精度）。
- `Views/MailingEnrollmentView.swift` の `ImportedSendListView` / `ImportedSendRowView` / `StatChip` を削除。「送付済み取込」タブは、**ファイルを選んで取り込むボタンと、取り込み結果メッセージだけ**の簡素な画面にする（取り込んだ人は問い合わせ一覧に出るので、専用の一覧は不要）。

---

## 2. ステージを8段階 → 6段階にする

### 2-1. 新しいステージ

```swift
enum StageOptions {
    static let stages = [
        "送付",
        "電話・メールあり",
        "見学予約",
        "見学・個別相談実施",
        "体験",
        "入学"
    ]
}
```

- `保留` / `見送り` は**廃止**。止まっている段階が、そのままその人の状態。
- `feel`（手応え1〜5）と `comment` は**そのまま残す**。主に `見学・個別相談実施` で使う。
- イベント履歴型（進むたびに1行足す・上書きしない）は**変えない**。

### 2-2. 直す箇所

- `Person.currentStage` のデフォルト値 `"新規問い合わせ"` → `"送付"`。
- `DataStore.addPerson()` の初期イベント `"新規問い合わせ"` → **`"電話・メールあり"`**（手入力で登録するのは、相手から接触があった人だから。取り込み経由は1-2のとおり `"送付"` が入る）。
- `StatisticsCalculator.funnelStats()` の `StageOptions.stages.prefix(6)` → **`StageOptions.stages`**（全6段階）。
- **`"入学・入会"` という文字列参照をすべて `"入学"` に置換**する。少なくとも次の5か所にある：`sourceStats` / `feelStats` / `zoneStats` / `areaStats` / `todayActions`。**grep で全部拾うこと。**
- `Views/InquiriesView.swift` の `StageBadge` の色分けを新6段階へ。
- `Views/MonthlyView.swift` の `FunnelSection.funnelColor` を新6段階へ。

---

## 3. 統計の書き換え（`ViewModels/StatisticsCalculator.swift`）

### 3-1. 「反応あり」の新しい定義

```
反応あり ＝ その人の events に "送付" 以外のステージが1つでも含まれる
反応なし ＝ events が "送付" だけで止まっている
```

### 3-2. `zoneStats(from:)`

- 走査対象を `data.importedSends` → **`data.people` のうち `zone` が nil でない人**へ変更。
- `sent` ＝ その距離帯の人数（母数）。
- `responded` ＝ そのうち3-1で「反応あり」の人数。`matchedPersonId` で辿る処理は不要。
- `visited` / `enrolled` はこれまでどおり `events` から判定（ステージ名は新しいものに）。

### 3-3. `areaStats(from:)`

- 同様に `data.people`（`zone` が nil でない人）を走査。
- 住所は `Person.address.text` から取る。`extractArea` はそのまま使える。

### 3-4. 変わらないもの

`sourceStats` / `feelStats` / `monthlyStats` / `currentMonthInquiries` / `currentMonthMailings` / `latestTotalEnrollment` / `netGrowth` は、ステージ名の文字列置換以外は**変更不要**。

---

## 4. 既存データの移行（version 1 → 2）

### 4-1. 読み替え表（**運営側で確定済み。あなたは変更しないこと**）

| 旧ステージ | 新ステージ |
| --- | --- |
| `新規問い合わせ` | **タグで分ける**：`source` が「データパレット」なら `送付`、それ以外はすべて `電話・メールあり` |
| `資料請求` | `送付` |
| `見学・個別相談予約` | `見学予約` |
| `見学・個別相談実施` | `見学・個別相談実施`（変更なし） |
| `体験` | `体験`（変更なし） |
| `入学・入会` | `入学` |
| `保留` | **そのイベントを削除**し、直前のイベントを最新とする。ただし `Person.note` の末尾に `"[移行] 保留だった（2026-07-28時点）"` を追記して事実を残す |
| `見送り` | **そのイベントを削除**し、直前のイベントを最新とする。ただし `Person.note` の末尾に `"[移行] 見送りだった（2026-07-28時点）"` を追記して事実を残す |

※ `新規問い合わせ` は `addPerson` が全レコードに自動で付ける初期イベントなので、**手入力した全員が該当する**。取りこぼさないこと。

### 4-2. `importedSends` の変換

- `matchedPersonId` が入っているものは、**その `Person` に `zone` だけ書き込む。新しい Person を作らない**（重複させない）。
- `matchedPersonId` が nil のものは、1-2の変換表に従って**新しい `Person` として登録**する（初期イベント `送付`）。
- 変換後、`importedSends` は消える（フィールドごと無くなる）。

### 4-3. 移行の実行方法

- **アプリ起動時の自動変換**にする（別コマンドは実行し忘れる）。
- **変換前に必ずバックアップを2か所へ取る。バックアップに失敗したら移行を中止し、画面にその旨を出すこと。**
  1. `~/Library/Application Support/SchoolLedger/backups/data-v1-移行前-YYYYMMDD.json`
  2. `~/Documents/Obsidian Vault/バックアップ/学校台帳_v1最終_YYYY-MM-DD.json`
- 変換後に `version` を **2** にする。`version >= 2` なら変換をスキップ（二重変換しない）。
- 変換結果を画面に出す（例：「移行しました。人 42件、うち送付から作った人 30件、ステージ読み替え 58件」）。**3秒で消さない。**

---

## 5. 受け入れ確認（ここまで自分で確認してから完了と言うこと）

架空データで全部通ること。

1. `swift build -c release` が通る。
2. **`bash build.command` で `.app` ができ、ダブルクリックで起動する。**（素の実行ファイルだとファイル選択パネルが開かない。`swift run` で確認しない）
3. 旧形式の**架空の** `data.json`（`importedSends` あり・8段階・`保留`と`見送り`を含む）を用意し、起動して移行が走ることを確認する。バックアップが2か所にできている。
4. 移行後、`保留`/`見送り` だった人のステージが直前の段階になり、`note` に印が残っている。
5. 移行後、`新規問い合わせ` がタグに応じて `送付` / `電話・メールあり` に分かれている。
6. 2回目の起動で移行が**走らない**（version 2 なのでスキップ）。
7. ラベル管理形式の架空JSON（`batch: null`、`zone` 全 null を含む）を取り込み、**エラーにならず** `people` に登録され、初期イベントが `送付` になっている。
8. 同じJSONをもう一度取り込むと、重複としてスキップされる。
9. 統計タブで、ファネルが6段階で出る。距離帯別・住所別の反応率が出る（`sent` と `responded` の数が3-1の定義どおり）。
10. 紐づけ関連の画面・ボタンがどこにも残っていない。
11. 10回連続で起動・終了しても固まらない。

---

## 6. 完成したら報告してほしいこと

- どこまで実装したか、実装しなかったものとその理由
- `swift build` と `.app` 起動の結果
- 受け入れ確認1〜11のどれが通ってどれが通らなかったか
- 移行処理で、指示になくて自分で判断した箇所（あれば）
- 詰まった点

---

*これが最新の作業票。追加作業票2（タグ・貼り付け取り込み）の未実装分は、これが終わってから着手する。*
