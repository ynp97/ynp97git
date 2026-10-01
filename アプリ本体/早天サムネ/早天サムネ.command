#!/bin/zsh
cd "${0:A:h}"
/usr/bin/python3 "$HOME/Documents/Obsidian Vault/アプリ本体/早天サムネ/月間データ更新.py"
/usr/bin/python3 "月間データ更新.py"
/usr/bin/python3 "$HOME/Desktop/AI関係/早天配信/sync_data.py"
open yachiyo.crwebloc
