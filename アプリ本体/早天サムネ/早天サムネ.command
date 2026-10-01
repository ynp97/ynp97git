#!/bin/zsh
cd "${0:A:h}"
/usr/bin/python3 "月間データ更新.py"
open -a 'Google Chrome' index.html
