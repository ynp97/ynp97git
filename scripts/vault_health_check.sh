#!/bin/zsh

set -u

ROOT="${0:A:h:h}"
cd "$ROOT" || exit 1

section() {
  printf '\n=== %s ===\n' "$1"
}

count_lines() {
  awk 'END { print NR + 0 }'
}

section "Vault概要"
printf '容量: '
du -sh . | awk '{print $1}'
printf '全ファイル数（.git/.obsidian除外）: '
find . -type f -not -path './.git/*' -not -path './.obsidian/*' | count_lines
printf 'Markdown数: '
find . -type f -name '*.md' -not -path './.git/*' | count_lines

section "再生成キャッシュ"
cache_list="$(find アプリ本体 -type d \( -name 'DerivedData*' -o -name '.build' -o -name 'node_modules' -o -name '__pycache__' -o -name '.pytest_cache' \) -prune -print 2>/dev/null)"
if [[ -n "$cache_list" ]]; then
  print -r -- "$cache_list"
else
  echo 'なし'
fi

section "空Markdown"
empty_md="$(find . -type f -name '*.md' -empty -not -path './.git/*')"
if [[ -n "$empty_md" ]]; then
  print -r -- "$empty_md"
else
  echo 'なし'
fi

section "OS・一時ファイル"
junk="$(find . -type f \( -name '.DS_Store' -o -name '*.tmp' -o -name '*~' \) -not -path './.git/*')"
if [[ -n "$junk" ]]; then
  print -r -- "$junk"
else
  echo 'なし'
fi

section "壊れたシンボリックリンク"
broken="$(find . -type l ! -exec test -e {} \; -print)"
if [[ -n "$broken" ]]; then
  print -r -- "$broken"
else
  echo 'なし'
fi

section "完全重複Markdown"
hash_file="$(mktemp)"
find . -type f -name '*.md' -not -empty -not -path './.git/*' -print0 \
  | xargs -0 shasum | sort > "$hash_file"
awk '
  BEGIN { previous = ""; count = 0 }
  {
    hash = $1
    sub($1 "  ", "")
    if (hash != previous) {
      if (count > 1) {
        for (i = 1; i <= count; i++) print paths[i]
        print ""
      }
      delete paths
      count = 0
      previous = hash
    }
    count++
    paths[count] = $0
  }
  END {
    if (count > 1) for (i = 1; i <= count; i++) print paths[i]
  }
' "$hash_file"
rm -f "$hash_file"

section "ジャーナル写真（確認のみ）"
photo_count="$(find media/ジャーナル写真 -type f 2>/dev/null | count_lines)"
gallery_count="$(rg -c '^!\[\[' 'ジャーナル/ジャーナル写真一覧.md' 2>/dev/null || echo 0)"
printf '写真ファイル: %s\n' "$photo_count"
printf '写真一覧の埋め込み: %s\n' "$gallery_count"
if [[ "$photo_count" == "$gallery_count" ]]; then
  echo '状態: 一致'
else
  echo '状態: 要確認（件数が一致しません）'
fi

section "50MB以上の大容量ファイル"
find . -type f -size +50M -not -path './.git/*' -print \
  | while IFS= read -r file; do
      size="$(du -h "$file" | awk '{print $1}')"
      printf '%s  %s\n' "$size" "$file"
    done

printf '\n診断のみ完了しました。ファイルの削除・移動・変更はしていません。\n'
