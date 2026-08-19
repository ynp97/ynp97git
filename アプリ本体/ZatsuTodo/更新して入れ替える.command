#!/bin/zsh
# ZatsuTodo をビルドして /Applications へ入れ替える。ダブルクリックで実行する。
project_dir="/Users/yoshiakinagumo/Documents/Obsidian Vault/アプリ本体/ZatsuTodo"
cd "$project_dir"
echo "ZatsuTodo を更新します（1〜2分かかることがあります）"
echo ""
if zsh "$project_dir/install_update.sh"; then
    echo ""
    echo "✅ 更新できました。TODOアプリを開いて確認してください。"
else
    echo ""
    echo "❌ 失敗しました。上に出ているエラーを丸ごとコピーして貼ってください。"
fi
echo ""
echo "このウインドウは閉じて構いません。"
