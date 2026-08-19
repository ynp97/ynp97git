# eBay Record Lister

レコードをeBayへ出品するためのローカル管理ツールです。ブラウザだけで動き、商品データはブラウザのlocalStorageに保存されます。

## 開き方

`index.html` をブラウザで開きます。

## できること

- レコードの商品情報を登録・編集
- 盤質、ジャケット状態、帯、インサート、型番を管理
- 仕入れ、送料、梱包、手数料、為替から商品価格と購入者総額を計算
- 送料別 / 送料無料を切り替え、送料別ではeBayのPrice欄に入れる商品価格を分けて表示
- 英語タイトルと説明文のたたき台を生成
- eBay出品画面へ貼るためのコピペ用パックを生成
- タイトル、価格/SKU、Item specifics、Condition、Description、Shipping/Returnsを個別コピー
- eBay sold / active、Discogs、Popsike、Yahoo Auctionsの確認リンクを生成
- Discogs Release URL / ID から基本データを取り込み
- 写真ファイルからバーコード検出と入力候補の反映
- OCRテキストから型番、年、回転数、盤種などを推定
- CSVで出力
- JSONでバックアップ、復元

## 次に足す候補

- eBayの実テンプレートに合わせたCSV列
- 写真からの本格OCR
- SQLite保存
- sold/completed検索のメモ欄
- ヤフオク向け出品文
