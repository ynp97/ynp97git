# ds-apps — DS開発用リポジトリ

## ルール

1. **main への直接 push 禁止** → 作業ごとに `ds/作業名` ブランチを作成し push すること
2. `apps/` には委任されたアプリだけが入る。勝手にアプリを追加しない
3. 実データ（氏名・住所など）・APIキー・証明書・Vault は絶対に入れない
4. 作業完了時は `docs/作業票/` に作業票を置くこと

## ブランチ運用

```bash
# 作業開始
git checkout main
git pull
git checkout -b ds/アプリ名

# 作業完了
git add .
git commit -m "作業票: XXX"
git push origin ds/アプリ名
# main には push しない！
```
