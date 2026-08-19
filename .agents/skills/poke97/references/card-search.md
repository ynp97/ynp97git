# 公式カード条件検索

## ローカル全件検索（現行スタンダード）

- 実体: `アプリ本体/Poke97-Card-Lab/`
- 引き継ぎ: `アプリ引き継ぎ/W poke97 カード研究室.md`
- AI用入口: `python3 search_cards.py ...`
- 公式全件を取り込んだDBを先に機械検索し、候補だけをAIが考察する。毎回全詳細ページを会話へ読み込まない。
- 検索前に準備済み件数と総数が一致するか確認する。不一致なら回答範囲を明記するか更新する。
- ローカルDBは検索用の写しであり、カード本文・ルールの最終正本は下記公式ページ。

## 正本

- 検索画面: `https://www.pokemon-card.com/card-search/index.php`
- 検索API: `https://www.pokemon-card.com/card-search/resultAPI.php`
- 個別詳細: `https://www.pokemon-card.com/card-search/details.php/card/{cardID}`

日本語カードの名前、テキスト、レギュレーション、カード特性はここを正本にする。APIは公式カード検索画面が使うJSONエンドポイント。仕様が公開保証された固定APIではないため、応答しない場合は検索画面を使う。

## 必須の確認

- JSONの `result` が `1` か確認する。
- `searchCondition` に、意図した条件が全て出ているか確認する。出ていない条件は無視されている。
- `hitCnt` を該当数、`maxPage` を全ページ数とする。`cardList` は1ページ分で、各件に `cardID`、カード名、画像パスがある。
- 2ページ目以降は同じ条件に `page=2` のように追加する。
- 同名でも `cardID` が異なれば別版。勝手に重複削除しない。

## 主なパラメータ

URLのクエリーとして指定する。チェック項目は値 `1`。

| 自然言語の条件 | パラメータ |
|---|---|
| 名前・カード本文 | `keyword=文字列&sm_and_keyword=true` |
| スタンダード | `regulation_sidebar_form=XY&regulation=XY` |
| エクストラ | `regulation_sidebar_form=BW&regulation=BW` |
| 殿堂 | `regulation_sidebar_form=DP&regulation=DP` |
| すべて | `regulation_sidebar_form=all&regulation=all` |
| ポケモン / トレーナーズ / エネルギー | `se_ta=pokemon` / `trainer` / `energy` |
| HP下限 / 上限 | `sc_hp_s=120` / `sc_hp_e=200` |
| にげる下限 / 上限 | `sc_run_away_s=0` / `sc_run_away_e=2` |
| たね / 1進化 / 2進化 | `sc_pm_evo_0=1` / `sc_pm_evo_1=1` / `sc_pm_evo_2=1` |
| 特性あり / なし | `sc_ab_special=1` / `sc_ab_non_special=1` |
| ポケモンex / テラスタル | `sc_pm_ex3=1` / `sc_pm_terrastal=1` |
| タイプ | `sc_pm_type_grass/fire/water/electric/psychic/fighting/dark/steel/dragon/none=1` |
| 弱点 | `sc_weak_grass/fire/water/electric/psychic/fighting/dark/steel/dragon/none=1` |
| 抵抗力 | `sc_regist_grass/fire/water/electric/psychic/fighting/dark/steel/dragon/none=1` |
| ワザのエネルギー | `sc_ab_type_grass/fire/water/electric/psychic/fighting/dark/steel/dragon/none/void=1` |
| グッズ / ポケモンのどうぐ / サポート / スタジアム | `sc_tr_tr=1` / `sc_tr_goods=1` / `sc_tr_sp=1` / `sc_tr_st=1` |
| 基本 / 特殊エネルギー | `sc_energy_basic=1` / `sc_energy_special=1` |
| ACE SPEC | `sc_tr_acespec=1`（トレーナーズ）または `sc_en_acespec=1`（エネルギー） |
| 古代 / 未来 | `sc_type_ancient=1` / `sc_type_future=1` |
| ミラー仕様 | `sc_rare_mirror=1` |
| レアリティ | `sc_rare_com/unc/rac/rr/ar/sr/sar/mur/ma/ur/bwr/scl/ssr/hr/chr/csr/tr=1` |
| イラストレーター | `illust=名前` |
| 商品 | `pg=公式検索画面の現行商品ID` |

フェアリーや過去カード固有の条件は、レギュレーションをすべてにし、公式検索画面の現行フォーム名を確認する。商品IDは追加・変更されるため固定表を保存しない。

## 検索例

「スタンダードで、たね、雷タイプ、HP100以下、特性あり」:

```text
https://www.pokemon-card.com/card-search/resultAPI.php?se_ta=pokemon&regulation_sidebar_form=XY&regulation=XY&sc_pm_evo_0=1&sc_pm_type_electric=1&sc_hp_e=100&sc_ab_special=1&illust=
```

実測で `searchCondition` は「カードの種別：ポケモン / 進化：たね / 特性：特性あり / タイプ：雷 / HP：～100 / レギュレーション：スタンダード」と返る。

## 回答の基本形

- 対象範囲と検索条件
- 該当数
- カード名、商品・カード番号など別版を見分ける情報
- 公式詳細ページ
- 必要な場合のみ、デッキ上の用途や条件を緩めた別案

価格は公式カード検索の対象外。価格を求められたら `auc97` の手順で、販売価格、買取価格、実成約を分けて調べる。
